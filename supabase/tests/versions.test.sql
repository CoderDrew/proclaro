-- 0026: version history. solicitation_versions (append-only, v1 written by publish_solicitation and backfilled),
-- solicitation_funding_changes (append-only, preferred by app.funding_cents), app.last_schedule_change,
-- public.solicitation_version_list, and the narrow freeze exception in app.reject_published_change for
-- publish_addendum (setting app.publishing_addendum = the solicitation id; only the current pointer columns move).
begin;

select plan(56);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000261', 'VH Office',   'office'),
  ('00000000-0000-0000-0000-000000000262', 'VH Agency A', 'agency'),
  ('00000000-0000-0000-0000-000000000265', 'VH Agency B', 'agency');

select tests.make_user('vh.author@test.test', '00000000-0000-0000-0000-000000000262') as author \gset
select tests.make_user('vh.other@test.test',  '00000000-0000-0000-0000-000000000265') as other_agency \gset
select tests.make_user('vh.r1@test.test',     '00000000-0000-0000-0000-000000000261') as r1 \gset
select tests.make_user('vh.r2@test.test',     '00000000-0000-0000-0000-000000000261') as r2 \gset
select tests.make_bidder('vh.bidder@test.test', 'VH Bidder') as bidder \gset

\set v1 '00000000-0000-0000-0000-000000000263'
\set dr '00000000-0000-0000-0000-000000000264'

-- ===========================================================================
-- Schema objects
-- ===========================================================================
select has_table('public', 'solicitation_versions', 'solicitation_versions exists');
select col_is_pk('public', 'solicitation_versions', array['solicitation_id', 'version'],
  'solicitation_versions is keyed by (solicitation_id, version)');
select has_table('public', 'solicitation_funding_changes', 'solicitation_funding_changes exists');
select col_is_pk('public', 'solicitation_funding_changes', array['solicitation_id', 'version'],
  'solicitation_funding_changes is keyed by (solicitation_id, version)');
select has_function('app', 'last_schedule_change', array['uuid'], 'app.last_schedule_change(uuid) exists');
select has_function('public', 'solicitation_version_list', array['uuid'],
  'public.solicitation_version_list(uuid) exists');

-- ===========================================================================
-- Backfill: the seeded, already-published 27-0003 has exactly its version 1
-- ===========================================================================
select is((select count(*)::int from public.solicitation_versions v
             join public.solicitations s on s.id = v.solicitation_id where s.number = '27-0003'), 1,
  'seeded 27-0003 has exactly one version row');
select is((select row(v.version, v.rfb_path, v.bid_form_path, v.bid_due_at, v.addendum_path is null,
                      v.schedule_changed, v.published_by is null, v.snapshot = s.published_snapshot)::text
             from public.solicitation_versions v join public.solicitations s on s.id = v.solicitation_id
            where s.number = '27-0003'),
          (select row(1, s.rfb_path, s.bid_form_path, s.bid_due_at, true, false, true, true)::text
             from public.solicitations s where s.number = '27-0003'),
  'the backfilled version 1 copies the current columns, with no addendum and no publisher');

-- ===========================================================================
-- publish_solicitation writes version 1. v1: released today. dr: stays a draft.
-- ===========================================================================
insert into public.solicitations (id, agency_id, created_by, data) values
  (:'v1', '00000000-0000-0000-0000-000000000262', :'author',
   tests.solicitation_data(jsonb_build_object('shortTitle', 'Versioned', 'fundingAmountCents', 16000000,
     'releaseDate', to_char(app.today(), 'YYYY-MM-DD'), 'adStart', to_char(app.today(), 'YYYY-MM-DD')))),
  (:'dr', '00000000-0000-0000-0000-000000000262', :'author',
   tests.solicitation_data(jsonb_build_object('shortTitle', 'Draft')));

select tests.act_as(:'author');
select public.submit_solicitation(:'v1');
select tests.act_as(:'r1');
select public.start_review(:'v1');
select public.send_to_check(:'v1');
select tests.act_as(:'r2');
select public.approve_check(:'v1');

