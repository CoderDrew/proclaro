-- 0025: final review fixes for slice 2b (bid review, bond cure, recap, award).
--
-- I1 / Ruling 14: after close, the originals log (void_bid_original, log_bid_original) and the bond cure
--   (submit_cure_bond, the cure branch of app.can_upload_bid_file) are allowed only while the evaluation is in
--   bid_review. A posted recap or award can no longer be contradicted by a later void or a reopened cure. Before
--   close nothing changes.
--   Lock order, the same as review_bids (open_bids_gate FOR SHARE on bids, then lock_evaluation) and set_bid_outcome
--   (evaluation only): the bids row first, then app.lock_evaluation. void_bid_original locks its target log entry
--   before the bid; no other function locks log entries, so that adds no cycle.
--   Lock mode on the bids row: FOR NO KEY UPDATE, not FOR UPDATE. Writers that take lock_evaluation first and then
--   insert a row referencing bids (set_bid_outcome, verify_resident, decide_flagged_bid, send_award_to_check,
--   post_award, recall_award, the audit rows) take FOR KEY SHARE on the bid row for the foreign key check. FOR UPDATE
--   blocks KEY SHARE, so a cure upload and an outcome save on the same bid would deadlock (bid -> evaluation versus
--   evaluation -> bid). FOR NO KEY UPDATE does not block KEY SHARE, and it still conflicts with open_bids_gate's
--   FOR SHARE and with other NO KEY UPDATE / FOR UPDATE lockers, so opening and submit/withdraw serialization hold.
--   submit_cure_bond also takes one clock reading for both the deadline check and uploaded_at (final review M1), and
--   its evaluation lock serializes it with send_recap_to_check / send_flags_to_agency (M2).
-- I2 / Ruling 13: recall_recap (recap_check -> bid_review) and recall_award (award_check -> recap_posted), sender
--   only. recall_award does not stamp award_disagreed_at, so the same pick can be re-sent or posted alone.
--   recap_draft now also returns canCheck and canRecall, so the panel disables buttons that would always fail.
-- I3: my_bid_outcome returns the posted recap's kind, so a bidder under the all-rejected memo is told so.
-- I6: a post-close void of an original counts as reviewing these bids (app.was_evaluation_reviewer).

-- ---------------------------------------------------------------------------
-- I6: app.was_evaluation_reviewer. A void made at or after the bid due time changed a bid's status after close (it
-- can make a bid non-responsive automatically), which is a review decision in effect. A void before close is mail
-- logging, not review, and does not count.
-- ---------------------------------------------------------------------------
create or replace function app.was_evaluation_reviewer(p_solicitation_id uuid, p_user uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bid_audit_log l
     where l.solicitation_id = p_solicitation_id
       and l.actor_id = p_user
       and (l.action in ('set_bid_outcome', 'verify_resident', 'send_flags_to_agency', 'send_recap_to_check')
            or (l.action = 'void_bid_original'
                and l.created_at >= (select s.bid_due_at from public.solicitations s where s.id = p_solicitation_id))));
$$;

