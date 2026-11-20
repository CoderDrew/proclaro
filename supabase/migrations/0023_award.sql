-- 0023_award: the award. The agency picks a bid from the posted recap, the office posts the award with a second-person
-- check (slice 2b, Task 10).
--
-- The flow on public.evaluations (0018), after the recap is posted (0022):
--   recap_posted --send_award_to_check--> award_check --post_award--> awarded
--                <--disagree_award------
--   recap_posted --post_award_alone (single-reviewer fallback)--> awarded
-- The agency records picks (public.pick_award) only while the stage is recap_posted; the latest pick is current.
--
-- Everything is read from the POSTED public.recaps row (kind 'recap'), never evaluations.recap_draft. The award amount
-- is the picked row's totalCents (base plus the selected alternates, computed in Postgres); nobody types it.
--
-- award_picks: append-only, no API privileges. It holds the pick reason, which is not public; the office and the
-- owning agency read the current pick through public.current_award_pick.
-- awards: append-only, one row per solicitation, public once it exists. The snapshot has no reason key.
--
-- Two-person check (Ruling 12): the checker (post_award / disagree_award) must not be the CURRENT round's sender,
-- evaluations.award_preparer_id (set by send_award_to_check). A sender of an earlier round may check, so two office
-- users can always finish. The fallback is stamped single_reviewer = true and its audit detail carries
-- 'fallback' = 'no second reviewer available'.
--
-- Rounds (Ruling 11): disagree_award stamps evaluations.award_disagreed_at (clock_timestamp(), no API grant). After a
-- disagreement, send_award_to_check and post_award_alone need a pick made after that time (app.award_pick_fresh), else
-- invalid_state, so a rejected pick can be neither re-sent nor posted alone.
--
-- Database clock (Ruling 8): every writer takes app.lock_evaluation first, then judges the stage and the pick.
-- award_preparer_id has no API grant (0018 column grant); public.award_check_info exposes whether the caller may check.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
-- The time of the latest disagree_award. Not in the 0018 column grant, so no API role reads it.
alter table public.evaluations add column award_disagreed_at timestamptz;

create table public.award_picks (
  id              uuid primary key default gen_random_uuid(),
  solicitation_id uuid not null references public.solicitations (id),
  bid_id          uuid not null references public.bids (id),
  reason          text check (reason is null or btrim(reason) <> ''),
  picked_by       uuid not null references public.profiles (user_id),
  picked_at       timestamptz not null default now()
);
create index award_picks_solicitation_idx on public.award_picks (solicitation_id, picked_at desc);

create table public.awards (
  solicitation_id uuid primary key references public.solicitations (id),
  bid_id          uuid not null references public.bids (id),
  pick_id         uuid not null references public.award_picks (id),
  snapshot        jsonb not null,
  prepared_by     uuid not null references public.profiles (user_id),
  checked_by      uuid references public.profiles (user_id),
  single_reviewer boolean not null,
  posted_at       timestamptz not null default now(),
  constraint awards_single_reviewer_check check (single_reviewer = (checked_by is null)),
  constraint awards_snapshot_bid check (snapshot ->> 'bidId' = bid_id::text)
);

create trigger award_picks_append_only
  before update or delete on public.award_picks for each row execute function app.reject_change();
create trigger award_picks_no_truncate
  before truncate on public.award_picks for each statement execute function app.reject_change();
create trigger awards_append_only
  before update or delete on public.awards for each row execute function app.reject_change();
create trigger awards_no_truncate
  before truncate on public.awards for each statement execute function app.reject_change();

revoke all on public.award_picks, public.awards from anon, authenticated, service_role;
grant select on public.awards to anon, authenticated;

alter table public.award_picks enable row level security;
alter table public.awards enable row level security;

-- Rows exist only once posted, and a posted award is public. award_picks has no policy (and no grant).
create policy awards_read on public.awards
  for select to anon, authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- Helpers (schema `app`, no API role executes them)
-- ---------------------------------------------------------------------------

