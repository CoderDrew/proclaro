-- Bidder-organization membership guard and admin org policies (slice 2a final review, C1).
begin;

select plan(25);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000df1', 'GD Office', 'office'),
  ('00000000-0000-0000-0000-000000000da1', 'GD Agency', 'agency');
\set office '00000000-0000-0000-0000-000000000df1'
\set agency '00000000-0000-0000-0000-000000000da1'
select tests.make_user('gd.offadmin@test.test', :'office', true) as office_admin \gset
select tests.make_user('gd.agadmin@test.test', :'agency', true) as agency_admin \gset
select tests.make_user('gd.staff@test.test', :'office') as staff \gset
select tests.make_bidder('gd.bidder@test.test', 'GD Bidder LLC') as bidder \gset
select p.org_id as bidder_org from public.profiles p where p.user_id = :'bidder' \gset
select tests.make_auth_user('gd.new1@test.test') as new1 \gset
select tests.make_auth_user('gd.new2@test.test') as new2 \gset
select tests.make_auth_user('gd.selfsign@test.test') as selfsign \gset

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_trigger('public', 'profiles', 'profiles_bidder_org_guard', 'profiles has the bidder-org guard trigger');
select is(
  (select count(*)::int from pg_proc p
    where p.oid = 'app.guard_bidder_profile()'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')),
  1, 'app.guard_bidder_profile: definer, empty search_path, executable by no API role');
select is((select tgtype::int & 2 <> 0 from pg_trigger where tgname = 'profiles_bidder_org_guard'), true,
  'the guard fires BEFORE');

-- ---------------------------------------------------------------------------
-- service_role (the admin invite path's client): refused into a bidder org, allowed elsewhere
-- ---------------------------------------------------------------------------
select tests.act_as_service_role();
select throws_ok(
  format('insert into public.profiles (user_id, org_id, display_name) values (%L, %L, %L)', :'new1', :'bidder_org', 'Mole'),
  'P0001', 'not_authorized', 'service_role: a profile insert into a bidder org raises not_authorized');
select throws_ok(
  format('update public.profiles set org_id = %L where user_id = %L', :'bidder_org', :'staff'),
  'P0001', 'not_authorized', 'service_role: moving a profile into a bidder org raises not_authorized');
select set_config('app.registering', '00000000-0000-0000-0000-000000000000', true);
select throws_ok(
  format('insert into public.profiles (user_id, org_id, display_name) values (%L, %L, %L)', :'new1', :'bidder_org', 'Mole'),
  'P0001', 'not_authorized', 'a registering flag naming another org does not open a bidder org');
select set_config('app.registering', '', true);
select lives_ok(
  format('insert into public.profiles (user_id, org_id, display_name) values (%L, %L, %L)', :'new2', :'office', 'Office New'),
  'service_role: a profile insert into an office org still works (the invite flow)');
select lives_ok(
  format('update public.profiles set display_name = %L where user_id = %L', 'Renamed Bidder User', :'bidder'),
  'service_role: an update that leaves a bidder profile''s org alone is not blocked');
reset role;
select is((select org_id from public.profiles where user_id = :'staff'), :'office'::uuid, 'the refused move changed nothing');
select is((select count(*)::int from public.profiles where user_id = :'new1'), 0, 'the refused insert created no profile');

-- The database owner (and so any definer function) is held to the same rule.
select throws_ok(
  format('insert into public.profiles (user_id, org_id, display_name) values (%L, %L, %L)', :'new1', :'bidder_org', 'Mole'),
  'P0001', 'not_authorized', 'owner without the flag: a profile insert into a bidder org raises not_authorized');

-- ---------------------------------------------------------------------------
-- Office admin (authenticated): no profile writes at all, and no bidder orgs
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_admin');
select throws_ok(
  format('insert into public.profiles (user_id, org_id, display_name) values (%L, %L, %L)', :'new1', :'bidder_org', 'Mole'),
  '42501', null, 'office admin: a profile insert into a bidder org raises');
select throws_ok(
  format('update public.profiles set org_id = %L where user_id = %L', :'bidder_org', :'office_admin'),
  '42501', null, 'office admin: moving own profile into a bidder org raises');
select throws_ok(
  format('insert into public.organizations (name, kind) values (%L, %L)', 'GD Shell Bidder', 'bidder'),
  '42501', null, 'office admin: creating a bidder org raises');
select lives_ok(
  format('insert into public.organizations (name, kind) values (%L, %L)', 'GD New Agency', 'agency'),
  'office admin: creating an agency still works');
select results_eq(
  format('with u as (update public.organizations set name = %L where id = %L returning 1) select count(*)::int from u',
         'GD Bidder Renamed', :'bidder_org'),
  'values (0)', 'office admin: renaming a bidder org updates no row');
select results_eq(
  format('with u as (update public.organizations set name = %L where id = %L returning 1) select count(*)::int from u',
         'GD Agency Renamed', :'agency'),
  'values (1)', 'office admin: renaming an agency still works');
select throws_ok(
  format('update public.organizations set name = %L, kind = %L where id = %L', 'GD Agency Renamed', 'bidder', :'agency'),
  '42501', null, 'office admin: an agency cannot be turned into a bidder org (kind is not updatable)');
select tests.act_as(:'agency_admin');
select throws_ok(
  format('insert into public.organizations (name, kind) values (%L, %L)', 'GD Shell Bidder 2', 'bidder'),
  '42501', null, 'agency admin: creating a bidder org raises');
reset role;
select is((select name from public.organizations where id = :'bidder_org'), 'GD Bidder LLC', 'the bidder org name is unchanged');
select is((select count(*)::int from public.organizations where name like 'GD Shell Bidder%'), 0, 'no bidder org was created');

-- ---------------------------------------------------------------------------
-- register_bidder still works, and leaves no flag behind
-- ---------------------------------------------------------------------------
select tests.act_as(:'selfsign');
select public.register_bidder('GD Self Signed Co', '5 Test Way', 'Sam Self', '555-0105', 'gd.selfsign@test.test',
                              false, null) as self_org \gset
select is((select org_id from public.profiles where user_id = :'selfsign'), :'self_org'::uuid,
  'register_bidder creates the profile in the new bidder org');
select is((select kind::text from public.organizations where id = :'self_org'), 'bidder', 'and the org is a bidder org');
select is(coalesce(current_setting('app.registering', true), ''), '', 'register_bidder clears the registering flag');
reset role;
select tests.act_as_service_role();
select throws_ok(
  format('insert into public.profiles (user_id, org_id, display_name) values (%L, %L, %L)', :'new1', :'self_org', 'Mole'),
  'P0001', 'not_authorized', 'after registration, the same transaction cannot add a second profile to that org');
reset role;

select * from finish();
rollback;
