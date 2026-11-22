-- 0026_versions: version history (slice 2c, Task 1).
--
-- * public.solicitation_versions: one append-only row per published version. Version 1 is written by
--   publish_solicitation (and backfilled below for rows published before this migration); version n is written by
--   publish_addendum (addendum n - 1, a later task). solicitations.version, published_snapshot, data, bid_due_at,
--   rfb_path and bid_form_path stay the CURRENT pointer, so every 2a/2b reader keeps working unchanged.
-- * public.solicitation_funding_changes: an addendum may change the confidential funding amount; the change is
--   frozen here per version (same confidentiality as solicitation_funding). app.funding_cents prefers the highest
--   version, and app.funding_from_estimate counts it as a frozen amount.
-- * app.reject_published_change: a published row stays frozen, except that publish_addendum may move the pointer
--   columns. It opts in with the transaction-local setting app.publishing_addendum = the solicitation id; nothing
--   else on the row may change, and delete is never allowed.
-- * app.last_schedule_change: the latest version whose addendum changed the bid schedule (1 when none did).
-- * public.solicitation_version_list: the version history for the public solicitation page.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.solicitation_versions (
  solicitation_id  uuid not null references public.solicitations (id),
  version          int not null check (version >= 1),
  snapshot         jsonb not null,
  rfb_path         text not null,
  bid_form_path    text not null,
  addendum_path    text,
  bid_due_at       timestamptz not null,
  published_at     timestamptz not null default now(),
  published_by     uuid references public.profiles (user_id),
  schedule_changed boolean not null default false,
  primary key (solicitation_id, version),
  -- Version 1 is the original publish; every later version is an addendum with its own PDF.
  constraint solicitation_versions_addendum_path check ((version = 1) = (addendum_path is null)),
  -- Snapshots are publicly readable, so (Ruling 2, 0014) they never carry the confidential funding amount.
  constraint solicitation_versions_no_funding check (not jsonb_path_exists(snapshot, '$.**.fundingAmountCents'))
);

create table public.solicitation_funding_changes (
  solicitation_id uuid not null,
  -- Version 1's amount is solicitation_funding; a change belongs to an addendum's version.
  version         int not null check (version >= 2),
  funding_cents   bigint not null check (funding_cents >= 0),
  frozen_at       timestamptz not null default now(),
  primary key (solicitation_id, version),
  foreign key (solicitation_id, version) references public.solicitation_versions (solicitation_id, version)
);

create trigger solicitation_versions_append_only
  before update or delete on public.solicitation_versions
  for each row execute function app.reject_change();
create trigger solicitation_versions_no_truncate
  before truncate on public.solicitation_versions
  for each statement execute function app.reject_change();
create trigger solicitation_funding_changes_append_only
  before update or delete on public.solicitation_funding_changes
  for each row execute function app.reject_change();
create trigger solicitation_funding_changes_no_truncate
  before truncate on public.solicitation_funding_changes
  for each statement execute function app.reject_change();

-- Read through RLS only; nobody writes through the API (definer functions are the only writers).
revoke all on public.solicitation_versions, public.solicitation_funding_changes
  from public, anon, authenticated, service_role;
grant select on public.solicitation_versions to anon, authenticated;
grant select on public.solicitation_funding_changes to authenticated;

alter table public.solicitation_versions enable row level security;
alter table public.solicitation_funding_changes enable row level security;

-- Same rule as the solicitation row: public once published and released (solicitations_read_public), or staff
-- (office, owning agency).
create policy solicitation_versions_read on public.solicitation_versions for select to anon, authenticated
  using (
    exists (select 1 from public.solicitations s
             where s.id = solicitation_id and s.state = 'published' and s.release_date <= (select app.today()))
    or app.can_see_solicitation(solicitation_id)
  );

-- Same rule as solicitation_funding: owning agency or office staff; anon has no grant.
create policy solicitation_funding_changes_read on public.solicitation_funding_changes for select to authenticated
  using (app.can_see_solicitation(solicitation_id));

