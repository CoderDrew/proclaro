-- 0027_addenda: addenda drafting (slice 2c, Task 2).
--
-- * public.addenda: one row per addendum. `data` is the full proposed solicitation data INCLUDING the
--   confidential fundingAmountCents (staff-only, like solicitation_funding). Numbers run 1, 2, 3... per
--   solicitation: a new addendum takes (published addenda) + 1, so a withdrawn number is reused and published
--   numbers never have gaps (partial unique index below).
-- * public.addendum_comments: append-only review comments (the review functions arrive in 0028).
-- * Both tables are read through RLS by staff only (app.can_see_solicitation); bidders and anon get nothing. Nobody
--   writes through the API: the definer functions here are the only writers.
-- * app.addendum_effective_state: after close an unpublished addendum counts as withdrawn (derived, not written by
--   a job), so the one-at-a-time guard ignores it.
-- * app.locked_fields: data keys an addendum may not change. Kept in sync with src/domain/addendum/lockedFields.ts by
--   src/domain/addendum/lockedFields.test.ts, which parses the list out of this file.
--
-- Every public function follows 0002: SECURITY DEFINER, empty search_path, check order
-- org kind -> row exists -> owning agency -> state -> per-row role, and one audit_log row whose action is the function
-- name (save_addendum excepted: it is an autosave, like solicitations.data). Audit details always carry addendum_id
-- and number. Writers re-check the deadline on clock_timestamp() after taking their lock (Ruling 8).
--
-- New error strings (errcode P0001): addendum_in_progress, locked_field, narrative_required.
-- Reused: not_authorized, not_found, invalid_state, invalid_data, reason_required, bids_closed, not_open.

-- ---------------------------------------------------------------------------
-- Types and tables
-- ---------------------------------------------------------------------------
create type public.addendum_state as enum
  ('draft', 'submitted', 'in_review', 'in_check', 'approved', 'published', 'withdrawn');

create table public.addenda (
  id                  uuid primary key default gen_random_uuid(),
  solicitation_id     uuid not null references public.solicitations (id),
  number              int not null check (number >= 1),
  state               public.addendum_state not null default 'draft',
  data                jsonb not null,
  narrative           text not null default '',
  created_by          uuid not null references public.profiles (user_id),
  created_at          timestamptz not null default now(),
  latest_submitted_at timestamptz,
  reviewer_id         uuid references public.profiles (user_id),
  checker_id          uuid references public.profiles (user_id),
  single_reviewer     boolean not null default false,
  published_version   int,
  withdrawn_reason    text,
  -- Same-person rule, as on solicitations: the reviewer can never be the checker.
  constraint addenda_reviewer_not_checker
    check (reviewer_id is null or checker_id is null or reviewer_id <> checker_id)
);
-- A withdrawn addendum gives its number back.
create unique index addenda_live_number on public.addenda (solicitation_id, number) where state <> 'withdrawn';
create index addenda_solicitation_id_idx on public.addenda (solicitation_id);

create table public.addendum_comments (
  id          uuid primary key default gen_random_uuid(),
  addendum_id uuid not null references public.addenda (id),
  field       text,
  body        text not null,
  kind        public.comment_kind not null,
  author_id   uuid not null references public.profiles (user_id),
  created_at  timestamptz not null default now()
);
create index addendum_comments_addendum_id_idx on public.addendum_comments (addendum_id);

create trigger addendum_comments_append_only
  before update or delete on public.addendum_comments
  for each row execute function app.reject_change();
create trigger addendum_comments_no_truncate
  before truncate on public.addendum_comments
  for each statement execute function app.reject_change();

revoke all on public.addenda, public.addendum_comments from public, anon, authenticated, service_role;
grant select on public.addenda, public.addendum_comments to authenticated;

alter table public.addenda enable row level security;
alter table public.addendum_comments enable row level security;

-- Staff only: office staff, or the owning agency.
create policy addenda_read on public.addenda for select to authenticated
  using (app.can_see_solicitation(solicitation_id));

create policy addendum_comments_read on public.addendum_comments for select to authenticated
  using (exists (select 1 from public.addenda a
                  where a.id = addendum_id and app.can_see_solicitation(a.solicitation_id)));

-- ---------------------------------------------------------------------------
-- Helpers (schema `app`, not exposed to API roles)
-- ---------------------------------------------------------------------------

-- Data keys an addendum may not change: history once published (spec §2). Parsed by lockedFields.test.ts.
create function app.locked_fields()
returns text[]
language sql immutable
set search_path = ''
as $$
  select array[
    -- locked-fields:start
    'releaseDate', 'adStart', 'adEnd', 'newspapers', 'category'
    -- locked-fields:end
  ]::text[];
$$;

-- Lock and return the addendum row, or raise not_found.
create function app.lock_addendum(p_id uuid)
returns public.addenda
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  select * into v_row from public.addenda a where a.id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  return v_row;
end;
$$;

-- After close an unpublished addendum can never be published, so it counts as withdrawn.
create function app.addendum_effective_state(p_row public.addenda)
returns public.addendum_state
language sql stable security definer
set search_path = ''
as $$
  select case
    when p_row.state <> 'published' and app.bids_closed(p_row.solicitation_id) then 'withdrawn'::public.addendum_state
    else p_row.state
  end;
$$;

-- The caller is an agency user of the solicitation's owning agency (org kind first, then ownership).
create function app.require_owning_agency(p_solicitation_id uuid)
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.solicitations s
                  where s.id = p_solicitation_id and s.agency_id = app.my_org()) then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
