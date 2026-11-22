-- 0033: public.solicitation_addenda, the staff list of a solicitation's addenda with the effective state
-- (app.addendum_effective_state is not callable by API roles). Owning agency or office only.
begin;

select plan(16);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000331', 'SA Office',   'office'),
  ('00000000-0000-0000-0000-000000000332', 'SA Agency A', 'agency'),
  ('00000000-0000-0000-0000-000000000333', 'SA Agency B', 'agency');

select tests.make_user('sa.author@test.test', '00000000-0000-0000-0000-000000000332') as author \gset
select tests.make_user('sa.other@test.test',  '00000000-0000-0000-0000-000000000333') as other_agency \gset
select tests.make_user('sa.r1@test.test',     '00000000-0000-0000-0000-000000000331') as r1 \gset
select tests.make_bidder('sa.bidder@test.test', 'SA Bidder') as bidder \gset

-- s1: open for bids. s2: closed.
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000332', :'author',
  now() + interval '20 days') as s1 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000332', :'author',
  now() - interval '1 hour') as s2 \gset

-- s1: a withdrawn Addendum 1, the published Addendum 1 that reused its number (version 2), a draft Addendum 2.
insert into public.addenda (id, solicitation_id, number, state, data, created_by, created_at, withdrawn_reason)
values ('00000000-0000-0000-0000-0000000033a1', :'s1', 1, 'withdrawn', '{}'::jsonb, :'author',
        now() - interval '3 hours', 'Wrong date');
insert into public.addenda (id, solicitation_id, number, state, data, created_by, created_at, published_version)
values ('00000000-0000-0000-0000-0000000033a2', :'s1', 1, 'published', '{}'::jsonb, :'author',
        now() - interval '2 hours', 2);
insert into public.addenda (id, solicitation_id, number, state, data, created_by, created_at)
values ('00000000-0000-0000-0000-0000000033a3', :'s1', 2, 'draft', '{}'::jsonb, :'author', now() - interval '1 hour');
insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path, addendum_path,
                                          bid_due_at, published_at)
values (:'s1', 2, '{}'::jsonb, 'r', 'b', 'a', now() + interval '20 days', '2026-11-02 17:00:00+00');
-- s2 (closed): a submitted addendum that can never be published, so it counts as withdrawn.
insert into public.addenda (id, solicitation_id, number, state, data, created_by)
values ('00000000-0000-0000-0000-0000000033b1', :'s2', 1, 'submitted', '{}'::jsonb, :'author');

-- ===========================================================================
-- Shape and grants
-- ===========================================================================
select has_function('public', 'solicitation_addenda', array['uuid'], 'solicitation_addenda(uuid) exists');
select ok((select p.prosecdef and p.proconfig @> array['search_path=""']
             from pg_proc p where p.oid = 'public.solicitation_addenda(uuid)'::regprocedure),
  'solicitation_addenda is security definer with an empty search_path');
select ok(has_function_privilege('authenticated', 'public.solicitation_addenda(uuid)', 'execute'),
  'authenticated may execute solicitation_addenda');
select ok(not has_function_privilege('anon', 'public.solicitation_addenda(uuid)', 'execute')
      and not has_function_privilege('service_role', 'public.solicitation_addenda(uuid)', 'execute'),
  'anon and service_role may not execute solicitation_addenda');
select ok(not has_function_privilege('public', 'public.solicitation_addenda(uuid)', 'execute'),
  'public may not execute solicitation_addenda');

-- ===========================================================================
-- The owning agency
-- ===========================================================================
select tests.act_as(:'author');
select results_eq(
  format('select id from public.solicitation_addenda(%L)', :'s1'),
  $$values ('00000000-0000-0000-0000-0000000033a1'::uuid), ('00000000-0000-0000-0000-0000000033a2'::uuid),
           ('00000000-0000-0000-0000-0000000033a3'::uuid)$$,
  'the owning agency sees every addendum, ordered by number then created_at');
select results_eq(
  format('select number, state, effective_state from public.solicitation_addenda(%L)', :'s1'),
  $$values (1, 'withdrawn'::public.addendum_state, 'withdrawn'::public.addendum_state),
           (1, 'published'::public.addendum_state, 'published'::public.addendum_state),
           (2, 'draft'::public.addendum_state, 'draft'::public.addendum_state)$$,
  'while bidding is open the effective state is the stored state');
select results_eq(
  format('select published_version, published_at from public.solicitation_addenda(%L) where state = %L',
         :'s1', 'published'),
  $$values (2, '2026-11-02 17:00:00+00'::timestamptz)$$,
  'a published addendum carries its version and the version''s published_at');
select is(
  (select count(*)::int from public.solicitation_addenda(:'s1') where published_at is not null),
  1, 'unpublished addenda have no published_at');
select results_eq(
  format('select state, effective_state from public.solicitation_addenda(%L)', :'s2'),
  $$values ('submitted'::public.addendum_state, 'withdrawn'::public.addendum_state)$$,
  'after close an unpublished addendum shows effective_state withdrawn');

-- ===========================================================================
-- Office staff
-- ===========================================================================
select tests.act_as(:'r1');
select is((select count(*)::int from public.solicitation_addenda(:'s1')), 3, 'office staff see the addenda');

-- ===========================================================================
-- Everyone else
-- ===========================================================================
select tests.act_as(:'other_agency');
select throws_ok(format('select * from public.solicitation_addenda(%L)', :'s1'), 'P0001', 'not_authorized',
  'another agency gets not_authorized');
select tests.act_as(:'bidder');
select throws_ok(format('select * from public.solicitation_addenda(%L)', :'s1'), 'P0001', 'not_authorized',
  'a bidder gets not_authorized');
select tests.act_as(:'author');
select throws_ok(format('select * from public.solicitation_addenda(%L)', gen_random_uuid()), 'P0001',
  'not_authorized', 'an unknown solicitation gets not_authorized');
select tests.act_as_anon();
select throws_ok(format('select * from public.solicitation_addenda(%L)', :'s1'), '42501', null,
  'anon cannot call solicitation_addenda');
reset role;
select is((select count(*)::int from public.addenda where solicitation_id = :'s1'), 3,
  'the fixtures are untouched (read-only function)');

select * from finish();
rollback;
