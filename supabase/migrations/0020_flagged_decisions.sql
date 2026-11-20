-- 0020_flagged_decisions: agency decisions on flagged bids (slice 2b, Task 7).
--
-- After its review the office sends the "accepted, flagged" bids to the owning agency (send_flags_to_agency sets
-- evaluations.flags_released_at). The agency then sees, for each bid whose current outcome is accepted_flagged, only
-- the bid reference, the reviewer's note, the base total and its own decision (agency_flagged_bids): no bidder name,
-- items or alternates. It accepts or rejects each one with a reason (decide_flagged_bid). Decisions are append-only
-- rows in flagged_decisions (0018); the latest row for an outcome counts, so a decision can be revised until the recap
-- is sent to check. A decision belongs to one outcome row: if the office changes the outcome, the old decision no
-- longer applies (app.bid_review_status reads only decisions on the current outcome row).
--
-- Integrity (carried from Task 4): flagged_decisions.bid_id and solicitation_id must be those of the referenced
-- outcome row, and bid_outcomes.solicitation_id must be the bid's solicitation. Both are now composite foreign keys.

-- ---------------------------------------------------------------------------
-- Integrity: tie each decision to its outcome row's bid and solicitation, and each outcome to its bid's solicitation.
-- ---------------------------------------------------------------------------
alter table public.bids
  add constraint bids_id_solicitation_key unique (id, solicitation_id);
alter table public.bid_outcomes
  add constraint bid_outcomes_bid_solicitation_fkey
  foreign key (bid_id, solicitation_id) references public.bids (id, solicitation_id);
alter table public.bid_outcomes
  add constraint bid_outcomes_id_bid_solicitation_key unique (id, bid_id, solicitation_id);
alter table public.flagged_decisions
  add constraint flagged_decisions_outcome_match_fkey
  foreign key (outcome_id, bid_id, solicitation_id) references public.bid_outcomes (id, bid_id, solicitation_id);

-- ---------------------------------------------------------------------------
-- app.require_solicitation_agency: not_authorized unless the caller is a member of the agency that owns the
-- solicitation (an unknown solicitation is not_authorized too, so the error is no existence oracle).
-- ---------------------------------------------------------------------------
create function app.require_solicitation_agency(p_solicitation_id uuid)
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not app.is_agency()
     or app.my_org() is distinct from (select s.agency_id from public.solicitations s where s.id = p_solicitation_id)
     or app.my_org() is null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function app.require_solicitation_agency(uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- send_flags_to_agency: the office releases the flagged bids to the agency. Error order: not_authorized -> sealed
-- (before close, from lock_evaluation) -> invalid_state (stage) -> cure_pending -> undecided_bids -> invalid_state (no
-- bid is flagged). Statuses are judged on clock_timestamp() after the evaluation lock (Ruling 8). Idempotent: a second
-- call keeps the first release time. Every successful call is audited with the number of flagged bids.
-- ---------------------------------------------------------------------------
create function public.send_flags_to_agency(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval    public.evaluations;
  v_now     timestamptz;
  v_pending int := 0;
  v_undec   int := 0;
  v_flagged int := 0;
  r         record;
begin
  perform app.require_office();
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'bid_review');

  v_now := clock_timestamp();
  for r in
    select s.status
      from public.bids b
      cross join lateral app.bid_review_status(b.id, v_now) s
     where b.solicitation_id = p_solicitation_id
  loop
    if r.status = 'pending_cure' then
      v_pending := v_pending + 1;
    elsif r.status = 'undecided' then
      v_undec := v_undec + 1;
    elsif r.status = 'flagged' then
      v_flagged := v_flagged + 1;
    end if;
  end loop;

  if v_pending > 0 then
    raise exception 'cure_pending' using errcode = 'P0001';
  end if;
  if v_undec > 0 then
    raise exception 'undecided_bids' using errcode = 'P0001';
  end if;
  if v_flagged = 0 then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  update public.evaluations
     set flags_released_at = coalesce(flags_released_at, now())
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, null, auth.uid(), 'send_flags_to_agency', jsonb_build_object('flagged_count', v_flagged));
end;
$$;

