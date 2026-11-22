-- 0030_bid_versions_addenda: bids priced against a solicitation version, and resubmit required (slice 2c, Task 5).
--
-- * bid_drafts.solicitation_version and bid_versions.solicitation_version: the solicitation version the prices were
--   entered against. Existing rows are backfilled to 1 by the column default. Bidders cannot write the draft's
--   column (no column grant): start_bid, replace_bid and publish_addendum set it.
-- * The draft reset happens at publish (constraints "Draft reset happens at publish"): when an addendum changes the
--   bid schedule, publish_addendum empties item_cents and alternate_cents of every draft of the solicitation and
--   moves it to the new version. Uploaded draft files stay.
-- * submit_bid raises stale_draft when the draft's solicitation_version is below app.last_schedule_change, and seals
--   the draft's solicitation_version into bid_versions.
-- * Resubmit required is DERIVED, never stored: app.bid_stale(bid, version) is that version's solicitation_version
--   below app.last_schedule_change. app.bid_excluded = app.is_withdrawn or app.bid_stale. After close a stale bid is
--   treated like a withdrawn one: not opened, tabulated, reviewed or counted, its prices and files stay sealed.
--   opened_bids writes a bid_close_determination row {"version": v, "reason": "resubmit_required"} for it (the 0012
--   once-per-change rule), and public.stale_bids lists it to the office.
--
-- Post-close readers and writers replaced to call app.bid_excluded instead of app.is_withdrawn (each from its latest
-- definition, R1):
--   public.opened_bids (0012), public.opened_bid_files (0012), app.bond_cure (0016), app.can_read_bid_file (0016),
--   app.bid_review_status (0018), public.set_bid_outcome (0018), public.verify_resident (0019).
-- Not replaced:
--   app.recap_bids (0022): it cross-joins app.bid_review_status, which returns no row for a stale bid, so a stale
--     bid can never reach the recap; its remaining is_withdrawn filter is redundant but harmless.
--   withdraw_bid (0010): bidder-facing, keeps is_withdrawn. my_bid_receipts, bidding_state and office_bid_index read
--     bid_withdrawals directly and are bidder-facing or pre-close; unchanged.
--   Every other post-close reader (review_bids, resident_claims, agency_flagged_bids, recap_blockers, my_bid_outcome,
--   submit_cure_bond, my_bid_cure, can_upload_bid_file) goes through one of the replaced functions.
--
-- Concurrency (publish_addendum's reset versus the bid writers). publish_addendum locks the addendum, then the
-- solicitation FOR UPDATE (app.lock_solicitation), then updates the drafts. Before this migration submit_bid locked
-- the bid, then the draft FOR UPDATE, and only then wrote bid_audit_log, whose foreign key takes FOR KEY SHARE on the
-- solicitation row. FOR UPDATE blocks KEY SHARE, so a submit that held its draft while publish held the
-- solicitation deadlocked (submit: draft -> solicitation; publish: solicitation -> draft). Fix: submit_bid and
-- replace_bid now take FOR SHARE on the solicitation row BEFORE app.lock_bid, the same order as start_bid
-- (solicitation, then bid). app.lock_bid stays the last lock, and the wall-clock check (require_before_due_clock)
-- still follows it directly (Ruling 8: a writer that waited behind a publish re-checks the clock after waiting, so
-- it cannot seal after close; bids.test.sql pins that adjacency). So every bid writer that touches a draft takes
-- solicitation -> bid -> draft, holding a solicitation lock that conflicts with publish's FOR UPDATE before it
-- touches the draft, and publish never locks a bids row: no cycle. Either publish commits first (the writer then reads the reset draft and the new version), or the writer
-- commits first (publish's draft UPDATE, a later statement, sees its draft and resets it). The stale_draft guard in
-- submit_bid stays as defense in depth: it is checked after the locks, on a fresh snapshot, and with the locks above
-- it is reachable only through a draft written outside these functions.
--
-- Errors (P0001): stale_draft (new); not_authorized, not_found, sealed, invalid_state, invalid_bid as before.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------
alter table public.bid_drafts add column solicitation_version int not null default 1
  constraint bid_drafts_solicitation_version_positive check (solicitation_version >= 1);
alter table public.bid_versions add column solicitation_version int not null default 1
  constraint bid_versions_solicitation_version_positive check (solicitation_version >= 1);
-- The 0009/0015 column grants on bid_drafts (item_cents, alternate_cents, bid_bond_choice, apprentice_commitment)
-- are column-specific, so the new column gets no update privilege. Table-level select grants cover it.

-- ---------------------------------------------------------------------------
-- Helpers (schema `app`, no API role executes them)
-- ---------------------------------------------------------------------------

-- A submitted version is stale when its prices were entered against a version older than the latest schedule change.
create function app.bid_stale(p_bid_id uuid, p_version int)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce((
    select v.solicitation_version < app.last_schedule_change(b.solicitation_id)
      from public.bid_versions v
      join public.bids b on b.id = v.bid_id
     where v.bid_id = p_bid_id and v.version = p_version), false);
$$;

-- Excluded after close: withdrawn, or resubmit required.
create function app.bid_excluded(p_bid_id uuid, p_version int)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select app.is_withdrawn(p_bid_id, p_version) or app.bid_stale(p_bid_id, p_version);
$$;

revoke all on function app.bid_stale(uuid, int), app.bid_excluded(uuid, int)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- publish_addendum: the 0029 body, with step 12 (the draft reset) implemented.
-- ---------------------------------------------------------------------------
create or replace function public.publish_addendum(
  p_addendum_id uuid,
  p_rfb_path text,
  p_bid_form_path text,
  p_addendum_path text,
  p_snapshot jsonb,
  p_bid_due_at timestamptz,
  p_funding_cents bigint)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_add         public.addenda;
  v_sol         public.solicitations;
  v_version     int;
  v_bid_due     timestamptz;
  v_funding_raw jsonb;
  v_funding_num numeric;
  v_funding     bigint;
  v_new_data    jsonb;
  v_changed     boolean;
  v_answers_due timestamptz;
begin
  -- 1. Office, then the addendum lock, then the solicitation lock.
  perform app.require_office();
  v_add := app.lock_addendum(p_addendum_id);
  v_sol := app.lock_solicitation(v_add.solicitation_id);

  -- 2. Approved, and the caller is its reviewer or checker.
  if v_add.state <> 'approved' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if auth.uid() is distinct from v_add.reviewer_id and auth.uid() is distinct from v_add.checker_id then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  perform app.require_state(v_sol, 'published');

  -- 3. Closed on the wall clock, judged after the locks (Ruling 8).
  if clock_timestamp() >= v_sol.bid_due_at then
    raise exception 'bids_closed' using errcode = 'P0001';
  end if;

  if p_rfb_path is null or p_bid_form_path is null or p_addendum_path is null
     or p_snapshot is null or p_snapshot in ('null'::jsonb, '{}'::jsonb)
     or p_bid_due_at is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  -- 4. Version n = current + 1, which is addendum number + 1; the paths are pinned to v{n}.
  v_version := v_sol.version + 1;
  if v_add.number <> v_version - 1 then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if p_rfb_path <> format('solicitations/%s/v%s/rfb.pdf', v_sol.id, v_version)
     or p_bid_form_path <> format('solicitations/%s/v%s/bid-form.pdf', v_sol.id, v_version)
     or p_addendum_path <> format('solicitations/%s/v%s/addendum.pdf', v_sol.id, v_version) then
    raise exception 'invalid_paths' using errcode = 'P0001';
  end if;

  -- 5. The due time is recomputed from the addendum's data.
  v_bid_due := app.bid_due_at(v_add.data);
  if v_bid_due is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if p_bid_due_at <> v_bid_due then
    raise exception 'bid_due_mismatch' using errcode = 'P0001';
  end if;

  -- 6. The 5-day rule applies to every addendum.
  if app.addendum_too_close(v_bid_due, clock_timestamp()) then
    raise exception 'too_close' using errcode = 'P0001';
  end if;

  -- 7. Funding: a non-negative whole number of cents, validated by the caller and kept out of the public snapshot.
  v_funding_raw := v_add.data -> 'fundingAmountCents';
  if jsonb_typeof(v_funding_raw) is distinct from 'number' then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  v_funding_num := v_funding_raw::numeric;
  if v_funding_num < 0 or v_funding_num <> trunc(v_funding_num) or v_funding_num > 9223372036854775807 then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  v_funding := v_funding_num::bigint;
  if p_funding_cents is distinct from v_funding
     or jsonb_path_exists(p_snapshot, '$.**.fundingAmountCents') then
    raise exception 'snapshot_mismatch' using errcode = 'P0001';
  end if;

  -- 8. Locked fields, re-checked against the current data.
  if exists (select 1 from unnest(app.locked_fields()) k
              where (v_add.data -> k) is distinct from (v_sol.data -> k)) then
    raise exception 'locked_field' using errcode = 'P0001';
  end if;

  -- 9. Did the bid schedule change?
  v_new_data := v_add.data - 'fundingAmountCents';
  v_changed := app.schedule_changed(v_sol.data, v_new_data);

  -- 10. Version history (the version row first: the funding change references it).
  insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path,
                                            addendum_path, bid_due_at, published_at, published_by, schedule_changed)
  values (v_sol.id, v_version, p_snapshot, p_rfb_path, p_bid_form_path, p_addendum_path, v_bid_due, now(),
          auth.uid(), v_changed);
  insert into public.solicitation_funding_changes (solicitation_id, version, funding_cents)
  values (v_sol.id, v_version, v_funding);

  -- 11. Move the current pointer under the freeze exception, then close the exception at once.
  perform set_config('app.publishing_addendum', v_sol.id::text, true);
  update public.solicitations s
     set version = v_version,
         published_snapshot = p_snapshot,
         data = v_new_data,
         bid_due_at = v_bid_due,
         rfb_path = p_rfb_path,
         bid_form_path = p_bid_form_path
   where s.id = v_sol.id and s.state = 'published';
  perform set_config('app.publishing_addendum', '', true);

  -- 12. The schedule changed: every draft of this solicitation's bids loses its prices (items have no ids, so
  --     carrying them across would guess) and is now priced against the new version. Bid writers hold FOR SHARE on
  --     the solicitation before touching a draft (see the header), so no draft write is in flight here.
  if v_changed then
    update public.bid_drafts d
       set item_cents = '{}', alternate_cents = '{}', solicitation_version = v_version
      from public.bids b
     where b.id = d.bid_id and b.solicitation_id = v_sol.id;
  end if;

  -- 13. The addendum is published.
  update public.addenda a
     set state = 'published', published_version = v_version
   where a.id = v_add.id and a.state = 'approved';

  -- 14. Audit. after_answers_due: published after the answers-due time bidders were working to (the data before
  --     this publish), read in settings.timezone.
  v_answers_due := app.local_deadline(v_sol.data -> 'answersDue');
  perform app.audit(v_sol.id, 'publish_addendum', jsonb_build_object(
    'addendum_id', v_add.id, 'number', v_add.number, 'from', 'approved', 'to', 'published',
    'version', v_version, 'schedule_changed', v_changed, 'bid_due_at', v_bid_due,
    'after_answers_due', coalesce(now() > v_answers_due, false),
    'rfb_path', p_rfb_path, 'bid_form_path', p_bid_form_path, 'addendum_path', p_addendum_path,
    'funding_cents', v_funding));
  return v_version;