-- The posted recap snapshot of kind 'recap', or null (no recap posted, or the "all bids rejected" memo).
create function app.posted_recap(p_solicitation_id uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select r.snapshot from public.recaps r
   where r.solicitation_id = p_solicitation_id and r.kind = 'recap';
$$;

-- The current (latest) pick for the solicitation, or a row of nulls.
create function app.latest_award_pick(p_solicitation_id uuid)
returns public.award_picks
language sql stable security definer
set search_path = ''
as $$
  select p.* from public.award_picks p
   where p.solicitation_id = p_solicitation_id
   order by p.picked_at desc, p.id desc
   limit 1;
$$;

-- The latest pick exists and, after a disagree_award, was made after it (Ruling 11).
create function app.award_pick_fresh(p_eval public.evaluations)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select p.id is not null and (p_eval.award_disagreed_at is null or p.picked_at > p_eval.award_disagreed_at)
    from app.latest_award_pick(p_eval.solicitation_id) p;
$$;

-- A pick differs from the expected award when the recap has an expected winner and the pick is another bid. With a
-- tie at rank 1 there is no expected winner, so nothing differs (the pick still needs a reason).
create function app.award_differs(p_recap jsonb, p_bid_id uuid)
returns boolean
language sql immutable
set search_path = ''
as $$
  select p_recap ->> 'expectedWinnerBidId' is not null
         and p_recap ->> 'expectedWinnerBidId' is distinct from p_bid_id::text;
$$;

-- The award snapshot for p_bid_id from a posted recap (names.md): the amount is that row's totalCents. No reason key.
-- Null when the bid is not a row of the recap.
create function app.build_award(p_recap jsonb, p_bid_id uuid)
returns jsonb
language sql immutable
set search_path = ''
as $$
  select jsonb_build_object(
           'bidId', r.value ->> 'bidId',
           'reference', r.value ->> 'reference',
           'bidderName', r.value ->> 'bidderName',
           'amountCents', (r.value ->> 'totalCents')::bigint,
           'selectedAlternates', p_recap -> 'selectedAlternates',
           'alternates', p_recap -> 'alternates',
           'expectedWinnerBidId', p_recap -> 'expectedWinnerBidId',
           'differsFromExpected', app.award_differs(p_recap, p_bid_id))
    from jsonb_array_elements(coalesce(p_recap -> 'rows', '[]'::jsonb)) r
   where r.value ->> 'bidId' = p_bid_id::text;
$$;

-- same_person when the caller is the current round's sender (Ruling 12).
create function app.require_award_checker(p_eval public.evaluations)
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if p_eval.award_preparer_id = auth.uid() then
    raise exception 'same_person' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function app.posted_recap(uuid), app.latest_award_pick(uuid), app.award_pick_fresh(public.evaluations),
  app.award_differs(jsonb, uuid), app.build_award(jsonb, uuid), app.require_award_checker(public.evaluations)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- pick_award: the owning agency picks a bid from the posted recap. Error order: not_authorized (not the owning
-- agency) -> sealed (lock_evaluation) -> invalid_state (stage is not recap_posted or no posted recap of kind recap)
-- -> not_in_recap -> reason_required (unless the pick is the non-null expected winner: this covers a pick that
-- differs and any pick when rank 1 is tied). Returns the pick id. Audited on bid_audit_log.
-- ---------------------------------------------------------------------------
create function public.pick_award(p_solicitation_id uuid, p_bid_id uuid, p_reason text)
returns uuid
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval     public.evaluations;
  v_recap    jsonb;
  v_expected text;
  v_reason   text := nullif(btrim(coalesce(p_reason, '')), '');
  v_differs  boolean;
  v_id       uuid;
begin
  perform app.require_solicitation_agency(p_solicitation_id);
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'recap_posted');
  v_recap := app.posted_recap(p_solicitation_id);
  if v_recap is null then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if p_bid_id is null or app.build_award(v_recap, p_bid_id) is null then
    raise exception 'not_in_recap' using errcode = 'P0001';
  end if;
  v_expected := v_recap ->> 'expectedWinnerBidId';
  if v_reason is null and (v_expected is null or v_expected <> p_bid_id::text) then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;
  v_differs := app.award_differs(v_recap, p_bid_id);

  insert into public.award_picks (solicitation_id, bid_id, reason, picked_by, picked_at)
  values (p_solicitation_id, p_bid_id, v_reason, auth.uid(), clock_timestamp())
  returning id into v_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, p_bid_id, auth.uid(), 'pick_award',
          jsonb_build_object('bid_id', p_bid_id, 'reason', v_reason, 'differs_from_expected', v_differs));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- current_award_pick: the office or the owning agency reads the latest pick (not_authorized otherwise). No row
-- before the first pick.
-- ---------------------------------------------------------------------------
create function public.current_award_pick(p_solicitation_id uuid)
returns table (bid_id uuid, reference text, reason text, picked_at timestamptz, differs_from_expected boolean)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not app.is_office() then
    perform app.require_solicitation_agency(p_solicitation_id);
  end if;
  return query
    select p.bid_id, b.reference, p.reason, p.picked_at,
           coalesce(app.award_differs(app.posted_recap(p_solicitation_id), p.bid_id), false)
      from app.latest_award_pick(p_solicitation_id) p
      join public.bids b on b.id = p.bid_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- award_check_info: the office's read of who sent the award to check, whether the caller may check it, and whether
-- the agency must pick again after a disagreement (award_preparer_id and award_disagreed_at have no API grant).
-- not_authorized unless office. can_check: award_check and the caller is not the current round's sender.
-- needs_new_pick: recap_posted after a disagree_award with no pick made since.
-- ---------------------------------------------------------------------------
create function public.award_check_info(p_solicitation_id uuid)
returns table (prepared_by text, can_check boolean, needs_new_pick boolean)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform app.require_office();
  return query
    select p.display_name,
           e.stage = 'award_check'
             and e.award_preparer_id is distinct from auth.uid(),
           e.stage = 'recap_posted' and e.award_disagreed_at is not null and not app.award_pick_fresh(e)
      from public.evaluations e
      left join public.profiles p on p.user_id = e.award_preparer_id
     where e.solicitation_id = p_solicitation_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- send_award_to_check: the office sends the current pick to a second office user. Error order: not_authorized ->
