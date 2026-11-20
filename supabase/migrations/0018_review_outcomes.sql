-- 0018_review_outcomes: bid review outcomes, evaluation state and derived review statuses (slice 2b, Task 4).
--
-- evaluations: one mutable row per closed solicitation, created by app.lock_evaluation (the only creator) and
-- locked FOR UPDATE by every evaluation writer, so outcome writes and stage moves on one solicitation serialize.
-- Creating it also freezes the cure deadline (Ruling 3, app.freeze_cure_due from 0016). Readable by the office and
-- the owning agency; no API role can write it.
--
-- bid_outcomes: append-only. The latest row per bid (set_at, id) is current, so every change is its own audited
-- row. set_at is stamped with clock_timestamp() by set_bid_outcome, so two changes in one transaction still order.
-- flagged_decisions: append-only; one agency decision belongs to one outcome row (written in Task 7). If the office
-- changes the outcome, the old decision no longer applies (it points at an older outcome row).
--
-- Review status (app.bid_review_status), in precedence order:
--   1. non_responsive, automatic: 'signed original not received by the bid due time' (2a rule, 0011/0012), then
--      'bid bond not received by the cure deadline' (app.bond_cure = 'failed', 0016);
--   2. pending_cure (app.bond_cure = 'pending');
--   3. undecided (no outcome row);
--   4. non_responsive, office ground ('late upload' | 'wrong form' | 'missing signature');
--   5. accepted;
--   6. flagged (accepted_flagged with no decision on that outcome row; reason = the reviewer's note);
--   7. flag_accepted / 8. flag_rejected (reason = the agency's decision reason).
-- An automatic non-responsive status cannot be overridden: set_bid_outcome raises outcome_locked for it.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.evaluation_stage as enum
  ('bid_review', 'recap_check', 'recap_posted', 'award_check', 'awarded', 'all_rejected');
create type public.bid_outcome as enum ('accepted', 'accepted_flagged', 'non_responsive');
create type public.non_responsive_ground as enum ('late_upload', 'wrong_form', 'missing_signature');
create type public.flag_decision as enum ('accept', 'reject');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.evaluations (
  solicitation_id   uuid primary key references public.solicitations (id),
  stage             public.evaluation_stage not null default 'bid_review',
  flags_released_at timestamptz,
  recap_preparer_id uuid references public.profiles (user_id),
  recap_draft       jsonb,
  award_preparer_id uuid references public.profiles (user_id),
  updated_at        timestamptz not null default now()
);

create table public.bid_outcomes (
  id              uuid primary key default gen_random_uuid(),
  solicitation_id uuid not null references public.solicitations (id),
  bid_id          uuid not null references public.bids (id),
  version         int not null,
  outcome         public.bid_outcome not null,
  ground          public.non_responsive_ground,
  note            text not null check (btrim(note) <> ''),
  set_by          uuid not null references public.profiles (user_id),
  set_at          timestamptz not null default now(),
  foreign key (bid_id, version) references public.bid_versions (bid_id, version),
  constraint bid_outcomes_ground_matches check ((outcome = 'non_responsive') = (ground is not null))
);
create index bid_outcomes_bid_idx on public.bid_outcomes (bid_id, set_at desc, id desc);
create index bid_outcomes_solicitation_idx on public.bid_outcomes (solicitation_id);

create table public.flagged_decisions (
  id              uuid primary key default gen_random_uuid(),
  solicitation_id uuid not null references public.solicitations (id),
  bid_id          uuid not null references public.bids (id),
  outcome_id      uuid not null references public.bid_outcomes (id),
  decision        public.flag_decision not null,
  reason          text not null check (btrim(reason) <> ''),
  decided_by      uuid not null references public.profiles (user_id),
  decided_at      timestamptz not null default now()
);
create index flagged_decisions_outcome_idx on public.flagged_decisions (outcome_id, decided_at desc, id desc);
create index flagged_decisions_solicitation_idx on public.flagged_decisions (solicitation_id);

-- Trigger: keep evaluations.updated_at current.
create function app.touch_evaluation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger evaluations_touch
  before update on public.evaluations for each row execute function app.touch_evaluation();

create trigger bid_outcomes_append_only
  before update or delete on public.bid_outcomes for each row execute function app.reject_change();
create trigger bid_outcomes_no_truncate
  before truncate on public.bid_outcomes for each statement execute function app.reject_change();
create trigger flagged_decisions_append_only
  before update or delete on public.flagged_decisions for each row execute function app.reject_change();
create trigger flagged_decisions_no_truncate
  before truncate on public.flagged_decisions for each statement execute function app.reject_change();

revoke all on public.evaluations, public.bid_outcomes, public.flagged_decisions from anon, authenticated, service_role;
-- Column-level grant: the stage columns only. recap_draft (Task 9's unposted recap snapshot: bidder names, prices,
-- ranks) and the preparer ids are never readable through the API; office definer functions expose them. This keeps
-- the agency, which reads its own row through evaluations_read, from seeing anything about bids before posting.
grant select (solicitation_id, stage, flags_released_at, updated_at) on public.evaluations to authenticated;

alter table public.evaluations enable row level security;
alter table public.bid_outcomes enable row level security;
alter table public.flagged_decisions enable row level security;

-- The office, or the agency that owns the solicitation. No write policies (and no write grants).
create policy evaluations_read on public.evaluations
  for select to authenticated
  using (
    app.is_office()
    or (app.is_agency()
        and app.my_org() = (select s.agency_id from public.solicitations s where s.id = evaluations.solicitation_id))
  );

-- ---------------------------------------------------------------------------
-- Helpers (schema `app`, no API role executes them)
-- ---------------------------------------------------------------------------

-- Create (once) and lock the solicitation's evaluation row. sealed unless bids are closed (including unknown or
-- unpublished solicitations). Freezes the cure deadline (Ruling 3) when the row is created at close.
create function app.lock_evaluation(p_solicitation_id uuid)
returns public.evaluations
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_row public.evaluations;
begin
  if not app.bids_closed(p_solicitation_id) then
    raise exception 'sealed' using errcode = 'P0001';
  end if;
  perform app.freeze_cure_due(p_solicitation_id);
  insert into public.evaluations (solicitation_id) values (p_solicitation_id)
  on conflict (solicitation_id) do nothing;
  select e.* into v_row from public.evaluations e where e.solicitation_id = p_solicitation_id for update;
  return v_row;
end;
$$;

create function app.require_stage(p_eval public.evaluations, p_stage public.evaluation_stage)
returns void
language plpgsql immutable
set search_path = ''
as $$
begin
  if p_eval.stage is distinct from p_stage then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
end;
$$;

-- The bid's current outcome: the latest row by (set_at, id), or null.
create function app.current_outcome(p_bid_id uuid)
returns public.bid_outcomes
language sql stable security definer
set search_path = ''
as $$
  select o.* from public.bid_outcomes o
   where o.bid_id = p_bid_id
   order by o.set_at desc, o.id desc
   limit 1;
$$;

-- The derived review status of a bid's latest, non-withdrawn version as of p_now (no row when it has none).
-- p_now decides only the cure (pending versus failed); the signed original is judged at the bid due time.
create function app.bid_review_status(p_bid_id uuid, p_now timestamptz default now())
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
  if v_due is null or v_version is null or app.is_withdrawn(p_bid_id, v_version) then
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

revoke all on function app.touch_evaluation(), app.lock_evaluation(uuid),
  app.require_stage(public.evaluations, public.evaluation_stage), app.current_outcome(uuid),
  app.bid_review_status(uuid, timestamptz)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- set_bid_outcome: the office records an outcome for a bid's opened version. Error order:
-- not_authorized -> not_found (bid) -> sealed (before close) -> not_found (no opened version) -> invalid_state
-- (stage) -> outcome_locked (automatic non-responsive, judged on clock_timestamp() after the lock, Ruling 8) ->
-- reason_required (blank note) -> invalid_data (ground/outcome mismatch).
-- ---------------------------------------------------------------------------
create function public.set_bid_outcome(
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
  if v_version is null or app.is_withdrawn(v_bid.id, v_version) then
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

-- ---------------------------------------------------------------------------
-- review_bids: the office's review screen source. One row per opened bid (public.opened_bids: its gates, order and
-- close-determination audit), with the cure, the current outcome and the derived status. Creates/locks the
-- evaluation row (freezing the cure deadline) and audits each past-deadline cure result through
-- app.audit_cure_determination (0016: advisory lock, written on first read and only again when it changes).
-- ---------------------------------------------------------------------------
create function public.review_bids(p_solicitation_id uuid)
returns table (
  bid_id uuid, reference text, version int, bidder_name text, bidder_org_id uuid, base_total_cents bigint,
  alternate_cents bigint[], apprentice_commitment boolean, cure_status text, cure_due_at timestamptz,
  outcome_id uuid, outcome public.bid_outcome, ground public.non_responsive_ground, note text,
  status text, status_reason text)
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
    return next;
  end loop;
end;
$$;

revoke all on function public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text),
  public.review_bids(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text),
  public.review_bids(uuid)
  to authenticated;