end;
$$;

revoke all on function public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)
  to authenticated;

-- ---------------------------------------------------------------------------
-- start_bid: the 0010 body; the draft is priced against the solicitation's current version (read under the
-- solicitation's FOR SHARE lock, so publish_addendum cannot move it in between).
-- ---------------------------------------------------------------------------
create or replace function public.start_bid(p_solicitation_id uuid)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_bid public.bids;
begin
  perform app.require_bidder();
  v_org := app.my_org();

  -- Lock: the solicitation row (shared; published rows are frozen) so its due time cannot move under us.
  -- An unknown id and an unpublished one both read as not_open, so the error does not reveal which ids exist.
  perform 1 from public.solicitations s where s.id = p_solicitation_id for share;
  if not found then
    raise exception 'not_open' using errcode = 'P0001';
  end if;
  perform app.require_bidding_open(p_solicitation_id);

  insert into public.bids (solicitation_id, bidder_org_id, reference, created_by)
  values (p_solicitation_id, v_org, app.new_bid_reference(), auth.uid())
  on conflict (solicitation_id, bidder_org_id) do nothing;
  select b.* into v_bid from public.bids b
   where b.solicitation_id = p_solicitation_id and b.bidder_org_id = v_org;
  v_bid := app.lock_bid(v_bid.id);
  perform app.require_before_due_clock(v_bid.solicitation_id);

  if exists (select 1 from public.bid_drafts d where d.bid_id = v_bid.id) then
    return v_bid.id;
  end if;
  if app.latest_version(v_bid.id) is not null then
    raise exception 'invalid_state' using errcode = 'P0001';  -- already submitted: use replace_bid
  end if;
  insert into public.bid_drafts (bid_id, version, solicitation_version)
  select v_bid.id, 1, s.version from public.solicitations s where s.id = v_bid.solicitation_id;
  return v_bid.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- replace_bid: the 0010 body. A new draft always starts with empty price arrays; it is priced against the
