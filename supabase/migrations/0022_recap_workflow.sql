-- 0022_recap_workflow: prepare, check, post and freeze the recap, or the "all bids rejected" memo (slice 2b, Task 9).
--
-- The posted recap is the only public disclosure of bids. The flow on public.evaluations (0018):
--   bid_review --send_recap_to_check--> recap_check --post_recap--> recap_posted | all_rejected
--              <--disagree_recap------
--   bid_review --post_recap_alone (single-reviewer fallback)--> recap_posted | all_rejected
-- Two-person check: the checker (post_recap / disagree_recap) must not be anyone who ever reviewed these bids
-- (app.was_evaluation_reviewer: set an outcome, verified a resident claim, sent flags to the agency or sent the recap
-- to check). The fallback is stamped single_reviewer = true and its audit detail carries
-- 'fallback' = 'no second reviewer available'.
--
-- recap_draft (the unposted snapshot: bidder names, prices, ranks and the confidential funding amount) has no API
-- grant (0018 column grant). The office reads it through public.recap_draft. A posted recaps row is public.
--
-- Database clock (Ruling 8): app.recap_bids, app.build_recap and app.recap_blockers gain a trailing
-- p_now timestamptz default now() passed through to app.bid_review_status. Reads keep now(); the writers below call
-- them with clock_timestamp() after taking app.lock_evaluation, both for the readiness check and for the snapshot /
-- recap_stale comparison.

-- ---------------------------------------------------------------------------
-- 0021 helpers recreated with p_now (statuses as of p_now; reads pass now() by default).
-- preview_recap is plpgsql (no hard dependency); it is recreated below to call the new signatures explicitly.
-- ---------------------------------------------------------------------------
drop function app.build_recap(uuid);
drop function app.recap_blockers(uuid);
drop function app.recap_bids(uuid);

-- The recap-eligible bids of a solicitation as rank_recap input, ordered by reference: latest non-withdrawn version
-- with app.bid_review_status (as of p_now) accepted or flag_accepted. resident is the office's latest verification
-- verdict (app.resident_verified). Reads only; no gates (the caller gates).
create function app.recap_bids(p_solicitation_id uuid, p_now timestamptz default now())
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'bidId', b.id, 'reference', b.reference, 'bidderName', v.bidder_legal_name,
           'baseCents', coalesce((select sum(x) from unnest(v.item_cents) x), 0)::bigint,
           'alternateCents', to_jsonb(coalesce(v.alternate_cents, '{}'::bigint[])),
           'resident', app.resident_verified(b.id),
           'apprentice', coalesce(v.apprentice_commitment, false))
         order by b.reference), '[]'::jsonb)
    from public.bids b
    join public.bid_versions v on v.bid_id = b.id and v.version = app.latest_version(b.id)
    cross join lateral app.bid_review_status(b.id, p_now) s
   where b.solicitation_id = p_solicitation_id
     and not app.is_withdrawn(b.id, v.version)
     and s.status in ('accepted', 'flag_accepted');
$$;

-- The full recap snapshot (rank_recap plus solicitationNumber, alternates and fundingFromEstimate), statuses as of
-- p_now. not_found for an unknown solicitation. No gates: callers gate.
create function app.build_recap(p_solicitation_id uuid, p_now timestamptz default now())
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_sol   public.solicitations;
  v_data  jsonb;
  v_alts  jsonb;
  v_kinds text[];
begin
  select s.* into v_sol from public.solicitations s where s.id = p_solicitation_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  v_data := coalesce(v_sol.published_snapshot -> 'data', v_sol.data);
  v_alts := coalesce(v_data -> 'schedule' -> 'alternates', '[]'::jsonb);
  select coalesce(array_agg(a.value ->> 'kind' order by a.ordinality), '{}') into v_kinds
    from jsonb_array_elements(v_alts) with ordinality a;

  return app.rank_recap(app.recap_bids(p_solicitation_id, p_now), v_kinds, app.funding_cents(p_solicitation_id),
                        (v_data ->> 'estimateCents')::bigint)
         || jsonb_build_object('solicitationNumber', v_sol.number, 'alternates', v_alts,
                               'fundingFromEstimate', app.funding_from_estimate(p_solicitation_id));
end;
$$;

-- Why the recap cannot be sent to check yet, in this order, each code at most once: cure_pending, undecided_bids,
-- flags_pending, resident_unverified. Statuses as of p_now. Empty array when nothing blocks.
create function app.recap_blockers(p_solicitation_id uuid, p_now timestamptz default now())
returns text[]
language sql stable security definer
set search_path = ''
as $$
  with st as (
    select b.id, s.status
      from public.bids b
      cross join lateral app.bid_review_status(b.id, p_now) s
     where b.solicitation_id = p_solicitation_id
  )
  select array_remove(array[
    case when exists (select 1 from st where st.status = 'pending_cure') then 'cure_pending' end,
    case when exists (select 1 from st where st.status = 'undecided') then 'undecided_bids' end,
    case when exists (select 1 from st where st.status = 'flagged') then 'flags_pending' end,
    case when exists (select 1 from st where st.status in ('accepted', 'flag_accepted')
                                         and app.resident_unverified(st.id)) then 'resident_unverified' end
  ]::text[], null);
