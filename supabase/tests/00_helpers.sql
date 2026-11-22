-- Shared pgTAP helpers. This file runs first (00_ prefix) and is NOT wrapped in a
-- rolled-back transaction, so the `tests` schema persists for later test files.
-- Local test database only; nothing here ships in a migration.

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Create an auth user plus profile in the given organization. Returns the user id.
create or replace function tests.make_user(p_email text, p_org_id uuid, p_is_admin boolean default false)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
          p_email, '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

  insert into public.profiles (user_id, org_id, display_name, is_admin)
  values (v_id, p_org_id, p_email, p_is_admin);

  return v_id;
end;
$$;

-- Switch the current transaction to the `authenticated` role as the given user.
create or replace function tests.act_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
                     true);
end;
$$;

-- Switch the current transaction to the `anon` role.
create or replace function tests.act_as_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
end;
$$;

-- A solicitation `data` object carrying every top-level key the schema requires (so submit_solicitation accepts
-- it), with dates relative to app.today(), merged with the given overrides. Not a fully valid solicitation: the
-- database only checks keys; the app runs the full validation.
create or replace function tests.solicitation_data(p_overrides jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'shortTitle', 'Test', 'longTitle', 'Test solicitation', 'category', 'construction',
    'summary', 'Summary.', 'projectDescription', 'Description.', 'scopeNotes', '', 'specialProvisions', '',
    'location', jsonb_build_object('address', '1 Example Way', 'city', 'Calder City', 'county', 'Calder'),
    'requester', jsonb_build_object('name', 'Pat Example', 'email', 'pat@example.test', 'phone', '555-0100'),
    'projectManager', jsonb_build_object('name', 'Sam Example', 'email', 'sam@example.test', 'phone', '555-0101'),
    'estimateCents', 15000000, 'fundingAmountCents', 15000000, 'fundingSource', 'capital_construction', 'fundingOther', '', 'federalFunds', false,
    'releaseDate', to_char(app.today() + 7, 'YYYY-MM-DD'),
    'adStart', to_char(app.today() + 7, 'YYYY-MM-DD'), 'adEnd', to_char(app.today() + 28, 'YYYY-MM-DD'),
    'newspapers', 'Calder Courier',
    'questionsDue', jsonb_build_object('date', to_char(app.today() + 14, 'YYYY-MM-DD'), 'time', '13:00'),
    'answersDue', jsonb_build_object('date', to_char(app.today() + 18, 'YYYY-MM-DD'), 'time', '13:00'),
    'bidDueDate', to_char(app.today() + 28, 'YYYY-MM-DD'), 'bidDueTime', '13:00',
    'tentativeAwardDate', null, 'estimatedStartDate', null, 'estimatedCompletionDate', null,
    'bidValidityDays', 90,
    'preBid', jsonb_build_object('kind', 'none', 'format', null, 'date', null, 'time', null, 'location', ''),
    'backgroundCheck', jsonb_build_object('required', false, 'contact', '', 'leadDays', null),
    'schedule', jsonb_build_object('items', jsonb_build_array(jsonb_build_object('name', 'Base bid', 'description', '')),
                                   'alternates', '[]'::jsonb),
    'optionalSections', '[]'::jsonb, 'pageLimits', '{}'::jsonb, 'attachments', '[]'::jsonb
  ) || coalesce(p_overrides, '{}'::jsonb);
$$;

-- The bid due instant publish_solicitation will compute for the given data (bidDueDate + bidDueTime, settings zone).
create or replace function tests.bid_due_at(p_data jsonb)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select app.bid_due_at(p_data);
$$;

revoke all on function tests.make_user(text, uuid, boolean) from public, anon, authenticated;
grant execute on function tests.solicitation_data(jsonb) to anon, authenticated, service_role;
grant execute on function tests.bid_due_at(jsonb) to anon, authenticated, service_role;
grant execute on function tests.act_as(uuid) to anon, authenticated, service_role;
grant execute on function tests.act_as_anon() to anon, authenticated, service_role;