-- solicitation's current version, so when the latest submitted version is stale the bidder re-prices against the
-- changed schedule. FOR SHARE on the solicitation before the bid lock (see the header).
-- ---------------------------------------------------------------------------
create or replace function public.replace_bid(p_bid_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid     public.bids;
  v_latest  int;
  v_current int;
begin
  perform app.require_bidder();
  -- Solicitation first (FOR SHARE, as start_bid), then the bid: app.lock_bid is the last lock, so the wall-clock
  -- check right after it follows every lock (Ruling 8). Another org's or an unknown bid locks nothing here and
  -- lock_bid raises not_found.
  select s.version into v_current from public.solicitations s
   where s.id = (select b.solicitation_id from public.bids b where b.id = p_bid_id and b.bidder_org_id = app.my_org())
     for share;
  v_bid := app.lock_bid(p_bid_id);
  perform app.require_before_due_clock(v_bid.solicitation_id);
  perform app.require_bidding_open(v_bid.solicitation_id);

  v_latest := app.latest_version(v_bid.id);
  if v_latest is null or exists (select 1 from public.bid_drafts d where d.bid_id = v_bid.id) then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, solicitation_version)
  values (v_bid.id, v_latest + 1, '{}', '{}', v_current);
  perform app.bid_audit(v_bid, 'replace_bid',
                        jsonb_build_object('from_version', v_latest, 'draft_version', v_latest + 1));