reset role;
select tests.bid_due_at(data) as due1 from public.solicitations where id = :'v1' \gset
select jsonb_build_object('data', data - 'fundingAmountCents', 'clauses', '{}'::jsonb) as snap1
  from public.solicitations where id = :'v1' \gset

select is((select count(*)::int from public.solicitation_versions where solicitation_id = :'v1'), 0,
  'before publish: no version rows');

select tests.act_as(:'r1');
select lives_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000263/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000263/v1/bid-form.pdf', %L, %L, 16000000)$$,
    :'v1', :'snap1', :'due1'),
  'publish succeeds');

reset role;
select is((select count(*)::int from public.solicitation_versions where solicitation_id = :'v1'), 1,
  'publish creates exactly one version row');
select is((select version from public.solicitation_versions where solicitation_id = :'v1'), 1, 'it is version 1');
select ok((select addendum_path is null from public.solicitation_versions where solicitation_id = :'v1'),
  'version 1 has no addendum path');
select ok((select not schedule_changed from public.solicitation_versions where solicitation_id = :'v1'),
  'version 1 does not change the schedule');
select is((select published_by from public.solicitation_versions where solicitation_id = :'v1'), :'r1'::uuid,
  'published_by is the publisher');
select is((select row(v.snapshot, v.rfb_path, v.bid_form_path, v.bid_due_at, v.published_at)::text
             from public.solicitation_versions v where v.solicitation_id = :'v1'),
          (select row(s.published_snapshot, s.rfb_path, s.bid_form_path, s.bid_due_at, s.published_at)::text
             from public.solicitations s where s.id = :'v1'),
  'version 1 matches the published pointer columns');

-- A version row must not carry the funding amount (the snapshot is public) and has an addendum iff version > 1.
select throws_ok(format($$insert into public.solicitation_versions
    (solicitation_id, version, snapshot, rfb_path, bid_form_path, addendum_path, bid_due_at)
    values (%L, 2, '{"data": {"fundingAmountCents": 1}}', 'r', 'b', 'a', now())$$, :'v1'),
  '23514', null, 'a version snapshot carrying the funding amount is refused');
select throws_ok(format($$insert into public.solicitation_versions
    (solicitation_id, version, snapshot, rfb_path, bid_form_path, addendum_path, bid_due_at)
    values (%L, 2, '{}', 'r', 'b', null, now())$$, :'v1'),
  '23514', null, 'a version after 1 without an addendum path is refused');

-- ===========================================================================
-- Append-only: as office (no grant) and as postgres (trigger)
-- ===========================================================================
select tests.act_as(:'r1');
select throws_ok(format($$update public.solicitation_versions set schedule_changed = true where solicitation_id = %L$$, :'v1'),
  '42501', null, 'office cannot update a version row');
select throws_ok(format($$delete from public.solicitation_versions where solicitation_id = %L$$, :'v1'),
  '42501', null, 'office cannot delete a version row');
reset role;
select throws_ok(format($$update public.solicitation_versions set schedule_changed = true where solicitation_id = %L$$, :'v1'),
  'P0001', 'solicitation_versions is append-only: UPDATE is not allowed', 'postgres cannot update a version row');
select throws_ok(format($$delete from public.solicitation_versions where solicitation_id = %L$$, :'v1'),
  'P0001', 'solicitation_versions is append-only: DELETE is not allowed', 'postgres cannot delete a version row');
select throws_ok('truncate public.solicitation_versions cascade',
  'P0001', null, 'postgres cannot truncate solicitation_versions');

-- ===========================================================================
-- Visibility: solicitation_versions RLS and public.solicitation_version_list
-- A version row on the draft is inserted directly (it can't happen through the API) to prove it stays hidden.
-- ===========================================================================
insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path, bid_due_at)
values (:'dr', 1, '{"data": {}}', 'solicitations/x/v1/rfb.pdf', 'solicitations/x/v1/bid-form.pdf', now());

select tests.act_as_anon();
select is((select count(*)::int from public.solicitation_versions where solicitation_id = :'v1'), 1,
  'anon sees the released published solicitation''s version');
select is((select count(*)::int from public.solicitation_versions where solicitation_id = :'dr'), 0,
  'anon sees none of a draft''s versions');
