-- Bidder registration, bidder-aware helpers and the agency-only policies.
begin;

select plan(36);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000007f1', 'RG Office',   'office'),
  ('00000000-0000-0000-0000-0000000007a1', 'RG Agency A', 'agency');

select tests.make_user('rg.author@test.test', '00000000-0000-0000-0000-0000000007a1') as author \gset
select tests.make_user('rg.office@test.test', '00000000-0000-0000-0000-0000000007f1') as office_u \gset
select tests.make_bidder('rg.bidder.a@test.test', 'RG Bidder A') as bidder_a \gset
select tests.make_bidder('rg.bidder.b@test.test', 'RG Bidder B') as bidder_b \gset
select tests.make_auth_user('rg.new@test.test') as newbie \gset
select tests.make_auth_user('rg.invited@test.test', true) as invited \gset
select tests.make_auth_user('rg.new2@test.test') as newbie2 \gset

insert into public.solicitations (id, agency_id, created_by, data)
values ('00000000-0000-0000-0000-0000000007c1', '00000000-0000-0000-0000-0000000007a1', :'author',
        tests.solicitation_data(jsonb_build_object('title', 'RG draft')));

-- Registration
select tests.act_as(:'newbie');
select lives_ok($$select public.register_bidder('Quarry Peak Builders LLC', '12 Quarry Rd, Calder City', 'Ana Ridge', '555-0142', 'ana@quarrypeak.example.test', true, 'CR-0042')$$,
  'an unregistered user registers');
select is((select o.kind::text from public.organizations o where o.name = 'Quarry Peak Builders LLC'), 'bidder',
  'the new organization is a bidder');
select is((select p.is_admin from public.profiles p where p.user_id = :'newbie'), false, 'the profile is not admin');
select is((select p.org_id from public.profiles p where p.user_id = :'newbie'),
  (select o.id from public.organizations o where o.name = 'Quarry Peak Builders LLC'), 'the profile points at the new org');
select is((select p.display_name from public.profiles p where p.user_id = :'newbie'), 'Ana Ridge', 'display name is the contact name');
select is((select c.resident_certificate from public.bidder_companies c where c.org_id = app.my_org()), 'CR-0042',
  'the company row stores the certificate');
select throws_ok($$select public.register_bidder('Another Name LLC', 'a', 'b', 'c', 'd', false, null)$$,
  'P0001', 'already_registered', 'a second registration is refused');

select tests.act_as(:'author');
select throws_ok($$select public.register_bidder('Agency Sneak LLC', 'a', 'b', 'c', 'd', false, null)$$,
  'P0001', 'already_registered', 'an agency user cannot register');

select tests.act_as(:'invited');
select throws_ok($$select public.register_bidder('Invited Co', 'a', 'b', 'c', 'd', false, null)$$,
  'P0001', 'not_authorized', 'an invited user cannot register');

select tests.act_as_anon();
select throws_ok($$select public.register_bidder('Anon Co', 'a', 'b', 'c', 'd', false, null)$$,
  '42501', null, 'anon cannot call register_bidder');

select tests.act_as(:'newbie2');
select throws_ok($$select public.register_bidder('  ', 'a', 'b', 'c', 'd', false, null)$$,
  'P0001', 'invalid_data', 'a blank legal name is refused');
select throws_ok($$select public.register_bidder('Claim Co', 'a', 'b', 'c', 'd', true, null)$$,
  'P0001', 'invalid_data', 'a residency claim without a certificate is refused');
select throws_ok($$select public.register_bidder('Claim Co', 'a', 'b', 'c', 'd', true, '  ')$$,
  'P0001', 'invalid_data', 'a residency claim with a blank certificate is refused');
select throws_ok($$select public.register_bidder('Cert Co', 'a', 'b', 'c', 'd', false, 'CR-1')$$,
  'P0001', 'invalid_data', 'a certificate without a claim is refused');
select throws_ok($$select public.register_bidder('RG Bidder A', 'a', 'b', 'c', 'd', false, null)$$,
  'P0001', 'name_taken', 'a taken legal name is refused');
select is((select count(*)::int from public.profiles where user_id = :'newbie2'), 0, 'failed registrations leave no profile');

-- A bidder cannot act as an agency
select tests.act_as(:'bidder_a');
select throws_ok(format($$insert into public.solicitations (agency_id, created_by, data) values (%L, %L, '{}')$$,
  (select app.my_org()), :'bidder_a'), '42501', null, 'a bidder cannot insert a draft for its own org');
select is((select count(*)::int from public.solicitations where state = 'draft'), 0, 'a bidder sees no agency drafts');
select throws_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000007c1')$$,
  'P0001', 'not_authorized', 'a bidder cannot submit an agency draft');
select is((select app.is_agency()), false, 'is_agency is false for a bidder');
select is((select app.is_bidder()), true, 'is_bidder is true for a bidder');
select is((select app.my_org_kind()::text), 'bidder', 'my_org_kind is bidder for a bidder');

select tests.act_as(:'author');
select is((select app.is_agency()), true, 'is_agency is true for an agency author');
select is((select app.is_bidder()), false, 'is_bidder is false for an agency author');
with u as (update public.solicitations set data = data || '{"x":1}' where id = '00000000-0000-0000-0000-0000000007c1' returning 1)
select is((select count(*)::int from u), 1,
  'an agency author can still update its draft');
select cmp_ok((select count(*)::int from public.profiles where org_id = '00000000-0000-0000-0000-0000000007f1'), '>=', 1,
  'an agency author still sees office profiles');
select tests.act_as(:'bidder_a');
select is((select count(*)::int from public.profiles where org_id = '00000000-0000-0000-0000-0000000007f1'), 0,
  'a bidder sees no office profiles');
select tests.act_as(:'newbie2');
select is((select count(*)::int from public.profiles where org_id = '00000000-0000-0000-0000-0000000007f1'), 0,
  'an account with no profile sees no office profiles');
select tests.act_as(:'author');

-- Organizations are not a public list of bidders
select tests.act_as_anon();
select is((select count(*)::int from public.organizations where kind = 'bidder'), 0, 'anon sees no bidder orgs');
select is((select count(*)::int from public.organizations where name in ('RG Office', 'RG Agency A')), 2,
  'anon sees office and agency orgs');

select tests.act_as(:'bidder_a');
select is((select count(*)::int from public.organizations where name in ('RG Bidder A', 'RG Bidder B')), 1,
  'bidder A sees only its own org among bidders');

select tests.act_as(:'office_u');
select is((select count(*)::int from public.organizations where name in ('RG Bidder A', 'RG Bidder B')), 2,
  'the office sees both bidder orgs');

-- bidder_companies
select tests.act_as(:'bidder_a');
select is((select count(*)::int from public.bidder_companies), 1, 'bidder A sees only its own company row');
select tests.act_as(:'office_u');
select cmp_ok((select count(*)::int from public.bidder_companies), '>=', 3, 'the office sees every company row');
select tests.act_as(:'author');
select is((select count(*)::int from public.bidder_companies), 0, 'agency users see no company rows');
select tests.act_as_anon();
select throws_ok($$select count(*) from public.bidder_companies$$, '42501', null, 'anon cannot read company rows');

select * from finish();
rollback;