-- ---------------------------------------------------------------------------
-- The freeze, with the publish_addendum exception. Replaces the 0001 definition (its only one).
-- ---------------------------------------------------------------------------
create or replace function app.reject_published_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  -- The current pointer: the only columns publish_addendum may move.
  v_pointer constant text[] := array['version', 'published_snapshot', 'data', 'bid_due_at', 'rfb_path',
                                     'bid_form_path'];
begin
  if old.state = 'published' then
    if tg_op = 'UPDATE'
       and current_setting('app.publishing_addendum', true) = old.id::text
       and (to_jsonb(new) - v_pointer) = (to_jsonb(old) - v_pointer) then
      return new;
    end if;
    raise exception 'solicitation % is published and read-only', old.id
      using errcode = 'P0001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- ---------------------------------------------------------------------------
-- app.funding_cents: the highest-version funding change first, else the 0014 behaviour (solicitation_funding,
-- then the published estimate). Replaces the 0014 definition (its latest).
-- ---------------------------------------------------------------------------
create or replace function app.funding_cents(p_id uuid)
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select c.funding_cents from public.solicitation_funding_changes c
      where c.solicitation_id = p_id order by c.version desc limit 1),
    (select f.funding_cents from public.solicitation_funding f where f.solicitation_id = p_id),
    (select coalesce((s.published_snapshot -> 'data' ->> 'estimateCents')::bigint, (s.data ->> 'estimateCents')::bigint)
       from public.solicitations s where s.id = p_id)
  );
$$;
revoke all on function app.funding_cents(uuid) from public, anon, authenticated, service_role;

