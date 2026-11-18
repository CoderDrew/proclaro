-- 0008_registration: bidder companies, self-service bidder registration, and agency-only solicitation policies.
--
-- A self-signed-up account has no profile and therefore no role. register_bidder is the only way for it to
-- gain one, and it can only ever create a bidder organization (never an agency or office role). Staff remain
-- invite-only: an account with auth.users.invited_at set is refused. No one else can put a profile into a bidder
-- organization (profiles_bidder_org_guard), and administrators cannot create or rename one.

-- ---------------------------------------------------------------------------
-- Bidder company details. The legal name is organizations.name (already unique).
-- ---------------------------------------------------------------------------
create table public.bidder_companies (
  org_id               uuid primary key references public.organizations (id),
  address              text not null check (btrim(address) <> ''),
  contact_name         text not null check (btrim(contact_name) <> ''),
  contact_phone        text not null check (btrim(contact_phone) <> ''),
  contact_email        text not null check (btrim(contact_email) <> ''),
  resident_claimed     boolean not null default false,
  resident_certificate text,
  created_at           timestamptz not null default now(),
  constraint bidder_companies_certificate_matches_claim
    check (resident_claimed = (resident_certificate is not null and btrim(resident_certificate) <> ''))
);

-- ---------------------------------------------------------------------------
-- Role helpers
-- ---------------------------------------------------------------------------
create function app.my_org_kind()
returns public.org_kind
language sql stable security definer
set search_path = ''
as $$
  select o.kind
  from public.profiles p
  join public.organizations o on o.id = p.org_id
  where p.user_id = auth.uid();
$$;

create function app.is_agency()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(app.my_org_kind() = 'agency', false);
$$;

create function app.is_bidder()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(app.my_org_kind() = 'bidder', false);
$$;

revoke all on function app.my_org_kind(), app.is_agency(), app.is_bidder()
  from public, anon, authenticated, service_role;
grant execute on function app.my_org_kind(), app.is_agency(), app.is_bidder()
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- register_bidder: organization + company row + profile in one transaction.
-- ---------------------------------------------------------------------------
create function public.register_bidder(
  p_legal_name text,
  p_address text,
  p_contact_name text,
  p_contact_phone text,
  p_contact_email text,
  p_resident_claimed boolean,
  p_resident_certificate text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_invited timestamptz;
  v_org     uuid;
  v_claimed boolean := coalesce(p_resident_claimed, false);
  v_cert    text := nullif(btrim(coalesce(p_resident_certificate, '')), '');
begin
  if v_uid is null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  select u.invited_at into v_invited from auth.users u where u.id = v_uid;
  if not found or v_invited is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.profiles p where p.user_id = v_uid) then
    raise exception 'already_registered' using errcode = 'P0001';
  end if;

  if coalesce(btrim(p_legal_name), '') = ''
     or coalesce(btrim(p_address), '') = ''
     or coalesce(btrim(p_contact_name), '') = ''
     or coalesce(btrim(p_contact_phone), '') = ''
     or coalesce(btrim(p_contact_email), '') = ''
     or v_claimed <> (v_cert is not null) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  begin
    insert into public.organizations (name, kind)
    values (btrim(p_legal_name), 'bidder')
    returning id into v_org;
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P0001';
  end;

  insert into public.bidder_companies (org_id, address, contact_name, contact_phone, contact_email,
                                       resident_claimed, resident_certificate)
  values (v_org, btrim(p_address), btrim(p_contact_name), btrim(p_contact_phone), btrim(p_contact_email),
          v_claimed, v_cert);

  -- The only sanctioned way into a bidder organization (profiles_bidder_org_guard below): a transaction-local
  -- flag naming exactly this new org, cleared again straight after the insert.
  perform set_config('app.registering', v_org::text, true);
  begin
    insert into public.profiles (user_id, org_id, display_name, is_admin)
    values (v_uid, v_org, btrim(p_contact_name), false);
  exception when unique_violation then
    -- A concurrent registration by the same user won the race.
    raise exception 'already_registered' using errcode = 'P0001';
  end;
  perform set_config('app.registering', '', true);

  return v_org;
end;
$$;

revoke all on function public.register_bidder(text, text, text, text, text, boolean, text)
  from public, anon, authenticated, service_role;
grant execute on function public.register_bidder(text, text, text, text, text, boolean, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Bidder-org membership guard. Nobody joins a bidder organization except through register_bidder: not an
-- administrator (the invite flow inserts profiles with the service-role client), not service_role, not a definer
-- function. A profile insert, or an update that moves a profile into a different org, raises not_authorized when
-- the target org is a bidder org, unless the transaction-local flag `app.registering` (set only by
-- register_bidder, for the org it just created) names that org. Security definer so the org-kind lookup is not
-- hidden by the caller's RLS (organizations_read hides bidder orgs from most roles). The flag is not a boundary
-- against a direct database connection: like the database superuser, that is outside the API's threat model.
-- ---------------------------------------------------------------------------
create function app.guard_bidder_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.org_id is not distinct from old.org_id then
    return new;
  end if;
  if exists (select 1 from public.organizations o where o.id = new.org_id and o.kind = 'bidder')
     and coalesce(current_setting('app.registering', true), '') <> new.org_id::text then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke all on function app.guard_bidder_profile() from public, anon, authenticated, service_role;

create trigger profiles_bidder_org_guard
  before insert or update of org_id on public.profiles
  for each row execute function app.guard_bidder_profile();

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------
-- Administrators manage agencies and offices only. A bidder org is created by register_bidder and its legal name
-- is the bidder's own (an admin renaming it would change what the office reads as the bidder's name).
drop policy organizations_admin_insert on public.organizations;
create policy organizations_admin_insert on public.organizations for insert to authenticated
  with check ((select app.is_admin()) and kind <> 'bidder');
drop policy organizations_admin_update on public.organizations;
create policy organizations_admin_update on public.organizations for update to authenticated
  using ((select app.is_admin()) and kind <> 'bidder')
  with check ((select app.is_admin()) and kind <> 'bidder');

-- Agency-only drafts. `not is_office()` would let a bidder insert a draft for its own org.
drop policy solicitations_insert_draft on public.solicitations;
create policy solicitations_insert_draft on public.solicitations for insert to authenticated
  with check (
    state = 'draft'
    and agency_id = (select app.my_org())
    and created_by = (select auth.uid())
    and (select app.is_agency())
  );

drop policy solicitations_update_draft on public.solicitations;
create policy solicitations_update_draft on public.solicitations for update to authenticated
  using (
    state = 'draft'
    and agency_id = (select app.my_org())
    and (select app.is_agency())
  )
  with check (state = 'draft' and agency_id = (select app.my_org()));

-- Registered bidders are not a public list.
drop policy organizations_read on public.organizations;
create policy organizations_read on public.organizations for select to anon, authenticated
  using (kind <> 'bidder' or id = (select app.my_org()) or (select app.is_office()));

-- Company details: own org's members and office staff. No write grants: registration is function-only.
alter table public.bidder_companies enable row level security;
revoke all on public.bidder_companies from anon, authenticated;
grant select on public.bidder_companies to authenticated;
create policy bidder_companies_read on public.bidder_companies for select to authenticated
  using (org_id = (select app.my_org()) or (select app.is_office()));

-- Office staff are visible to agency users (names on comments), not to bidders or accounts with no profile.
drop policy profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (
    user_id = (select auth.uid())
    or org_id = (select app.my_org())
    or (select app.is_office())
    or ((select app.is_agency())
        and exists (select 1 from public.organizations o where o.id = org_id and o.kind = 'office'))
  );