select results_eq(format($$select version, rfb_path, bid_form_path, addendum_path, is_current
                          from public.solicitation_version_list(%L)$$, :'v1'),
  $$values (1, 'solicitations/00000000-0000-0000-0000-000000000263/v1/rfb.pdf',
            'solicitations/00000000-0000-0000-0000-000000000263/v1/bid-form.pdf', null::text, true)$$,
  'anon lists the released solicitation''s versions, version 1 current');
select is((select count(*)::int from public.solicitation_version_list(:'dr')), 0,
  'anon lists none of a draft''s versions');

select tests.act_as(:'bidder');
select is((select count(*)::int from public.solicitation_versions where solicitation_id = :'dr'), 0,
  'a bidder sees none of a draft''s versions');
select is((select count(*)::int from public.solicitation_version_list(:'v1')), 1,
  'a bidder lists the released solicitation''s versions');

select tests.act_as(:'author');
select is((select count(*)::int from public.solicitation_versions where solicitation_id = :'dr'), 1,
  'the owning agency sees its draft''s version rows');
select is((select count(*)::int from public.solicitation_version_list(:'dr')), 1,
  'the owning agency lists its draft''s versions');

select tests.act_as(:'other_agency');
select is((select count(*)::int from public.solicitation_version_list(:'dr')), 0,
  'another agency lists none of the draft''s versions');

-- ===========================================================================
-- The freeze: a published row is read-only, except the pointer columns during publish_addendum
-- ===========================================================================
reset role;
select throws_ok(format($$update public.solicitations set bid_due_at = bid_due_at + interval '1 day' where id = %L$$, :'v1'),
  'P0001', format('solicitation %s is published and read-only', :'v1'),
  'without the setting, a published row''s bid_due_at cannot change');

select set_config('app.publishing_addendum', :'v1', true);
select lives_ok(format($$update public.solicitations
    set bid_due_at = bid_due_at + interval '1 day', version = 2,
        published_snapshot = published_snapshot || '{"addendum": 1}',
        data = data || '{"summary": "Changed."}',
        rfb_path = 'solicitations/00000000-0000-0000-0000-000000000263/v2/rfb.pdf',
        bid_form_path = 'solicitations/00000000-0000-0000-0000-000000000263/v2/bid-form.pdf'
  where id = %L$$, :'v1'),
  'with the setting, the pointer columns can move');
select is((select row(version, bid_due_at, data ->> 'summary')::text from public.solicitations where id = :'v1'),
          row(2, :'due1'::timestamptz + interval '1 day', 'Changed.')::text,
  'the pointer update took effect');
select throws_ok(format($$update public.solicitations set state = 'approved' where id = %L$$, :'v1'),
  'P0001', format('solicitation %s is published and read-only', :'v1'), 'with the setting, state cannot change');
select throws_ok(format($$update public.solicitations set number = 'XX-9999' where id = %L$$, :'v1'),
  'P0001', format('solicitation %s is published and read-only', :'v1'), 'with the setting, number cannot change');
select throws_ok(format($$update public.solicitations set version = 3, release_date = release_date + 1 where id = %L$$, :'v1'),
  'P0001', format('solicitation %s is published and read-only', :'v1'),
  'with the setting, a pointer change bundled with release_date is refused');
select throws_ok(format($$delete from public.solicitations where id = %L$$, :'v1'),
  'P0001', format('solicitation %s is published and read-only', :'v1'), 'with the setting, delete is still refused');

select set_config('app.publishing_addendum', '00000000-0000-0000-0000-000000000264', true);
select throws_ok(format($$update public.solicitations set bid_due_at = bid_due_at + interval '2 days' where id = %L$$, :'v1'),
  'P0001', format('solicitation %s is published and read-only', :'v1'),
  'with the setting for a different id, the update is refused');
select set_config('app.publishing_addendum', '', true);

-- ===========================================================================
-- Funding changes and app.funding_cents
-- ===========================================================================
select is(app.funding_cents(:'v1'), 16000000::bigint, 'funding_cents is the solicitation_funding value');

insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path,
                                          addendum_path, bid_due_at)