$$;

revoke all on function app.recap_bids(uuid, timestamptz), app.build_recap(uuid, timestamptz),
  app.recap_blockers(uuid, timestamptz)
  from public, anon, authenticated, service_role;

create or replace function public.preview_recap(p_solicitation_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  perform app.open_bids_gate(p_solicitation_id);
  return jsonb_build_object('recap', app.build_recap(p_solicitation_id, now()),
                            'blockers', to_jsonb(app.recap_blockers(p_solicitation_id, now())));
end;
$$;

revoke all on function public.preview_recap(uuid) from public, anon, authenticated, service_role;
grant execute on function public.preview_recap(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- recaps: the posted recap or memo. One row per solicitation (primary key), append-only, public once it exists.
-- ---------------------------------------------------------------------------
create type public.recap_kind as enum ('recap', 'all_rejected');

create table public.recaps (
  solicitation_id uuid primary key references public.solicitations (id),
  kind            public.recap_kind not null,
  snapshot        jsonb not null,
  prepared_by     uuid not null references public.profiles (user_id),
  checked_by      uuid references public.profiles (user_id),
  single_reviewer boolean not null,
  posted_at       timestamptz not null default now(),
  constraint recaps_single_reviewer_check check (single_reviewer = (checked_by is null)),
  constraint recaps_kind_matches_snapshot check (snapshot ->> 'kind' = kind::text)
);

create trigger recaps_append_only
  before update or delete on public.recaps for each row execute function app.reject_change();
create trigger recaps_no_truncate
  before truncate on public.recaps for each statement execute function app.reject_change();

revoke all on public.recaps from anon, authenticated, service_role;
grant select on public.recaps to anon, authenticated;

alter table public.recaps enable row level security;

-- Rows exist only once posted, and a posted recap is public.
create policy recaps_read on public.recaps
  for select to anon, authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- Helpers (schema `app`, no API role executes them)
-- ---------------------------------------------------------------------------

-- p_user reviewed these bids: the actor of any bid_audit_log row for the solicitation that sets an outcome, verifies a
-- resident claim, sends flags to the agency or sends the recap to check. No rounds: anyone who ever reviewed these
-- bids cannot check them.
create function app.was_evaluation_reviewer(p_solicitation_id uuid, p_user uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bid_audit_log l
     where l.solicitation_id = p_solicitation_id
       and l.actor_id = p_user
       and l.action in ('set_bid_outcome', 'verify_resident', 'send_flags_to_agency', 'send_recap_to_check'));
$$;

-- Raises the first app.recap_blockers code (statuses as of p_now; writers pass clock_timestamp() after the lock).
create function app.require_recap_ready(p_solicitation_id uuid, p_now timestamptz default now())
returns void
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_blockers text[] := app.recap_blockers(p_solicitation_id, p_now);
begin
  if cardinality(v_blockers) > 0 then
    raise exception '%', v_blockers[1] using errcode = 'P0001';
  end if;
end;
$$;

-- The stage a posted snapshot ends the recap at.
create function app.posted_stage(p_snapshot jsonb)
returns public.evaluation_stage
language sql immutable
set search_path = ''
as $$
  select case when p_snapshot ->> 'kind' = 'all_rejected' then 'all_rejected' else 'recap_posted' end
         ::public.evaluation_stage;
$$;

revoke all on function app.was_evaluation_reviewer(uuid, uuid), app.require_recap_ready(uuid, timestamptz),
  app.posted_stage(jsonb)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- send_recap_to_check: the preparer freezes the draft for a second person. Error order: not_authorized -> sealed
-- (lock_evaluation) -> invalid_state (stage) -> the first blocker (cure_pending, undecided_bids, flags_pending,
-- resident_unverified), judged on clock_timestamp() after the lock.
-- ---------------------------------------------------------------------------
create function public.send_recap_to_check(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval  public.evaluations;
  v_now   timestamptz;
  v_draft jsonb;
begin
  perform app.require_office();
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'bid_review');
  v_now := clock_timestamp();
  perform app.require_recap_ready(p_solicitation_id, v_now);
  v_draft := app.build_recap(p_solicitation_id, v_now);

  update public.evaluations
     set stage = 'recap_check', recap_preparer_id = auth.uid(), recap_draft = v_draft
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, null, auth.uid(), 'send_recap_to_check', jsonb_build_object('kind', v_draft ->> 'kind'));
end;
$$;

-- ---------------------------------------------------------------------------
-- disagree_recap: the checker sends the draft back with a comment. Error order: not_authorized -> sealed ->
-- invalid_state (stage) -> same_person (the caller reviewed these bids) -> comment_required.
-- ---------------------------------------------------------------------------
create function public.disagree_recap(p_solicitation_id uuid, p_comment text)
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
  if v_eval.recap_preparer_id = auth.uid() or app.was_evaluation_reviewer(p_solicitation_id, auth.uid()) then
    raise exception 'same_person' using errcode = 'P0001';
  end if;
  if btrim(coalesce(p_comment, '')) = '' then
    raise exception 'comment_required' using errcode = 'P0001';
  end if;

  update public.evaluations
     set stage = 'bid_review', recap_draft = null
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, null, auth.uid(), 'disagree_recap', jsonb_build_object('comment', btrim(p_comment)));
end;
$$;