end;
$$;

-- Bidding is open now (bids_closed, then not_open) and still before the due time on the wall clock (Ruling 8).
-- Call it after the row lock is held.
create function app.require_addendum_window(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  perform app.require_bidding_open(p_solicitation_id);
  perform app.require_before_due_clock(p_solicitation_id);
end;
$$;

revoke all on function app.locked_fields(), app.lock_addendum(uuid), app.addendum_effective_state(public.addenda),
  app.require_owning_agency(uuid), app.require_addendum_window(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- start_addendum: agency user of the owning agency, on a published solicitation still open for bids, with no other
-- addendum in progress. The draft starts from the current data plus the current funding amount.
-- ---------------------------------------------------------------------------
create function public.start_addendum(p_solicitation_id uuid)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_sol    public.solicitations;
  v_number int;
  v_id     uuid;
begin
  if auth.uid() is null or not app.is_agency() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  -- The solicitation lock serializes numbering and the one-at-a-time guard.
  v_sol := app.lock_solicitation(p_solicitation_id);
  if v_sol.agency_id is distinct from app.my_org() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  perform app.require_state(v_sol, 'published');
  perform app.require_addendum_window(p_solicitation_id);

  if exists (select 1 from public.addenda a
              where a.solicitation_id = p_solicitation_id
                and app.addendum_effective_state(a) not in ('published', 'withdrawn')) then
    raise exception 'addendum_in_progress' using errcode = 'P0001';
  end if;

  select count(*)::int + 1 into v_number
    from public.addenda a
   where a.solicitation_id = p_solicitation_id and a.state = 'published';

  insert into public.addenda (solicitation_id, number, data, created_by)
  values (p_solicitation_id, v_number,
          v_sol.data || jsonb_build_object('fundingAmountCents', app.funding_cents(p_solicitation_id)),
          auth.uid())
  returning id into v_id;

  perform app.audit(p_solicitation_id, 'start_addendum', jsonb_build_object(
    'addendum_id', v_id, 'number', v_number, 'to', 'draft'));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- save_addendum: owning agency, draft, while bidding is open. Not audited (autosave).
-- ---------------------------------------------------------------------------
create function public.save_addendum(p_addendum_id uuid, p_data jsonb, p_narrative text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row  public.addenda;
  v_base jsonb;
begin
  if auth.uid() is null or not app.is_agency() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  v_row := app.lock_addendum(p_addendum_id);
  perform app.require_owning_agency(v_row.solicitation_id);
  if v_row.state <> 'draft' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);

  if jsonb_typeof(p_data) is distinct from 'object' or not (p_data ?& app.required_data_keys()) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  select s.data into v_base from public.solicitations s where s.id = v_row.solicitation_id;
  if exists (select 1 from unnest(app.locked_fields()) k
              where (p_data -> k) is distinct from (v_base -> k)) then
    raise exception 'locked_field' using errcode = 'P0001';
  end if;

  update public.addenda a
     set data = p_data, narrative = coalesce(p_narrative, '')
   where a.id = p_addendum_id and a.state = 'draft';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- submit_addendum: owning agency, draft -> submitted, while bidding is open; the narrative is required.
-- ---------------------------------------------------------------------------
create function public.submit_addendum(p_addendum_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  if auth.uid() is null or not app.is_agency() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  v_row := app.lock_addendum(p_addendum_id);
  perform app.require_owning_agency(v_row.solicitation_id);
  if v_row.state <> 'draft' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);
  if btrim(v_row.narrative) = '' then
    raise exception 'narrative_required' using errcode = 'P0001';
  end if;

  update public.addenda a
     set state = 'submitted', latest_submitted_at = now()
   where a.id = p_addendum_id and a.state = 'draft';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(v_row.solicitation_id, 'submit_addendum', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number, 'from', 'draft', 'to', 'submitted'));
end;
$$;

-- ---------------------------------------------------------------------------
-- withdraw_addendum: the owning agency from draft; office staff from any unpublished state. Terminal. No deadline
-- check: after close the addendum already counts as withdrawn, and writing it down changes nothing else.
-- (Questions picked into the addendum go back to open: wired in 0032, once addendum_answers exists.)
-- ---------------------------------------------------------------------------
create function public.withdraw_addendum(p_addendum_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row    public.addenda;
  v_office boolean := app.is_office();
begin
  if auth.uid() is null or not (v_office or app.is_agency()) then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  v_row := app.lock_addendum(p_addendum_id);
  if not v_office then
    perform app.require_owning_agency(v_row.solicitation_id);
  end if;
  if (v_office and v_row.state in ('published', 'withdrawn'))
     or (not v_office and v_row.state <> 'draft') then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;

  update public.addenda a
     set state = 'withdrawn', withdrawn_reason = btrim(p_reason)
   where a.id = p_addendum_id and a.state = v_row.state;
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(v_row.solicitation_id, 'withdraw_addendum', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number, 'from', v_row.state, 'to', 'withdrawn',
    'reason', btrim(p_reason)));
end;
$$;

revoke all on function public.start_addendum(uuid), public.save_addendum(uuid, jsonb, text),
  public.submit_addendum(uuid), public.withdraw_addendum(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.start_addendum(uuid), public.save_addendum(uuid, jsonb, text),
  public.submit_addendum(uuid), public.withdraw_addendum(uuid, text)
  to authenticated;