-- sealed -> invalid_state (stage) -> pick_required -> invalid_state (no pick since the latest disagree_award).
-- ---------------------------------------------------------------------------
create function public.send_award_to_check(p_solicitation_id uuid)
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
  perform app.require_stage(v_eval, 'recap_posted');
  v_pick := app.latest_award_pick(p_solicitation_id);
  if v_pick.id is null then
    raise exception 'pick_required' using errcode = 'P0001';
  end if;
  if not app.award_pick_fresh(v_eval) then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  update public.evaluations
     set stage = 'award_check', award_preparer_id = auth.uid()
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, v_pick.bid_id, auth.uid(), 'send_award_to_check',
          jsonb_build_object('pick_id', v_pick.id, 'bid_id', v_pick.bid_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- disagree_award: the checker sends the award back with a comment. Error order: not_authorized -> sealed ->
-- invalid_state (stage) -> same_person -> comment_required. Returns to recap_posted and stamps award_disagreed_at, so
-- the agency must pick again before the award is re-sent or posted alone.
-- ---------------------------------------------------------------------------
create function public.disagree_award(p_solicitation_id uuid, p_comment text)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval public.evaluations;
begin
  perform app.require_office();
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'award_check');
  perform app.require_award_checker(v_eval);
  if btrim(coalesce(p_comment, '')) = '' then
    raise exception 'comment_required' using errcode = 'P0001';
  end if;

  update public.evaluations
     set stage = 'recap_posted', award_disagreed_at = clock_timestamp()
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, null, auth.uid(), 'disagree_award', jsonb_build_object('comment', btrim(p_comment)));
end;
$$;

-- ---------------------------------------------------------------------------
-- post_award: the checker posts the award. Error order: not_authorized -> sealed -> invalid_state (stage, or no
-- posted recap) -> same_person -> pick_required. The snapshot is built from the latest pick and the posted recap.
-- ---------------------------------------------------------------------------
create function public.post_award(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval     public.evaluations;
  v_pick     public.award_picks;
  v_snapshot jsonb;
begin
  perform app.require_office();
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'award_check');
  perform app.require_award_checker(v_eval);
  v_pick := app.latest_award_pick(p_solicitation_id);
  if v_pick.id is null then
    raise exception 'pick_required' using errcode = 'P0001';
  end if;
  v_snapshot := app.build_award(app.posted_recap(p_solicitation_id), v_pick.bid_id);
  if v_snapshot is null then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.awards (solicitation_id, bid_id, pick_id, snapshot, prepared_by, checked_by, single_reviewer)
  values (p_solicitation_id, v_pick.bid_id, v_pick.id, v_snapshot, v_eval.award_preparer_id, auth.uid(), false);
  update public.evaluations set stage = 'awarded' where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, v_pick.bid_id, auth.uid(), 'post_award',
          jsonb_build_object('pick_id', v_pick.id, 'bid_id', v_pick.bid_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- post_award_alone: the single-reviewer fallback straight from recap_posted. Error order: not_authorized -> sealed ->
-- invalid_state (stage) -> pick_required -> invalid_state (no pick since the latest disagree_award). Stamped
-- single_reviewer = true; the audit detail carries
-- 'fallback' = 'no second reviewer available'.
-- ---------------------------------------------------------------------------
create function public.post_award_alone(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval     public.evaluations;
  v_pick     public.award_picks;
  v_snapshot jsonb;
begin
  perform app.require_office();
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'recap_posted');
  v_pick := app.latest_award_pick(p_solicitation_id);
  if v_pick.id is null then
    raise exception 'pick_required' using errcode = 'P0001';
  end if;
  if not app.award_pick_fresh(v_eval) then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  v_snapshot := app.build_award(app.posted_recap(p_solicitation_id), v_pick.bid_id);
  if v_snapshot is null then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.awards (solicitation_id, bid_id, pick_id, snapshot, prepared_by, checked_by, single_reviewer)
  values (p_solicitation_id, v_pick.bid_id, v_pick.id, v_snapshot, auth.uid(), null, true);
  update public.evaluations
     set stage = 'awarded', award_preparer_id = auth.uid()
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, v_pick.bid_id, auth.uid(), 'post_award_alone',
          jsonb_build_object('pick_id', v_pick.id, 'bid_id', v_pick.bid_id, 'fallback', 'no second reviewer available'));
end;
$$;

revoke all on function public.pick_award(uuid, uuid, text), public.current_award_pick(uuid),
  public.award_check_info(uuid), public.send_award_to_check(uuid), public.disagree_award(uuid, text),
  public.post_award(uuid), public.post_award_alone(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.pick_award(uuid, uuid, text), public.current_award_pick(uuid),
  public.award_check_info(uuid), public.send_award_to_check(uuid), public.disagree_award(uuid, text),
  public.post_award(uuid), public.post_award_alone(uuid)
  to authenticated;
