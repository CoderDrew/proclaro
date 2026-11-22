-- 0031_acknowledgments: addendum acknowledgments and the missing-acknowledgment flag at review (slice 2c, Task 6).
--
-- * Acknowledging is a separate online action (spec §5): it never creates a bid version and never needs a new mailed
--   original. It works whether the bid is a draft or already submitted, and it can't be undone.
-- * bid_acknowledgments is append-only (app.reject_change on update/delete/truncate) and has no API grants: the
--   bidder reads its own through public.my_bid_acknowledgments, the office reads only the missing numbers through
--   public.review_bids (after close, app.open_bids_gate). The agency and the public never read them.
-- * acknowledge_addendum locks like the other bidder writers (0030): the solicitation FOR SHARE (serializes with
--   publish_addendum's FOR UPDATE, so a publish committing first is seen), then app.lock_bid, then directly the
--   wall-clock check (Ruling 8). An acknowledgment recorded before close therefore always counts, and none can be
--   recorded at or after close.
-- * At review (constraints "Missing acknowledgment at review"), set_bid_outcome refuses 'accepted' for a bid missing
--   any published addendum (ack_missing) and prefixes 'accepted_flagged' notes with the fixed note
--   'Did not acknowledge Addendum N[, M].' unless the note already starts with it. 'non_responsive' is unchanged.
--   The brief's "flagged" is the existing outcome 'accepted_flagged'. No outcome row is written automatically.
-- * review_bids gains missing_addenda int[] (its return type changes, so it is dropped and recreated).
--
-- Errors (P0001): ack_missing (new); not_authorized, not_found, bids_closed, not_open as before.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------
create table public.bid_acknowledgments (
  bid_id          uuid not null references public.bids (id),
  addendum_number int not null check (addendum_number >= 1),
  acknowledged_at timestamptz not null default now(),
  acknowledged_by uuid not null references public.profiles (user_id),
  primary key (bid_id, addendum_number)
);

create trigger bid_acknowledgments_append_only
  before update or delete on public.bid_acknowledgments
  for each row execute function app.reject_change();
create trigger bid_acknowledgments_no_truncate
  before truncate on public.bid_acknowledgments
  for each statement execute function app.reject_change();

revoke all on public.bid_acknowledgments from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Helpers (schema `app`, no API role executes them)
-- ---------------------------------------------------------------------------

-- Published addendum numbers of the bid's solicitation (ascending) that the bid has not acknowledged. Empty, never
-- null, when none are missing.
create function app.missing_acknowledgments(p_bid_id uuid)
returns int[]
language sql stable security definer
set search_path = ''
as $$
  select coalesce(array_agg(a.number order by a.number), '{}'::int[])
    from public.bids b
    join public.addenda a on a.solicitation_id = b.solicitation_id and a.state = 'published'
   where b.id = p_bid_id
     and not exists (select 1 from public.bid_acknowledgments k
                      where k.bid_id = b.id and k.addendum_number = a.number);
$$;

-- The fixed review note. Kept in sync with ackNote in src/domain/addendum/ack.ts by ack.test.ts.
create function app.ack_note(p_missing int[])
returns text
language sql immutable security definer
set search_path = ''
as $$
  select 'Did not acknowledge Addendum ' || array_to_string(p_missing, ', ') || '.';
$$;

revoke all on function app.missing_acknowledgments(uuid), app.ack_note(int[])
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- acknowledge_addendum: the owning bidder acknowledges a published addendum. Error order: not_authorized (not a
-- bidder) -> not_found (unknown or another org's bid, app.lock_bid) -> bids_closed (clock_timestamp() after the
-- lock, Ruling 8) -> bids_closed / not_open (app.require_bidding_open) -> not_found (addendum not published).
-- Idempotent: a repeat call writes no row and no audit.
-- ---------------------------------------------------------------------------
create function public.acknowledge_addendum(p_bid_id uuid, p_addendum_number int)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid public.bids;
  v_n   int;
begin
  perform app.require_bidder();
  -- Solicitation first (FOR SHARE, as submit_bid in 0030), then the bid row; the clock check follows lock_bid
  -- directly. Another org's or an unknown bid locks nothing here; lock_bid raises not_found.
  perform 1 from public.solicitations s
   where s.id = (select b.solicitation_id from public.bids b where b.id = p_bid_id and b.bidder_org_id = app.my_org())
     for share;
  v_bid := app.lock_bid(p_bid_id);
  perform app.require_before_due_clock(v_bid.solicitation_id);
  perform app.require_bidding_open(v_bid.solicitation_id);

  if not exists (select 1 from public.addenda a
                  where a.solicitation_id = v_bid.solicitation_id and a.number = p_addendum_number
                    and a.state = 'published') then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  insert into public.bid_acknowledgments (bid_id, addendum_number, acknowledged_at, acknowledged_by)
  values (v_bid.id, p_addendum_number, clock_timestamp(), auth.uid())
  on conflict (bid_id, addendum_number) do nothing;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    perform app.bid_audit(v_bid, 'acknowledge_addendum', jsonb_build_object('addendum_number', p_addendum_number));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- my_bid_acknowledgments: the owning bidder's view. Every published addendum of the bid's solicitation, ascending,
-- with its version's published_at (version = number + 1) and acknowledged_at (null when not acknowledged).
-- not_authorized for anyone who is not a bidder (office staff included: they read missing_addenda through
-- review_bids after close); not_found for another org's bid.
-- ---------------------------------------------------------------------------
create function public.my_bid_acknowledgments(p_bid_id uuid)
returns table (addendum_number int, published_at timestamptz, acknowledged_at timestamptz)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_bid public.bids;
begin
  perform app.require_bidder();
  select b.* into v_bid from public.bids b where b.id = p_bid_id and b.bidder_org_id = app.my_org();
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  return query
    select a.number, sv.published_at, k.acknowledged_at
      from public.addenda a
      left join public.solicitation_versions sv
        on sv.solicitation_id = a.solicitation_id and sv.version = a.number + 1
      left join public.bid_acknowledgments k on k.bid_id = v_bid.id and k.addendum_number = a.number
     where a.solicitation_id = v_bid.solicitation_id and a.state = 'published'
     order by a.number;
end;
$$;

revoke all on function public.acknowledge_addendum(uuid, int), public.my_bid_acknowledgments(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.acknowledge_addendum(uuid, int), public.my_bid_acknowledgments(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- set_bid_outcome: the 0030 body (its latest) plus the missing-acknowledgment rule, checked last (after
-- reason_required and invalid_data): 'accepted' -> ack_missing; 'accepted_flagged' -> the fixed note, a space, then
-- the reviewer's note, unless the note already starts with the fixed note; 'non_responsive' unchanged.
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
  v_missing int[];
  v_fixed   text;
  v_note    text;
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

  v_note := btrim(p_note);
  v_missing := app.missing_acknowledgments(v_bid.id);
  if cardinality(v_missing) > 0 then
    if p_outcome = 'accepted' then
      raise exception 'ack_missing' using errcode = 'P0001';
    elsif p_outcome = 'accepted_flagged' then
      v_fixed := app.ack_note(v_missing);
      if left(v_note, length(v_fixed)) <> v_fixed then
        v_note := v_fixed || ' ' || v_note;
      end if;
    end if;
  end if;

  v_prev := (app.current_outcome(v_bid.id)).id;
  insert into public.bid_outcomes (solicitation_id, bid_id, version, outcome, ground, note, set_by, set_at)
  values (v_bid.solicitation_id, v_bid.id, v_version, p_outcome, p_ground, v_note, auth.uid(), clock_timestamp())
  returning id into v_id;
  perform app.bid_audit(v_bid, 'set_bid_outcome', jsonb_build_object(
    'outcome_id', v_id, 'version', v_version, 'outcome', p_outcome, 'ground', p_ground, 'note', v_note,
    'previous_outcome_id', v_prev));
  return v_id;
end;
$$;

revoke all on function public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- review_bids: the 0018 body (its latest) plus missing_addenda (app.missing_acknowledgments of each opened bid).
-- Same gate (app.open_bids_gate: office only, sealed before close) and lock order.
-- ---------------------------------------------------------------------------
drop function public.review_bids(uuid);

create function public.review_bids(p_solicitation_id uuid)
returns table (
  bid_id uuid, reference text, version int, bidder_name text, bidder_org_id uuid, base_total_cents bigint,
  alternate_cents bigint[], apprentice_commitment boolean, cure_status text, cure_due_at timestamptz,
  outcome_id uuid, outcome public.bid_outcome, ground public.non_responsive_ground, note text,
  status text, status_reason text, missing_addenda int[])
language plpgsql volatile security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  r       record;
  v_bid   public.bids;
  v_cure  text;
  v_due   timestamptz;
  v_out   public.bid_outcomes;
  v_stat  text;
  v_why   text;
begin
  perform app.open_bids_gate(p_solicitation_id);
  perform app.lock_evaluation(p_solicitation_id);

  for r in select o.* from public.opened_bids(p_solicitation_id) o loop
    select b.* into v_bid from public.bids b where b.id = r.bid_id;
    select c.status, c.due_at into v_cure, v_due from app.bond_cure(r.bid_id, now()) c;
    perform app.audit_cure_determination(v_bid, v_cure, v_due);
    v_out := app.current_outcome(r.bid_id);
    select s.status, s.reason into v_stat, v_why from app.bid_review_status(r.bid_id, now()) s;

    bid_id := r.bid_id;
    reference := r.reference;
    version := r.version;
    bidder_name := r.bidder_name;
    bidder_org_id := r.bidder_org_id;
    base_total_cents := r.base_total_cents;
    alternate_cents := r.alternate_cents;
    apprentice_commitment := (select v.apprentice_commitment from public.bid_versions v
                               where v.bid_id = r.bid_id and v.version = r.version);
    cure_status := v_cure;
    cure_due_at := v_due;
    outcome_id := v_out.id;
    outcome := v_out.outcome;
    ground := v_out.ground;
    note := v_out.note;
    status := v_stat;
    status_reason := v_why;
    missing_addenda := app.missing_acknowledgments(r.bid_id);
    return next;
  end loop;
end;
$$;

revoke all on function public.review_bids(uuid) from public, anon, authenticated, service_role;
grant execute on function public.review_bids(uuid) to authenticated;
