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
    'estimateCents', 15000000, 'fundingSource', 'capital_construction', 'fundingOther', '', 'federalFunds', false,
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

select plan(3);
select has_function('tests', 'make_user', array['text', 'uuid', 'boolean'], 'tests.make_user exists');
select has_function('tests', 'act_as', array['uuid'], 'tests.act_as exists');
select has_function('tests', 'solicitation_data', array['jsonb'], 'tests.solicitation_data exists');
select * from finish();