-- An auth user with NO profile (a self-signed-up account before registration). p_invited sets invited_at.
create or replace function tests.make_auth_user(p_email text, p_invited boolean default false)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, invited_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
          p_email, '', now(), case when p_invited then now() end,
          '{"provider":"email","providers":["email"]}', '{}', now(), now());
  return v_id;
end;
$$;

-- A bidder organization, its company row and a user (profile in that org). Returns the user id.
create or replace function tests.make_bidder(p_email text, p_org_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := gen_random_uuid();
  v_id  uuid;
begin
  insert into public.organizations (id, name, kind) values (v_org, p_org_name, 'bidder');
  insert into public.bidder_companies (org_id, address, contact_name, contact_phone, contact_email)
  values (v_org, '1 Test Rd', p_email, '555-0100', p_email);
  v_id := tests.make_auth_user(p_email);
  -- Bidder-org profiles are guarded (0008): set the same transaction-local flag register_bidder sets.
  perform set_config('app.registering', v_org::text, true);
  insert into public.profiles (user_id, org_id, display_name, is_admin) values (v_id, v_org, p_email, false);
  perform set_config('app.registering', '', true);
  return v_id;
end;
$$;

-- Switch the current transaction to `service_role`.
create or replace function tests.act_as_service_role()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
end;
$$;

revoke all on function tests.make_auth_user(text, boolean) from public, anon, authenticated;
revoke all on function tests.make_bidder(text, text) from public, anon, authenticated;
grant execute on function tests.act_as_service_role() to anon, authenticated, service_role;

-- A published, released solicitation inserted directly (the frozen trigger fires only on update/delete).
-- Default data: two schedule items, one deductive alternate, estimate $150,000, optional section "references".
-- As publish_solicitation does (0014, Ruling 2), the funding amount is moved out of the public data and snapshot
-- into solicitation_funding; an override of "fundingAmountCents": null leaves no funding row (estimate fallback).
create or replace function tests.make_published_solicitation(
  p_agency uuid, p_author uuid, p_bid_due_at timestamptz, p_overrides jsonb default '{}'::jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id   uuid := gen_random_uuid();
  v_data jsonb := tests.solicitation_data(jsonb_build_object(
    'schedule', jsonb_build_object(
      'items', jsonb_build_array(
        jsonb_build_object('name', 'Base bid', 'description', 'Site work'),
        jsonb_build_object('name', 'Item 2', 'description', 'Roofing')),
      'alternates', jsonb_build_array(
        jsonb_build_object('kind', 'deductive', 'description', 'Omit canopy'))),
    'estimateCents', 15000000,
    'optionalSections', jsonb_build_array('references')) || coalesce(p_overrides, '{}'::jsonb));
  v_funding bigint := (v_data ->> 'fundingAmountCents')::bigint;
begin
  v_data := v_data - 'fundingAmountCents';
  insert into public.solicitations (id, agency_id, created_by, state, number, fiscal_year, data, version,
                                    published_at, release_date, bid_due_at, published_snapshot)
  values (v_id, p_agency, p_author, 'published', 'TB-' || left(v_id::text, 8), extract(year from app.today())::int,
          v_data, 1, now(), app.today(), p_bid_due_at,
          jsonb_build_object('data', v_data, 'clauses', '{}'::jsonb, 'settings', '{}'::jsonb));
  if v_funding is not null then
    insert into public.solicitation_funding (solicitation_id, funding_cents) values (v_id, v_funding);
  end if;
  return v_id;
end;
$$;

-- Move a published solicitation's bid due time. Test transactions only (always rolled back).
create or replace function tests.set_bid_due(p_id uuid, p_at timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  alter table public.solicitations disable trigger solicitations_published_frozen;
  update public.solicitations set bid_due_at = p_at where id = p_id;
  alter table public.solicitations enable trigger solicitations_published_frozen;
end;
$$;

-- Stage the three PDFs of version p_version in the published bucket (the stand-in for the office's uploads), so
-- publish_addendum's file check (0035) passes. Skips names already present. Test transactions only.
create or replace function tests.stage_version_files(p_solicitation_id uuid, p_version int)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into storage.objects (bucket_id, name)
  select 'published', format('solicitations/%s/v%s/%s', p_solicitation_id, p_version, f)
    from unnest(array['rfb.pdf', 'bid-form.pdf', 'addendum.pdf']) f
   where not exists (select 1 from storage.objects o where o.bucket_id = 'published'
                       and o.name = format('solicitations/%s/v%s/%s', p_solicitation_id, p_version, f));
$$;

revoke all on function tests.make_published_solicitation(uuid, uuid, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function tests.set_bid_due(uuid, timestamptz) from public, anon, authenticated;
grant execute on function tests.stage_version_files(uuid, int) to authenticated;


-- A submitted bid (version 1) on an already published solicitation, inserted directly: bids, bid_versions v1
-- (submitted two hours before the bid due time, legal name from the org) and, for an electronic choice, a storage
-- object plus a bid_bond bid_version_files row. Originals: a signed_form log row (p_signed_original) and a paper
-- bid_bond log row (p_bond_original), each received and logged an hour before the bid due time. logged_by is the
-- bidder: a fixture shortcut (the real log is written by office staff through log_bid_original).
-- Call it after the solicitation's due time is set: the times are read from the solicitation row.
create or replace function tests.make_closed_bid(
  p_sol uuid, p_bidder uuid, p_items bigint[], p_alts bigint[] default '{}',
  p_choice public.bid_bond_choice default null, p_apprentice boolean default null,
  p_signed_original boolean default true, p_bond_original boolean default false)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_due  timestamptz := (select s.bid_due_at from public.solicitations s where s.id = p_sol);
  v_org  uuid := (select p.org_id from public.profiles p where p.user_id = p_bidder);
  v_bid  uuid := gen_random_uuid();
  v_ref  text := app.new_bid_reference();
  v_ver  uuid;
  v_path text;
  v_obj  uuid;
begin
  insert into public.bids (id, solicitation_id, bidder_org_id, reference, created_by)
  values (v_bid, p_sol, v_org, v_ref, p_bidder);
  insert into public.bid_versions (bid_id, version, submitted_at, submitted_by, item_cents, alternate_cents,
                                   bid_bond_choice, apprentice_commitment, bidder_legal_name)
  select v_bid, 1, v_due - interval '2 hours', p_bidder, p_items, coalesce(p_alts, '{}'), p_choice, p_apprentice, o.name
    from public.organizations o where o.id = v_org
  returning id into v_ver;
  if p_choice = 'electronic' then
    v_path := 'bids/' || v_bid || '/' || gen_random_uuid() || '/bond.pdf';
    insert into storage.objects (bucket_id, name, metadata)
    values ('bid-files', v_path, jsonb_build_object('eTag', '"fixture-bond"', 'size', 1024, 'mimetype', 'application/pdf'))
    returning id into v_obj;
    insert into public.bid_version_files (version_id, slot, path, file_name, object_id, object_size, object_etag)
    values (v_ver, 'bid_bond', v_path, 'bond.pdf', v_obj, 1024, '"fixture-bond"');
  end if;
  if p_signed_original then
    insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
    values (p_sol, v_bid, v_ref, 1, 'signed_form', v_due - interval '1 hour', p_bidder, v_due - interval '1 hour');
  end if;
  if p_bond_original then
    insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
    values (p_sol, v_bid, v_ref, 1, 'bid_bond', v_due - interval '1 hour', p_bidder, v_due - interval '1 hour');
  end if;
  return v_bid;
end;
$$;

revoke all on function tests.make_closed_bid(uuid, uuid, bigint[], bigint[], public.bid_bond_choice, boolean, boolean, boolean)
  from public, anon, authenticated;

select plan(3);
select has_function('tests', 'make_user', array['text', 'uuid', 'boolean'], 'tests.make_user exists');
select has_function('tests', 'act_as', array['uuid'], 'tests.act_as exists');
select has_function('tests', 'solicitation_data', array['jsonb'], 'tests.solicitation_data exists');
select * from finish();