values (:'v1', 2, '{"data": {}}', 'solicitations/00000000-0000-0000-0000-000000000263/v2/rfb.pdf',
        'solicitations/00000000-0000-0000-0000-000000000263/v2/bid-form.pdf',
        'solicitations/00000000-0000-0000-0000-000000000263/v2/addendum.pdf', now() + interval '30 days');
insert into public.solicitation_funding_changes (solicitation_id, version, funding_cents) values (:'v1', 2, 17000000);
select is(app.funding_cents(:'v1'), 17000000::bigint, 'after a version-2 funding change, funding_cents is the change');

-- A legacy row (published before slice 2b: no solicitation_funding row) whose addendum records a funding change.
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000262', :'author', now() + interval '30 days',
  '{"estimateCents": 15000000, "fundingAmountCents": null}') as legacy \gset
insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path, addendum_path,
                                          bid_due_at)
values (:'legacy', 1, '{"data": {}}', 'r1', 'b1', null, now() + interval '30 days'),
       (:'legacy', 2, '{"data": {}}', 'r2', 'b2', 'a2', now() + interval '30 days');
select ok(app.funding_from_estimate(:'legacy'), 'a legacy row with no funding change is from the estimate');
insert into public.solicitation_funding_changes (solicitation_id, version, funding_cents) values (:'legacy', 2, 14000000);
select is(app.funding_cents(:'legacy'), 14000000::bigint, 'a legacy row''s funding change is its funding amount');
select ok(not app.funding_from_estimate(:'legacy'), 'a legacy row with a funding change is not from the estimate');
select ok(not app.funding_from_estimate(:'v1'), 'a frozen amount plus a change is not from the estimate');

select throws_ok(format($$insert into public.solicitation_funding_changes (solicitation_id, version, funding_cents)
    values (%L, 9, 1)$$, :'v1'),
  '23503', null, 'a funding change needs its version row');
select throws_ok(format($$insert into public.solicitation_funding_changes (solicitation_id, version, funding_cents)
    values (%L, 1, 1)$$, :'v1'),
  '23514', null, 'version 1''s funding lives in solicitation_funding, not in a change');
select throws_ok(format($$update public.solicitation_funding_changes set funding_cents = 1 where solicitation_id = %L$$, :'v1'),
  'P0001', 'solicitation_funding_changes is append-only: UPDATE is not allowed', 'funding changes cannot be updated');
select throws_ok(format($$delete from public.solicitation_funding_changes where solicitation_id = %L$$, :'v1'),
  'P0001', 'solicitation_funding_changes is append-only: DELETE is not allowed', 'funding changes cannot be deleted');

-- Read policy: as solicitation_funding (owning agency and office; bidders 0 rows; anon no grant).
select tests.act_as(:'author');
select is((select count(*)::int from public.solicitation_funding_changes where solicitation_id = :'v1'), 1,
  'the owning agency reads the funding change');
select tests.act_as(:'r2');
select is((select count(*)::int from public.solicitation_funding_changes where solicitation_id = :'v1'), 1,
  'office staff read the funding change');
select tests.act_as(:'bidder');
select is((select count(*)::int from public.solicitation_funding_changes where solicitation_id = :'v1'), 0,
  'a bidder reads 0 funding changes');
select tests.act_as_anon();
select throws_ok(format($$select count(*) from public.solicitation_funding_changes where solicitation_id = %L$$, :'v1'),
  '42501', null, 'anon cannot read funding changes at all');

-- ===========================================================================
-- app.last_schedule_change
-- ===========================================================================
reset role;
select is(app.last_schedule_change(:'v1'), 1, 'with no schedule-changing version, last_schedule_change is 1');
insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path,
                                          addendum_path, bid_due_at, schedule_changed)
values (:'v1', 3, '{"data": {}}', 'solicitations/00000000-0000-0000-0000-000000000263/v3/rfb.pdf',
        'solicitations/00000000-0000-0000-0000-000000000263/v3/bid-form.pdf',
        'solicitations/00000000-0000-0000-0000-000000000263/v3/addendum.pdf', now() + interval '30 days', true);
select is(app.last_schedule_change(:'v1'), 3, 'after a version-3 schedule change, last_schedule_change is 3');

select * from finish();
rollback;