end;
$$;

-- ---------------------------------------------------------------------------
-- submit_bid: the 0015 body (its latest), plus FOR SHARE on the solicitation before the bid lock, the stale_draft
-- guard after the draft lock, and solicitation_version copied into the sealed version row.
-- ---------------------------------------------------------------------------
create or replace function public.submit_bid(p_bid_id uuid)
returns table (reference text, version int, submitted_at timestamptz)
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid      public.bids;
  v_draft    public.bid_drafts;
  v_latest   int;
  v_problems text[];
  v_version  public.bid_versions;
  v_n_files  int;
  v_copied   int;
begin
  perform app.require_bidder();
  -- Solicitation first (FOR SHARE, as start_bid): serializes with publish_addendum (FOR UPDATE on the solicitation)
  -- before the draft is read (see the header). app.lock_bid is then the last lock, so the wall-clock check right
  -- after it follows every lock (Ruling 8). Another org's or an unknown bid locks nothing here; lock_bid raises
  -- not_found.
  perform 1 from public.solicitations s
   where s.id = (select b.solicitation_id from public.bids b where b.id = p_bid_id and b.bidder_org_id = app.my_org())
     for share;
  v_bid := app.lock_bid(p_bid_id);
  perform app.require_before_due_clock(v_bid.solicitation_id);
  perform app.require_bidding_open(v_bid.solicitation_id);

  v_latest := app.latest_version(v_bid.id);
  select * into v_draft from public.bid_drafts d where d.bid_id = v_bid.id for update;
  if not found or v_draft.version <> coalesce(v_latest, 0) + 1 then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  -- Prices entered against a schedule that has since changed are never sealed.
  if v_draft.solicitation_version < app.last_schedule_change(v_bid.solicitation_id) then
    raise exception 'stale_draft' using errcode = 'P0001';
  end if;

  -- Lock the draft file rows so they cannot change between validation and the copy below.
  perform 1 from public.bid_draft_files f where f.bid_id = v_bid.id for update;
  select count(*) into v_n_files from public.bid_draft_files f where f.bid_id = v_bid.id;

  v_problems := app.bid_draft_problems(v_bid.id);
  if cardinality(v_problems) > 0 then
    raise exception 'invalid_bid' using errcode = 'P0001', detail = array_to_string(v_problems, ',');
  end if;

  -- The legal name is copied as it stands now (the as-submitted name the tabulation shows).
  insert into public.bid_versions (bid_id, version, submitted_by, item_cents, alternate_cents, bid_bond_choice,
                                   apprentice_commitment, bidder_legal_name, solicitation_version)
  select v_bid.id, v_draft.version, auth.uid(), v_draft.item_cents, v_draft.alternate_cents, v_draft.bid_bond_choice,
         v_draft.apprentice_commitment, o.name, v_draft.solicitation_version
    from public.organizations o
   where o.id = v_bid.bidder_org_id
  returning * into v_version;

  -- Validated above, but a storage object can still be deleted by a concurrent transaction that commits before
  -- this statement's snapshot: the join would then drop that file silently. Compare counts and refuse instead.
  insert into public.bid_version_files (version_id, slot, path, file_name, object_id, object_size, object_etag)
  select v_version.id, f.slot, f.path, f.file_name, o.id, (o.metadata->>'size')::bigint, o.metadata->>'eTag'
    from public.bid_draft_files f
    join storage.objects o on o.bucket_id = 'bid-files' and o.name = f.path
   where f.bid_id = v_bid.id
     and o.metadata->>'size' ~ '^[0-9]{1,18}$' and o.metadata->>'eTag' is not null;
  get diagnostics v_copied = row_count;
  if v_copied <> v_n_files then
    raise exception 'invalid_bid' using errcode = 'P0001', detail = 'file_missing';
  end if;

  delete from public.bid_drafts d where d.bid_id = v_bid.id;  -- cascades to bid_draft_files

  perform app.bid_audit(v_bid, 'submit_bid',
                        jsonb_build_object('reference', v_bid.reference, 'version', v_version.version,
                                           'supersedes', v_latest));

  return query select v_bid.reference, v_version.version, v_version.submitted_at;