revoke all on function app.was_evaluation_reviewer(uuid, uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- I1: log_bid_original. Error order: not_authorized -> invalid_data (no item) -> received_in_future -> unknown_bid
-- -> (after close) invalid_state unless the evaluation is in bid_review.
-- ---------------------------------------------------------------------------
create or replace function public.log_bid_original(
  p_solicitation_id uuid, p_reference text, p_version int, p_item public.original_item,
  p_received_at timestamptz default null)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_logged   timestamptz;
  v_received timestamptz;
  v_bid      public.bids;
  v_eval     public.evaluations;
  v_id       uuid;
begin
  perform app.require_office();
  if p_item is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if p_received_at > clock_timestamp() then
    raise exception 'received_in_future' using errcode = 'P0001';
  end if;

  -- Any submitted version counts here, superseded and withdrawn included: the log records the mail.
  -- FOR UPDATE on the bid row conflicts with opening's FOR SHARE (app.open_bids_gate): an entry still in flight
  -- when the office opens is waited out, and an entry that waits behind an opening is stamped after it.
  select b.* into v_bid
    from public.bids b
   where b.solicitation_id = p_solicitation_id
     and b.reference = app.normalize_bid_reference(p_reference)
     and exists (select 1 from public.bid_versions v where v.bid_id = b.id and v.version = p_version)
     for no key update of b;  -- not FOR UPDATE: see the lock-mode note at the top of 0025
  if not found then
    raise exception 'unknown_bid' using errcode = 'P0001';
  end if;

  -- Ruling 14: after close, only during bid review (bids row, then the evaluation: the review_bids order).
  if app.bids_closed(v_bid.solicitation_id) then
    v_eval := app.lock_evaluation(v_bid.solicitation_id);
    perform app.require_stage(v_eval, 'bid_review');
  end if;

  -- Stamped on the database's wall clock after the lock is held, not at transaction start: an entry whose
  -- transaction began before the due time but that commits after it is logged after it, and does not count.
  -- received_at defaults to the same instant, so received_at <= logged_at holds and neither is in the future.
  v_logged   := clock_timestamp();
  v_received := coalesce(p_received_at, v_logged);

  insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by,
                                       logged_at)
  values (v_bid.solicitation_id, v_bid.id, v_bid.reference, p_version, p_item, v_received, auth.uid(), v_logged)
  returning id into v_id;

  perform app.bid_audit(v_bid, 'log_bid_original',
                        jsonb_build_object('entry_id', v_id, 'reference', v_bid.reference, 'version', p_version,
                                           'item', p_item, 'received_at', v_received));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- I1: void_bid_original. Error order: not_authorized -> reason_required -> not_found -> (after close) invalid_state
-- unless the evaluation is in bid_review -> invalid_state (the target is itself a void) -> already_voided.
-- ---------------------------------------------------------------------------
create or replace function public.void_bid_original(p_entry_id uuid, p_reason text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_target public.bid_original_log;
  v_bid    public.bids;
  v_eval   public.evaluations;
  v_id     uuid;
begin
  perform app.require_office();
  if v_reason = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;

  -- Lock the target so two concurrent voids queue; the second then sees the first (unique index as backstop).
  select * into v_target from public.bid_original_log e where e.id = p_entry_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  -- Ruling 14: after close, only during bid review. The bids row first, then the evaluation (the review_bids order).
  if app.bids_closed(v_target.solicitation_id) then
    -- NO KEY UPDATE, not FOR UPDATE: see the lock-mode note at the top of 0025.
    select b.* into v_bid from public.bids b where b.id = v_target.bid_id for no key update;
    v_eval := app.lock_evaluation(v_target.solicitation_id);
    perform app.require_stage(v_eval, 'bid_review');
  end if;

  if v_target.voids_entry_id is not null then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.bid_original_log v where v.voids_entry_id = v_target.id) then
    raise exception 'already_voided' using errcode = 'P0001';
  end if;

  insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, voids_entry_id, reason,
                                       logged_by)
  values (v_target.solicitation_id, v_target.bid_id, v_target.reference, v_target.version, v_target.item,
          v_target.id, v_reason, auth.uid())
  returning id into v_id;

  select * into v_bid from public.bids b where b.id = v_target.bid_id;
  perform app.bid_audit(v_bid, 'void_bid_original',
                        jsonb_build_object('entry_id', v_id, 'voids_entry_id', v_target.id, 'reason', v_reason));
  return v_id;
end;
$$;