-- ---------------------------------------------------------------------------
-- post_recap: the checker posts the draft. Error order: not_authorized -> sealed -> invalid_state (stage) ->
-- same_person -> recap_stale (the snapshot rebuilt on clock_timestamp() after the lock differs from the draft, e.g. a
-- post-close void changed a status). Inserts the public recaps row and ends the recap at recap_posted, or at
-- all_rejected for the memo.
-- ---------------------------------------------------------------------------
create function public.post_recap(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval public.evaluations;
  v_built jsonb;
begin
  perform app.require_office();
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'recap_check');
  if v_eval.recap_preparer_id = auth.uid() or app.was_evaluation_reviewer(p_solicitation_id, auth.uid()) then
    raise exception 'same_person' using errcode = 'P0001';
  end if;
  v_built := app.build_recap(p_solicitation_id, clock_timestamp());
  if v_eval.recap_draft is null or v_built is distinct from v_eval.recap_draft then
    raise exception 'recap_stale' using errcode = 'P0001';
  end if;

  insert into public.recaps (solicitation_id, kind, snapshot, prepared_by, checked_by, single_reviewer)
  values (p_solicitation_id, (v_built ->> 'kind')::public.recap_kind, v_built, v_eval.recap_preparer_id, auth.uid(), false);
  update public.evaluations
     set stage = app.posted_stage(v_built)
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, null, auth.uid(), 'post_recap', jsonb_build_object('kind', v_built ->> 'kind'));
end;
$$;

-- ---------------------------------------------------------------------------
-- post_recap_alone: the single-reviewer fallback straight from bid review. Error order: not_authorized -> sealed ->
-- invalid_state (stage) -> the first blocker (clock_timestamp() after the lock). Stamped single_reviewer = true; the
-- audit detail carries 'fallback' = 'no second reviewer available'.
-- ---------------------------------------------------------------------------
create function public.post_recap_alone(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_eval     public.evaluations;
  v_now      timestamptz;
  v_snapshot jsonb;
begin
  perform app.require_office();
  v_eval := app.lock_evaluation(p_solicitation_id);
  perform app.require_stage(v_eval, 'bid_review');
  v_now := clock_timestamp();
  perform app.require_recap_ready(p_solicitation_id, v_now);
  v_snapshot := app.build_recap(p_solicitation_id, v_now);

  insert into public.recaps (solicitation_id, kind, snapshot, prepared_by, checked_by, single_reviewer)
  values (p_solicitation_id, (v_snapshot ->> 'kind')::public.recap_kind, v_snapshot, auth.uid(), null, true);
  update public.evaluations
     set stage = app.posted_stage(v_snapshot), recap_preparer_id = auth.uid(), recap_draft = null
   where solicitation_id = p_solicitation_id;
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_solicitation_id, null, auth.uid(), 'post_recap_alone',
          jsonb_build_object('kind', v_snapshot ->> 'kind', 'fallback', 'no second reviewer available'));
end;
$$;

-- ---------------------------------------------------------------------------
-- recap_draft: the office's read of the draft under check (recap_draft has no API grant). Gates
-- (app.open_bids_gate): not_authorized (not office) -> not_found -> sealed. Returns {recap, preparedBy} (the
-- preparer's display name) while a draft exists, else null. Writes nothing beyond the gate's FOR SHARE.
-- ---------------------------------------------------------------------------
create function public.recap_draft(p_solicitation_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_draft jsonb;
  v_name  text;
begin
  perform app.open_bids_gate(p_solicitation_id);
  select e.recap_draft, p.display_name into v_draft, v_name
    from public.evaluations e
    left join public.profiles p on p.user_id = e.recap_preparer_id
   where e.solicitation_id = p_solicitation_id;
  if v_draft is null then
    return null;
  end if;
  return jsonb_build_object('recap', v_draft, 'preparedBy', v_name);
end;
$$;

revoke all on function public.send_recap_to_check(uuid), public.disagree_recap(uuid, text), public.post_recap(uuid),
  public.post_recap_alone(uuid), public.recap_draft(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.send_recap_to_check(uuid), public.disagree_recap(uuid, text), public.post_recap(uuid),
  public.post_recap_alone(uuid), public.recap_draft(uuid)
  to authenticated;