-- ---------------------------------------------------------------------------
-- agency_flagged_bids: the owning agency's view of the flagged bids. not_authorized -> sealed (before close, judged by
-- the database clock so the agency page never decides "closed" itself). Nothing until the office releases the flags.
-- Then one row per bid whose current outcome is accepted_flagged and whose status is still in the flag family (an
-- automatic non-responsive status takes precedence and is not shown), with the latest decision on that outcome row.
-- Only the reference, the reviewer's note and the base total of the outcome's version: no bidder, items or alternates.
-- ---------------------------------------------------------------------------
create function public.agency_flagged_bids(p_solicitation_id uuid)
returns table (
  outcome_id uuid, reference text, note text, base_total_cents bigint,
  decision public.flag_decision, decision_reason text, decided_at timestamptz)
language plpgsql stable security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform app.require_solicitation_agency(p_solicitation_id);
  if not app.bids_closed(p_solicitation_id) then
    raise exception 'sealed' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.evaluations e
                  where e.solicitation_id = p_solicitation_id and e.flags_released_at is not null) then
    return;
  end if;

  return query
    select o.id, b.reference, o.note,
           coalesce((select sum(x) from unnest(v.item_cents) x), 0)::bigint,
           d.decision, d.reason, d.decided_at
      from public.bids b
      cross join lateral app.current_outcome(b.id) o
      join public.bid_versions v on v.bid_id = o.bid_id and v.version = o.version
      cross join lateral app.bid_review_status(b.id, now()) s
      left join lateral (
        select fd.decision, fd.reason, fd.decided_at
          from public.flagged_decisions fd
         where fd.outcome_id = o.id
         order by fd.decided_at desc, fd.id desc
         limit 1) d on true
     where b.solicitation_id = p_solicitation_id
       and o.outcome = 'accepted_flagged'
       and s.status in ('flagged', 'flag_accepted', 'flag_rejected')
     order by b.reference;
end;
$$;

-- ---------------------------------------------------------------------------
-- decide_flagged_bid: the owning agency accepts or rejects a flagged bid. Error order:
--   1. not_authorized (not the owning agency; an unknown outcome id is not_authorized too);
--   2. invalid_state: after lock_evaluation, the stage is not bid_review, or the flags are not released, or the outcome
--      is not the bid's current outcome of kind accepted_flagged still in the flag family (judged on clock_timestamp()
--      after the lock, Ruling 8);
--   3. reason_required (blank reason); invalid_data (null decision).
-- bid_id and solicitation_id are taken from the outcome row, never from input. decided_at uses clock_timestamp() so
-- two decisions in one transaction still order (app.bid_review_status takes the latest by decided_at, id).
-- ---------------------------------------------------------------------------
create function public.decide_flagged_bid(p_outcome_id uuid, p_decision public.flag_decision, p_reason text)
returns uuid
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_out    public.bid_outcomes;
  v_cur    public.bid_outcomes;
  v_bid    public.bids;
  v_eval   public.evaluations;
  v_status text;
  v_id     uuid;
begin
  select o.* into v_out from public.bid_outcomes o where o.id = p_outcome_id;
  perform app.require_solicitation_agency(v_out.solicitation_id);

  v_eval := app.lock_evaluation(v_out.solicitation_id);
  perform app.require_stage(v_eval, 'bid_review');
  if v_eval.flags_released_at is null then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  v_cur := app.current_outcome(v_out.bid_id);
  select s.status into v_status from app.bid_review_status(v_out.bid_id, clock_timestamp()) s;
  if v_cur.id is distinct from v_out.id or v_out.outcome <> 'accepted_flagged'
     or v_status is null or v_status not in ('flagged', 'flag_accepted', 'flag_rejected') then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;
  if p_decision is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  insert into public.flagged_decisions (solicitation_id, bid_id, outcome_id, decision, reason, decided_by, decided_at)
  values (v_out.solicitation_id, v_out.bid_id, v_out.id, p_decision, btrim(p_reason), auth.uid(), clock_timestamp())
  returning id into v_id;
  select b.* into v_bid from public.bids b where b.id = v_out.bid_id;
  perform app.bid_audit(v_bid, 'decide_flagged_bid', jsonb_build_object(
    'outcome_id', v_out.id, 'decision', p_decision, 'reason', btrim(p_reason)));
  return v_id;
end;
$$;

revoke all on function public.send_flags_to_agency(uuid), public.agency_flagged_bids(uuid),
  public.decide_flagged_bid(uuid, public.flag_decision, text)
  from public, anon, authenticated, service_role;
grant execute on function public.send_flags_to_agency(uuid), public.agency_flagged_bids(uuid),
  public.decide_flagged_bid(uuid, public.flag_decision, text)
  to authenticated;