end;
$$;

revoke all on function public.start_bid(uuid), public.replace_bid(uuid), public.submit_bid(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.start_bid(uuid), public.replace_bid(uuid), public.submit_bid(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- opened_bids: the 0012 body with app.bid_excluded, plus a resubmit_required determination for each stale bid
-- (latest version not withdrawn, but stale), written once per change like the 0012 determinations.
-- ---------------------------------------------------------------------------
create or replace function public.opened_bids(p_solicitation_id uuid)
returns table (
  bid_id uuid, reference text, version int, submitted_at timestamptz, bidder_org_id uuid, bidder_name text,
  item_cents bigint[], alternate_cents bigint[], base_total_cents bigint, bid_bond_choice public.bid_bond_choice,
  original_received boolean, non_responsive_reason text, bond_original_received boolean)
language plpgsql volatile security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reason constant text := 'signed original not received by the bid due time';
  v_due    timestamptz;
  v_detail jsonb;
  r        record;
  st       record;
begin
  v_due := app.open_bids_gate(p_solicitation_id);
  perform pg_advisory_xact_lock(hashtext(p_solicitation_id::text));

  for st in
    select b.id as stale_bid_id, v.version as stale_version
      from public.bids b
      join public.bid_versions v on v.bid_id = b.id and v.version = app.latest_version(b.id)
     where b.solicitation_id = p_solicitation_id
       and not app.is_withdrawn(b.id, v.version)
       and app.bid_stale(b.id, v.version)
     order by b.reference
  loop
    v_detail := jsonb_build_object('version', st.stale_version, 'reason', 'resubmit_required');
    if (select a.detail from public.bid_audit_log a
         where a.bid_id = st.stale_bid_id and a.action = 'bid_close_determination'
         order by a.id desc limit 1) is distinct from v_detail then
      insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
      values (p_solicitation_id, st.stale_bid_id, auth.uid(), 'bid_close_determination', v_detail);
    end if;
  end loop;

  for r in
    select b.id as bid_id, b.reference, v.version, v.submitted_at, b.bidder_org_id, v.bidder_legal_name as bidder_name,
           v.item_cents, v.alternate_cents,
           coalesce((select sum(x) from unnest(v.item_cents) x), 0)::bigint as base_total_cents,
           v.bid_bond_choice,
           app.original_received(b.id, v.version, v_due) as received,
           case when v.bid_bond_choice = 'paper' then app.bond_original_received(b.id, v.version, v_due) end as bond
      from public.bids b
      join public.bid_versions v on v.bid_id = b.id and v.version = app.latest_version(b.id)
     where b.solicitation_id = p_solicitation_id
       and not app.bid_excluded(b.id, v.version)
     order by 9, b.reference
  loop
    v_detail := jsonb_build_object('version', r.version, 'original_received', r.received,
                                   'reason', case when r.received then null else v_reason end);
    if (select a.detail from public.bid_audit_log a
         where a.bid_id = r.bid_id and a.action = 'bid_close_determination'
         order by a.id desc limit 1) is distinct from v_detail then
      insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
      values (p_solicitation_id, r.bid_id, auth.uid(), 'bid_close_determination', v_detail);
    end if;

    bid_id := r.bid_id;
    reference := r.reference;
    version := r.version;
    submitted_at := r.submitted_at;
    bidder_org_id := r.bidder_org_id;
    bidder_name := r.bidder_name;
    item_cents := r.item_cents;
    alternate_cents := r.alternate_cents;
    base_total_cents := r.base_total_cents;
    bid_bond_choice := r.bid_bond_choice;
    original_received := r.received;
    non_responsive_reason := case when r.received then null else v_reason end;
    bond_original_received := r.bond;
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- opened_bid_files: the 0012 body with app.bid_excluded.
-- ---------------------------------------------------------------------------
create or replace function public.opened_bid_files(p_solicitation_id uuid)
returns table (bid_id uuid, slot public.bid_upload_slot, path text, file_name text, file_status text)
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  perform app.open_bids_gate(p_solicitation_id);

  return query
    select b.id, f.slot, f.path, f.file_name,
           case when o.id is null then 'missing'
                when o.id is distinct from f.object_id
                  or (o.metadata->>'size') is distinct from f.object_size::text
                  or (o.metadata->>'eTag') is distinct from f.object_etag then 'changed'
                else 'ok' end
      from public.bids b
      join public.bid_versions v on v.bid_id = b.id and v.version = app.latest_version(b.id)
      join public.bid_version_files f on f.version_id = v.id
      left join storage.objects o on o.bucket_id = 'bid-files' and o.name = f.path
     where b.solicitation_id = p_solicitation_id
       and not app.bid_excluded(b.id, v.version)
     order by b.reference, f.slot;
end;
$$;

revoke all on function public.opened_bids(uuid), public.opened_bid_files(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.opened_bids(uuid), public.opened_bid_files(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- stale_bids: office only, at or after close (sealed before; the app.open_bids_gate error order). One row per bid
-- whose latest version is not withdrawn but stale, ordered by reference. No prices.
-- ---------------------------------------------------------------------------
create function public.stale_bids(p_solicitation_id uuid)
returns table (bid_id uuid, reference text, bidder_legal_name text, version int, solicitation_version int)
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  perform app.open_bids_gate(p_solicitation_id);

  return query
    select b.id, b.reference, v.bidder_legal_name, v.version, v.solicitation_version
      from public.bids b
      join public.bid_versions v on v.bid_id = b.id and v.version = app.latest_version(b.id)
     where b.solicitation_id = p_solicitation_id
       and not app.is_withdrawn(b.id, v.version)
       and app.bid_stale(b.id, v.version)
     order by b.reference;
end;
$$;

revoke all on function public.stale_bids(uuid) from public, anon, authenticated, service_role;
grant execute on function public.stale_bids(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- my_bid_status_addenda: the owning bidder only (otherwise not_found; non-bidders not_authorized). Readable before
-- and after close. No prices.
--   resubmit_required: the latest submitted version is not withdrawn and is stale.
--   schedule_changed_in: the addendum number (version - 1) of the latest schedule change after the latest submitted
--     version's solicitation_version, else null (also null with no submitted version).
--   draft_cleared_by: addendum number v - 1 when v = app.last_schedule_change > 1, the draft is at v with both price
--     arrays empty, and the bid was created before version v was published; else null.
-- ---------------------------------------------------------------------------
create function public.my_bid_status_addenda(p_bid_id uuid)
returns table (resubmit_required boolean, schedule_changed_in int, draft_cleared_by int)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_bid    public.bids;
  v_latest int;
  v_sv     int;
  v_last   int;
  v_draft  public.bid_drafts;
  v_pub_at timestamptz;
begin
  perform app.require_bidder();
  select b.* into v_bid from public.bids b where b.id = p_bid_id and b.bidder_org_id = app.my_org();
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  v_last := app.last_schedule_change(v_bid.solicitation_id);
  v_latest := app.latest_version(v_bid.id);
  select v.solicitation_version into v_sv from public.bid_versions v
   where v.bid_id = v_bid.id and v.version = v_latest;
  select d.* into v_draft from public.bid_drafts d where d.bid_id = v_bid.id;
  select sv.published_at into v_pub_at from public.solicitation_versions sv
   where sv.solicitation_id = v_bid.solicitation_id and sv.version = v_last;

  return query select
    coalesce(v_latest is not null and not app.is_withdrawn(v_bid.id, v_latest) and v_sv < v_last, false),
    case when v_sv < v_last then v_last - 1 end,
    case when v_last > 1
          and v_draft.solicitation_version = v_last
          and cardinality(v_draft.item_cents) = 0
          and cardinality(v_draft.alternate_cents) = 0
          and v_bid.created_at < v_pub_at
         then v_last - 1 end;
end;
$$;

revoke all on function public.my_bid_status_addenda(uuid) from public, anon, authenticated, service_role;
grant execute on function public.my_bid_status_addenda(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- app.bond_cure: the 0016 body (its latest) with app.bid_excluded: a stale bid has no bond to cure.
-- ---------------------------------------------------------------------------
create or replace function app.bond_cure(p_bid_id uuid, p_now timestamptz default now())
returns table (status text, due_at timestamptz)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_sol     public.solicitations;
  v_version public.bid_versions;
  v_missing boolean;
  v_due     timestamptz;
begin
  select s.* into v_sol
    from public.bids b join public.solicitations s on s.id = b.solicitation_id
   where b.id = p_bid_id;
  if not found or not app.bonds_required(v_sol.published_snapshot) then
    return query select 'not_required'::text, null::timestamptz;
    return;
  end if;
  select v.* into v_version from public.bid_versions v
   where v.bid_id = p_bid_id and v.version = app.latest_version(p_bid_id);
  if not found or app.bid_excluded(p_bid_id, v_version.version) then
    return query select 'not_required'::text, null::timestamptz;
    return;
  end if;

  v_missing := case v_version.bid_bond_choice
    when 'electronic' then not exists (select 1 from public.bid_version_files f
                                        where f.version_id = v_version.id and f.slot = 'bid_bond')
    when 'paper' then not app.bond_original_received(p_bid_id, v_version.version, v_sol.bid_due_at)
    else false end;  -- no choice cannot be sealed (submit_bid requires one): the plan's rule names only the two
  if not v_missing then
    return query select 'ok'::text, null::timestamptz;
    return;
  end if;

  v_due := app.cure_deadline(v_sol.id);
  if exists (select 1 from public.bid_cure_files c
              where c.bid_id = p_bid_id and c.version = v_version.version
                and c.uploaded_at < v_due)
     or app.bond_original_received(p_bid_id, v_version.version, v_due) then
    return query select 'cured'::text, v_due;
  elsif p_now >= v_due then
    return query select 'failed'::text, v_due;
  else
    return query select 'pending'::text, v_due;
  end if;
end;
$$;

revoke all on function app.bond_cure(uuid, timestamptz) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- app.can_read_bid_file: the 0016 body (its latest) with app.bid_excluded: office staff never read a stale
-- version's files.
-- ---------------------------------------------------------------------------
create or replace function app.can_read_bid_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bids b
    where b.id = app.path_bid_id(p_name)
      and (
        (b.bidder_org_id = app.my_org()
         and exists (select 1 from public.bid_draft_files df where df.bid_id = b.id and df.path = p_name)
         and not exists (select 1 from public.bid_version_files vf where vf.path = p_name))
        or
        (app.is_office()
         and app.bids_closed(b.solicitation_id)
         and exists (
           select 1 from public.bid_versions v
           join public.bid_version_files vf on vf.version_id = v.id
           where v.bid_id = b.id
             and vf.path = p_name
             and v.version = app.latest_version(b.id)
             and not app.bid_excluded(b.id, v.version)))
        or
        ((b.bidder_org_id = app.my_org() or (app.is_office() and app.bids_closed(b.solicitation_id)))
         and exists (select 1 from public.bid_cure_files cf where cf.bid_id = b.id and cf.path = p_name))
      )
  );
$$;

revoke all on function app.can_read_bid_file(text) from public, anon, authenticated, service_role;
grant execute on function app.can_read_bid_file(text) to authenticated;

-- ---------------------------------------------------------------------------
-- app.bid_review_status: the 0018 body with app.bid_excluded: no row for a stale bid.
-- ---------------------------------------------------------------------------
create or replace function app.bid_review_status(p_bid_id uuid, p_now timestamptz default now())
returns table (status text, reason text)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_due      timestamptz;
  v_version  int;
  v_cure     text;
  v_out      public.bid_outcomes;
  v_decision public.flagged_decisions;
begin
  select s.bid_due_at into v_due
    from public.bids b join public.solicitations s on s.id = b.solicitation_id
   where b.id = p_bid_id;
  v_version := app.latest_version(p_bid_id);
  if v_due is null or v_version is null or app.bid_excluded(p_bid_id, v_version) then
    return;
  end if;

  if not app.original_received(p_bid_id, v_version, v_due) then
    return query select 'non_responsive'::text, 'signed original not received by the bid due time'::text;
    return;
  end if;
  select c.status into v_cure from app.bond_cure(p_bid_id, p_now) c;
  if v_cure = 'failed' then
    return query select 'non_responsive'::text, 'bid bond not received by the cure deadline'::text;
    return;
  elsif v_cure = 'pending' then
    return query select 'pending_cure'::text, null::text;
    return;
  end if;

  v_out := app.current_outcome(p_bid_id);
  if v_out.id is null then
    return query select 'undecided'::text, null::text;
  elsif v_out.outcome = 'non_responsive' then
    return query select 'non_responsive'::text, replace(v_out.ground::text, '_', ' ');
  elsif v_out.outcome = 'accepted' then
    return query select 'accepted'::text, null::text;
  else
    select d.* into v_decision from public.flagged_decisions d
     where d.outcome_id = v_out.id
     order by d.decided_at desc, d.id desc
     limit 1;
    if v_decision.id is null then
      return query select 'flagged'::text, v_out.note;
    elsif v_decision.decision = 'accept' then
      return query select 'flag_accepted'::text, v_decision.reason;
    else
      return query select 'flag_rejected'::text, v_decision.reason;
    end if;
  end if;
end;
$$;

revoke all on function app.bid_review_status(uuid, timestamptz) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- set_bid_outcome: the 0018 body (its latest) with app.bid_excluded: a stale bid has no opened version (not_found).
-- ---------------------------------------------------------------------------
create or replace function public.set_bid_outcome(
  p_bid_id uuid, p_outcome public.bid_outcome, p_ground public.non_responsive_ground, p_note text)
returns uuid
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_bid     public.bids;
  v_eval    public.evaluations;
  v_version int;
  v_status  text;
  v_reason  text;
  v_prev    uuid;
  v_id      uuid;
begin
  perform app.require_office();
  select b.* into v_bid from public.bids b where b.id = p_bid_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  v_eval := app.lock_evaluation(v_bid.solicitation_id);
  v_version := app.latest_version(v_bid.id);
  if v_version is null or app.bid_excluded(v_bid.id, v_version) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  perform app.require_stage(v_eval, 'bid_review');

  select r.status, r.reason into v_status, v_reason from app.bid_review_status(v_bid.id, clock_timestamp()) r;
  if v_status = 'non_responsive' and v_reason in ('signed original not received by the bid due time',
                                                  'bid bond not received by the cure deadline') then
    raise exception 'outcome_locked' using errcode = 'P0001';
  end if;
  if btrim(coalesce(p_note, '')) = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;
  if p_outcome is null or (p_outcome = 'non_responsive') <> (p_ground is not null) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  v_prev := (app.current_outcome(v_bid.id)).id;
  insert into public.bid_outcomes (solicitation_id, bid_id, version, outcome, ground, note, set_by, set_at)
  values (v_bid.solicitation_id, v_bid.id, v_version, p_outcome, p_ground, btrim(p_note), auth.uid(), clock_timestamp())
  returning id into v_id;
  perform app.bid_audit(v_bid, 'set_bid_outcome', jsonb_build_object(
    'outcome_id', v_id, 'version', v_version, 'outcome', p_outcome, 'ground', p_ground, 'note', btrim(p_note),
    'previous_outcome_id', v_prev));
  return v_id;
end;
$$;

revoke all on function public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- verify_resident: the 0019 body (its latest) with app.bid_excluded: a stale bid has no opened version (not_found).
-- ---------------------------------------------------------------------------
create or replace function public.verify_resident(p_bid_id uuid, p_verified boolean, p_note text)
returns uuid
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_bid     public.bids;
  v_eval    public.evaluations;
  v_version int;
  v_cert    text;
  v_claimed boolean;
  v_id      uuid;
begin
  perform app.require_office();
  select b.* into v_bid from public.bids b where b.id = p_bid_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  v_eval := app.lock_evaluation(v_bid.solicitation_id);
  v_version := app.latest_version(v_bid.id);
  if v_version is null or app.bid_excluded(v_bid.id, v_version) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  perform app.require_stage(v_eval, 'bid_review');

  select c.resident_claimed, c.resident_certificate into v_claimed, v_cert
    from public.bidder_companies c where c.org_id = v_bid.bidder_org_id;
  if not coalesce(v_claimed, false) then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if p_verified is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if btrim(coalesce(p_note, '')) = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;

  insert into public.resident_verifications (solicitation_id, bid_id, certificate, verified, note, verified_by, verified_at)
  values (v_bid.solicitation_id, v_bid.id, btrim(v_cert), p_verified, btrim(p_note), auth.uid(), clock_timestamp())
  returning id into v_id;
  perform app.bid_audit(v_bid, 'verify_resident', jsonb_build_object(
    'verified', p_verified, 'certificate', btrim(v_cert), 'note', btrim(p_note)));
  return v_id;
end;
$$;

revoke all on function public.verify_resident(uuid, boolean, text) from public, anon, authenticated, service_role;
grant execute on function public.verify_resident(uuid, boolean, text) to authenticated;
