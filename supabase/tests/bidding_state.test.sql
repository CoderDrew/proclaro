-- public.bidding_state: the database's answer for the bidder UI (slice 2a, Task 7).
begin;

select plan(11);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000bf1', 'BS Office', 'office'),
  ('00000000-0000-0000-0000-000000000ba1', 'BS Agency', 'agency');
select tests.make_user('bs.author@test.test', '00000000-0000-0000-0000-000000000ba1') as author \gset
select tests.make_user('bs.office@test.test', '00000000-0000-0000-0000-000000000bf1') as office_u \gset
select tests.make_bidder('bs.bidder@test.test', 'BS Bidder') as bidder \gset

\set agency '00000000-0000-0000-0000-000000000ba1'
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol_open \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol_before \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol_at \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol_unreleased \gset
alter table public.solicitations disable trigger solicitations_published_frozen;
update public.solicitations set release_date = app.today() + 1 where id = :'sol_unreleased';
alter table public.solicitations enable trigger solicitations_published_frozen;
insert into public.solicitations (agency_id, created_by, data)
values (:'agency', :'author', tests.solicitation_data()) returning id as sol_draft \gset
select tests.set_bid_due(:'sol_before', now() + interval '1 second');
select tests.set_bid_due(:'sol_at', now());

select has_function('public', 'bidding_state', array['uuid'], 'public.bidding_state exists');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = 'bidding_state'
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')),
  1, 'bidding_state is security definer, empty search_path, execute for authenticated only');

select tests.act_as(:'bidder');
select is(public.bidding_state(:'sol_open'), 'open', 'a published, released solicitation before its due time is open');
select is(public.bidding_state(:'sol_before'), 'open', 'one second before the due time is open');
select is(public.bidding_state(:'sol_at'), 'closed', 'exactly at the due time is closed');
select is(public.bidding_state(:'sol_unreleased'), 'not_open', 'unreleased is not_open');
select is(public.bidding_state(:'sol_draft'), 'not_open', 'unpublished is not_open');
select is(public.bidding_state('00000000-0000-0000-0000-00000000dead'), 'not_open', 'an unknown id is not_open');
reset role;

select tests.act_as(:'office_u');
select throws_ok(format('select public.bidding_state(%L)', :'sol_open'), 'P0001', 'not_authorized', 'office is not authorized');
reset role;
select tests.act_as_anon();
select throws_ok(format('select public.bidding_state(%L)', :'sol_open'), '42501', null, 'anon cannot execute it');
reset role;
select tests.act_as_service_role();
select throws_ok(format('select public.bidding_state(%L)', :'sol_open'), '42501', null, 'service_role cannot execute it');
reset role;

select * from finish();
rollback;