-- app.funding_from_estimate: true only when no funding amount was ever frozen, neither at publish
-- (solicitation_funding) nor by an addendum (solicitation_funding_changes). Replaces the 0014 definition (its latest).
create or replace function app.funding_from_estimate(p_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select not exists (select 1 from public.solicitation_funding f where f.solicitation_id = p_id)
     and not exists (select 1 from public.solicitation_funding_changes c where c.solicitation_id = p_id);
$$;
revoke all on function app.funding_from_estimate(uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- app.last_schedule_change: the latest version whose addendum changed the bid schedule, else 1 (the original).
-- ---------------------------------------------------------------------------
create function app.last_schedule_change(p_solicitation_id uuid)
returns int
language sql stable security definer
set search_path = ''
as $$
  select coalesce(max(v.version) filter (where v.schedule_changed), 1)
    from public.solicitation_versions v
   where v.solicitation_id = p_solicitation_id;
$$;
revoke all on function app.last_schedule_change(uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- public.solicitation_version_list: every version, oldest first, with the current one marked. Visible exactly when
-- the version rows are (solicitation_versions_read).
-- ---------------------------------------------------------------------------
create function public.solicitation_version_list(p_solicitation_id uuid)
returns table (version int, published_at timestamptz, rfb_path text, bid_form_path text, addendum_path text,
               is_current boolean)
language sql stable security definer
set search_path = ''
as $$
  select v.version, v.published_at, v.rfb_path, v.bid_form_path, v.addendum_path, v.version = s.version
    from public.solicitation_versions v
    join public.solicitations s on s.id = v.solicitation_id
   where v.solicitation_id = p_solicitation_id
     and ((s.state = 'published' and s.release_date <= app.today())
          or app.can_see_solicitation(s.id))
   order by v.version;
$$;
revoke all on function public.solicitation_version_list(uuid) from public, anon, authenticated, service_role;
grant execute on function public.solicitation_version_list(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- publish_solicitation: the 0014 body (its latest), plus the version-1 row.
-- ---------------------------------------------------------------------------
create or replace function public.publish_solicitation(
  p_id uuid,
  p_rfb_path text,
  p_bid_form_path text,
  p_snapshot jsonb,
  p_bid_due_at timestamptz,
  p_funding_cents bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row         public.solicitations;
  v_release     date;
  v_bid_due     timestamptz;
  v_funding_raw jsonb;
  v_funding_num numeric;
  v_funding     bigint;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'approved');
  if auth.uid() is distinct from v_row.reviewer_id and auth.uid() is distinct from v_row.checker_id then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  if p_rfb_path is null or btrim(p_rfb_path) = ''
     or p_bid_form_path is null or btrim(p_bid_form_path) = ''
     or p_snapshot is null or p_snapshot in ('null'::jsonb, '{}'::jsonb)
     or p_bid_due_at is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  if p_rfb_path <> format('solicitations/%s/v1/rfb.pdf', p_id)
     or p_bid_form_path <> format('solicitations/%s/v1/bid-form.pdf', p_id) then
    raise exception 'invalid_paths' using errcode = 'P0001';
  end if;

  -- 1. The stored funding amount is a non-negative whole number of cents.
  v_funding_raw := v_row.data -> 'fundingAmountCents';
  if jsonb_typeof(v_funding_raw) is distinct from 'number' then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  v_funding_num := v_funding_raw::numeric;
  if v_funding_num < 0 or v_funding_num <> trunc(v_funding_num) or v_funding_num > 9223372036854775807 then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  v_funding := v_funding_num::bigint;

  -- 2. The caller validated the same amount, and kept it out of the public snapshot.
  if p_funding_cents is distinct from v_funding
     or jsonb_path_exists(p_snapshot, '$.**.fundingAmountCents') then
    raise exception 'snapshot_mismatch' using errcode = 'P0001';
  end if;

  begin
    v_release := (v_row.data ->> 'releaseDate')::date;
  exception when others then
    v_release := null;
  end;
  if v_release is null or v_release < app.today() then
    raise exception 'invalid_release_date' using errcode = 'P0001';
  end if;

  v_bid_due := app.bid_due_at(v_row.data);
  if v_bid_due is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if p_bid_due_at <> v_bid_due then
    raise exception 'bid_due_mismatch' using errcode = 'P0001';
  end if;

  update public.solicitations s
     set state = 'published',
         version = 1,
         published_at = now(),
         release_date = v_release,
         rfb_path = p_rfb_path,
         bid_form_path = p_bid_form_path,
         published_snapshot = p_snapshot,
         bid_due_at = v_bid_due,
         data = v_row.data - 'fundingAmountCents'
   where s.id = p_id and s.state = 'approved';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.solicitation_funding (solicitation_id, funding_cents) values (p_id, v_funding);

  -- Version history: the original publish is version 1 (no addendum; published_at matches the row's now()).
  insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path,
                                            bid_due_at, published_at, published_by)
  values (p_id, 1, p_snapshot, p_rfb_path, p_bid_form_path, v_bid_due, now(), auth.uid());

  -- audit_log is staff-only (agency + office), like the funding amount itself.
  perform app.audit(p_id, 'publish_solicitation', jsonb_build_object(
    'from', 'approved', 'to', 'published', 'version', 1,
    'release_date', v_release, 'bid_due_at', v_bid_due,
    'rfb_path', p_rfb_path, 'bid_form_path', p_bid_form_path,
    'funding_cents', v_funding));
end;
$$;

revoke all on function public.publish_solicitation(uuid, text, text, jsonb, timestamptz, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.publish_solicitation(uuid, text, text, jsonb, timestamptz, bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Backfill: version 1 for every solicitation already published, from its current columns (publisher unknown).
-- A local reset runs this before seed.sql, so the seed repeats the same statement for its directly inserted rows.
-- ---------------------------------------------------------------------------
insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path, bid_due_at,
                                          published_at, published_by)
select s.id, 1, s.published_snapshot, s.rfb_path, s.bid_form_path, s.bid_due_at, coalesce(s.published_at, now()), null
  from public.solicitations s
 where s.state = 'published'
on conflict (solicitation_id, version) do nothing;