revoke all on function public.log_bid_original(uuid, text, int, public.original_item, timestamptz),
  public.void_bid_original(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.log_bid_original(uuid, text, int, public.original_item, timestamptz),
  public.void_bid_original(uuid, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- I1: cure uploads only during bid review (storage rule). Before close, the 0009 rule; after close, the caller's own
-- bid while its cure is pending and the evaluation (if created yet) is in bid_review.
-- ---------------------------------------------------------------------------
create or replace function app.can_upload_bid_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bids b
    where b.id = app.path_bid_id(p_name)
      and b.bidder_org_id = app.my_org()
      and (app.bidding_open(b.solicitation_id)
           or (app.bids_closed(b.solicitation_id)
               and coalesce((select e.stage from public.evaluations e where e.solicitation_id = b.solicitation_id),
                            'bid_review') = 'bid_review'
               and (select c.status from app.bond_cure(b.id) c) = 'pending'))
  );
$$;

-- ---------------------------------------------------------------------------
-- I1: submit_cure_bond. Order: not_authorized -> not_found -> invalid_state (not closed) -> invalid_state (stage is
-- not bid_review) -> invalid_state (no bond to cure) -> cure_closed (clock after the locks, Ruling 8) -> invalid_data
-- (path/name) -> invalid_bid (file_missing). Locks: the bid row, then the evaluation.
-- ---------------------------------------------------------------------------
create or replace function public.submit_cure_bond(p_bid_id uuid, p_path text, p_file_name text)
returns timestamptz
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid     public.bids;
  v_eval    public.evaluations;
  v_due_bid timestamptz;
  v_status  text;
  v_due     timestamptz;
  v_version int;
  v_obj     storage.objects;
  v_at      timestamptz;
begin
  perform app.require_bidder();
  -- The caller's own bid, locked FOR NO KEY UPDATE (inline rather than app.lock_bid, whose FOR UPDATE would block
  -- the FK KEY SHARE of writers holding the evaluation lock: see the lock-mode note at the top of 0025).
  -- Another org's bid is never locked and reads as not_found.
  select b.* into v_bid from public.bids b
   where b.id = p_bid_id and b.bidder_org_id = app.my_org()
   for no key update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if not app.bids_closed(v_bid.solicitation_id) then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  -- Also freezes the cure deadline (Ruling 3).
  v_eval := app.lock_evaluation(v_bid.solicitation_id);
  perform app.require_stage(v_eval, 'bid_review');
  select c.status, c.due_at into v_status, v_due from app.bond_cure(v_bid.id, now()) c;
  -- 'failed' falls through to the clock check below, which always refuses it with cure_closed.
  if v_status not in ('pending', 'failed') then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  -- One clock reading for the check and the stamp, so a recorded upload is always before the deadline.
  v_at := clock_timestamp();
  if v_at >= v_due then
    raise exception 'cure_closed' using errcode = 'P0001';
  end if;

  select s.bid_due_at into v_due_bid from public.solicitations s where s.id = v_bid.solicitation_id;
  if p_path is null or app.path_bid_id(p_path) is distinct from v_bid.id
     or btrim(coalesce(p_file_name, '')) = ''
     or exists (select 1 from public.bid_version_files vf where vf.path = p_path)
     or exists (select 1 from public.bid_draft_files df where df.path = p_path)
     or exists (select 1 from public.bid_cure_files cf where cf.path = p_path) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  select o.* into v_obj from storage.objects o
   where o.bucket_id = 'bid-files' and o.name = p_path
     and o.metadata->>'size' ~ '^[0-9]{1,18}$' and o.metadata->>'eTag' is not null;
  if not found then
    raise exception 'invalid_bid' using errcode = 'P0001', detail = 'file_missing';
  end if;
  -- New data after close only: an object uploaded before the bid due time (a leftover draft file) is refused.
  if v_obj.created_at < v_due_bid then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  v_version := app.latest_version(v_bid.id);
  insert into public.bid_cure_files (bid_id, version, path, file_name, object_id, object_size, object_etag,
                                     uploaded_by, uploaded_at)
  values (v_bid.id, v_version, p_path, left(btrim(p_file_name), 200), v_obj.id, (v_obj.metadata->>'size')::bigint,
          v_obj.metadata->>'eTag', auth.uid(), v_at);
  perform app.bid_audit(v_bid, 'submit_cure_bond', jsonb_build_object('version', v_version, 'path', p_path));
  return v_at;
end;
$$;

revoke all on function public.submit_cure_bond(uuid, text, text) from public, anon, authenticated, service_role;
grant execute on function public.submit_cure_bond(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- I2 / Ruling 13: recall_recap. The office user who sent the recap (or memo) to check takes it back to bid review,
-- e.g. when no other office user may check it. Error order: not_authorized (not office) -> sealed -> invalid_state
-- (stage) -> not_authorized (not this draft's sender). Clears the draft; one audit row.
-- ---------------------------------------------------------------------------
create function public.recall_recap(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval public.evaluations;
begin
  perform app.require_office();
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'recap_check');
  if v_eval.recap_preparer_id is distinct from auth.uid() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  update public.evaluations
     set stage = 'bid_review', recap_draft = null
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, null, auth.uid(), 'recall_recap',
          jsonb_build_object('kind', v_eval.recap_draft ->> 'kind'));
end;
$$;

-- ---------------------------------------------------------------------------
-- I2 / Ruling 13: recall_award. The office user who sent the award to check takes it back to recap_posted. Unlike
-- disagree_award it does not stamp award_disagreed_at, so the same pick can be sent again or posted alone. Error
-- order: not_authorized (not office) -> sealed -> invalid_state (stage) -> not_authorized (not this round's sender).
-- ---------------------------------------------------------------------------
create function public.recall_award(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval public.evaluations;
  v_pick public.award_picks;
begin
  perform app.require_office();
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'award_check');
  if v_eval.award_preparer_id is distinct from auth.uid() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  v_pick := app.latest_award_pick(p_solicitation_id);
  update public.evaluations
     set stage = 'recap_posted'
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, v_pick.bid_id, auth.uid(), 'recall_award',
          jsonb_build_object('pick_id', v_pick.id, 'bid_id', v_pick.bid_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- recap_draft (0022, replaced): also returns canCheck (recap_check, and the caller neither sent it nor reviewed these
-- bids) and canRecall (recap_check, and the caller sent it). Same gates; writes nothing beyond the gate's FOR SHARE.
-- ---------------------------------------------------------------------------
create or replace function public.recap_draft(p_solicitation_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_draft    jsonb;
  v_name     text;
  v_stage    public.evaluation_stage;
  v_preparer uuid;
  v_checking boolean;
begin
  perform app.open_bids_gate(p_solicitation_id);
  select e.recap_draft, p.display_name, e.stage, e.recap_preparer_id into v_draft, v_name, v_stage, v_preparer
    from public.evaluations e
    left join public.profiles p on p.user_id = e.recap_preparer_id
   where e.solicitation_id = p_solicitation_id;
  if v_draft is null then
    return null;
  end if;
  v_checking := v_stage = 'recap_check';
  return jsonb_build_object(
    'recap', v_draft,
    'preparedBy', v_name,
    'canCheck', v_checking and v_preparer is distinct from auth.uid()
                and not app.was_evaluation_reviewer(p_solicitation_id, auth.uid()),
    'canRecall', v_checking and v_preparer = auth.uid());
end;
$$;

revoke all on function public.recall_recap(uuid), public.recall_award(uuid), public.recap_draft(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.recall_recap(uuid), public.recall_award(uuid), public.recap_draft(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- I3: my_bid_outcome (0024, replaced: a new output column). Also returns the posted recaps row's kind, so a bid that
-- was accepted under an all-rejected memo is shown as rejected with the memo, not as accepted.
-- ---------------------------------------------------------------------------
drop function public.my_bid_outcome(uuid);

create function public.my_bid_outcome(p_bid_id uuid)
returns table (status text, reason text, recap_kind public.recap_kind)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_bid  public.bids;
  v_kind public.recap_kind;
begin
  perform app.require_bidder();
  select b.* into v_bid from public.bids b where b.id = p_bid_id and b.bidder_org_id = app.my_org();
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  select r.kind into v_kind from public.recaps r where r.solicitation_id = v_bid.solicitation_id;
  if v_kind is null then
    return;
  end if;
  return query select s.status, s.reason, v_kind from app.bid_review_status(v_bid.id, now()) s;
end;
$$;

revoke all on function public.my_bid_outcome(uuid) from public, anon, authenticated, service_role;
grant execute on function public.my_bid_outcome(uuid) to authenticated;
