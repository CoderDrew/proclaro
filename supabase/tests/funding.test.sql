-- 0014: the funding amount. Required data key, frozen at publish into solicitation_funding (agency + office only,
-- Ruling 2: confidential until the recap is posted), never in the public row or snapshot, estimate fallback for rows
-- published before slice 2b.
begin;

select plan(56);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000ff1', 'FA Office',   'office'),
  ('00000000-0000-0000-0000-000000000fa1', 'FA Agency A', 'agency'),
  ('00000000-0000-0000-0000-000000000fa2', 'FA Agency B', 'agency');

select tests.make_user('fa.author@test.test', '00000000-0000-0000-0000-000000000fa1') as author \gset
select tests.make_user('fa.other@test.test',  '00000000-0000-0000-0000-000000000fa2') as other_agency \gset
select tests.make_user('fa.r1@test.test',     '00000000-0000-0000-0000-000000000ff1') as r1 \gset
select tests.make_user('fa.r2@test.test',     '00000000-0000-0000-0000-000000000ff1') as r2 \gset
select tests.make_user('fa.r3@test.test',     '00000000-0000-0000-0000-000000000ff1') as r3 \gset
select tests.make_bidder('fa.bidder@test.test', 'FA Bidder') as bidder \gset

\set fc1 '00000000-0000-0000-0000-000000000fc1'
\set fc2 '00000000-0000-0000-0000-000000000fc2'

-- ===========================================================================
-- Schema objects
-- ===========================================================================
select has_table('public', 'solicitation_funding', 'solicitation_funding exists');
select has_function('app', 'funding_cents', array['uuid'], 'app.funding_cents(uuid) exists');
select has_function('app', 'funding_from_estimate', array['uuid'], 'app.funding_from_estimate(uuid) exists');
select has_function('public', 'publish_solicitation', array['uuid', 'text', 'text', 'jsonb', 'timestamptz', 'bigint'],
  'publish_solicitation takes the funding amount');
select hasnt_function('public', 'publish_solicitation', array['uuid', 'text', 'text', 'jsonb', 'timestamptz'],
  'the five-argument publish_solicitation is gone');
select ok('fundingAmountCents' = any (app.required_data_keys()), 'fundingAmountCents is a required data key');

-- ===========================================================================
-- app.funding_cents / app.funding_from_estimate on directly inserted published rows
-- ===========================================================================
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000fa1', :'author', now() + interval '1 day',
  '{"estimateCents": 15000000, "fundingAmountCents": 16000000}') as p_funded \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000fa1', :'author', now() + interval '1 day',
  '{"estimateCents": 15000000, "fundingAmountCents": null}') as p_legacy \gset

select is(app.funding_cents(:'p_funded'), 16000000::bigint, 'funding_cents is the frozen funding amount');
select ok(not app.funding_from_estimate(:'p_funded'), 'a frozen funding amount is not from the estimate');
select is(app.funding_cents(:'p_legacy'), 15000000::bigint, 'with no funding amount, funding_cents is the estimate');
select ok(app.funding_from_estimate(:'p_legacy'), 'funding_from_estimate is true without a funding amount');
select ok(not jsonb_path_exists((select to_jsonb(s) from public.solicitations s where s.id = :'p_funded'),
                                '$.**.fundingAmountCents'),
  'the helper-published row carries no funding amount in data or snapshot');

-- A published row can never carry the funding amount in its public columns.
select throws_ok(format($$insert into public.solicitations (agency_id, created_by, state, data, release_date, published_at)
    values ('00000000-0000-0000-0000-000000000fa1', %L, 'published', '{"fundingAmountCents": 1}', app.today(), now())$$, :'author'),
  '23514', null, 'a published row with the funding amount in data is refused');
select throws_ok(format($$insert into public.solicitations (agency_id, created_by, state, data, release_date, published_at, published_snapshot)
    values ('00000000-0000-0000-0000-000000000fa1', %L, 'published', '{}', app.today(), now(),
            '{"data": {"nested": {"fundingAmountCents": 1}}}')$$, :'author'),
  '23514', null, 'a published row with the funding amount anywhere in the snapshot is refused');

-- ===========================================================================
-- The slice 1 walk to approved. fc1: funding 16,000,000, released today. fc2: funding null.
-- ===========================================================================
insert into public.solicitations (id, agency_id, created_by, data) values
  (:'fc1', '00000000-0000-0000-0000-000000000fa1', :'author',
   tests.solicitation_data(jsonb_build_object('shortTitle', 'Funded', 'fundingAmountCents', 16000000,
     'releaseDate', to_char(app.today(), 'YYYY-MM-DD'), 'adStart', to_char(app.today(), 'YYYY-MM-DD')))),
  (:'fc2', '00000000-0000-0000-0000-000000000fa1', :'author',
   tests.solicitation_data(jsonb_build_object('shortTitle', 'Unfunded', 'fundingAmountCents', null)));

select tests.act_as(:'author');
select public.submit_solicitation(:'fc1');
select public.submit_solicitation(:'fc2');
select tests.act_as(:'r1');
select public.start_review(:'fc1');
select public.send_to_check(:'fc1');
select public.start_review(:'fc2');
select public.send_to_check(:'fc2');
select tests.act_as(:'r2');
select public.approve_check(:'fc1');
select public.approve_check(:'fc2');

reset role;
select tests.bid_due_at(data) as due1 from public.solicitations where id = :'fc1' \gset
select tests.bid_due_at(data) as due2 from public.solicitations where id = :'fc2' \gset
select jsonb_build_object('data', data - 'fundingAmountCents', 'clauses', '{}'::jsonb) as snap1
  from public.solicitations where id = :'fc1' \gset

-- Before publish: the agency and office read it in data; anon and bidders read nothing.
select tests.act_as(:'author');
select is((select data ->> 'fundingAmountCents' from public.solicitations where id = :'fc1'), '16000000',
  'before publish: the owning agency reads the funding amount');
select tests.act_as(:'r3');
select is((select data ->> 'fundingAmountCents' from public.solicitations where id = :'fc1'), '16000000',
  'before publish: office staff read the funding amount');
select tests.act_as(:'other_agency');
select is((select count(*)::int from public.solicitations where id = :'fc1'), 0,
  'before publish: another agency reads 0 rows');
select tests.act_as(:'bidder');
select is((select count(*)::int from public.solicitations where id = :'fc1'), 0,
  'before publish: a bidder reads 0 solicitation rows');
select is((select count(*)::int from public.solicitation_funding where solicitation_id = :'fc1'), 0,
  'before publish: a bidder reads 0 funding rows');
select tests.act_as_anon();
select is((select count(*)::int from public.solicitations where id = :'fc1'), 0,
  'before publish: anon reads 0 solicitation rows');
select throws_ok(format($$select count(*) from public.solicitation_funding where solicitation_id = %L$$, :'fc1'),
  '42501', null, 'before publish: anon cannot read the funding table at all (0 rows)');

-- ===========================================================================
-- publish_solicitation checks the funding amount
-- ===========================================================================
select tests.act_as(:'r1');
select throws_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/bid-form.pdf', %L, %L, 16000001)$$,
    :'fc1', :'snap1', :'due1'),
  'P0001', 'snapshot_mismatch', 'publish refuses a funding amount that differs from the stored one');
select throws_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/bid-form.pdf', %L, %L, null)$$,
    :'fc1', :'snap1', :'due1'),
  'P0001', 'snapshot_mismatch', 'publish refuses a missing funding amount argument');
select throws_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/bid-form.pdf', %L, %L, 16000000)$$,
    :'fc1', (:'snap1'::jsonb || jsonb_build_object('data', (:'snap1'::jsonb -> 'data') || '{"fundingAmountCents": 16000000}')), :'due1'),
  'P0001', 'snapshot_mismatch', 'publish refuses a snapshot that carries the funding amount');
select throws_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/bid-form.pdf', %L, %L, 16000000)$$,
    :'fc1', (:'snap1'::jsonb || '{"extra": {"fundingAmountCents": 16000000}}'), :'due1'),
  'P0001', 'snapshot_mismatch', 'publish refuses the funding amount anywhere in the snapshot');
select throws_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/bid-form.pdf', '{"k":1}', %L, null)$$,
    :'fc2', :'due2'),
  'P0001', 'invalid_data', 'publish refuses a row whose funding amount is null');
select throws_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/bid-form.pdf', '{"k":1}', %L, 0)$$,
    :'fc2', :'due2'),
  'P0001', 'invalid_data', 'a null stored funding amount is invalid_data whatever the caller sends');

-- A non-integer or negative stored value is invalid_data too (rows are edited directly here, rolled back).
reset role;
update public.solicitations set data = data || '{"fundingAmountCents": -1}' where id = :'fc2';
select tests.act_as(:'r1');
select throws_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/bid-form.pdf', '{"k":1}', %L, -1)$$,
    :'fc2', :'due2'),
  'P0001', 'invalid_data', 'publish refuses a negative funding amount');
reset role;
update public.solicitations set data = data || '{"fundingAmountCents": 1.5}' where id = :'fc2';
select tests.act_as(:'r1');
select throws_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/bid-form.pdf', '{"k":1}', %L, 1)$$,
    :'fc2', :'due2'),
  'P0001', 'invalid_data', 'publish refuses a fractional funding amount');
reset role;
update public.solicitations set data = data || '{"fundingAmountCents": "16000000"}' where id = :'fc2';
select tests.act_as(:'r1');
select throws_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc2/v1/bid-form.pdf', '{"k":1}', %L, 16000000)$$,
    :'fc2', :'due2'),
  'P0001', 'invalid_data', 'publish refuses a funding amount stored as a string');

reset role;
select is((select state::text from public.solicitations where id = :'fc1'), 'approved',
  'refused publishes leave the row approved');
select is((select count(*)::int from public.solicitation_funding where solicitation_id in (:'fc1', :'fc2')), 0,
  'refused publishes freeze no funding amount');

select tests.act_as(:'r1');
select lives_ok(format($$select public.publish_solicitation(%L,
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-000000000fc1/v1/bid-form.pdf', %L, %L, 16000000)$$,
    :'fc1', :'snap1', :'due1'),
  'publish with the matching funding amount succeeds');

reset role;
select is((select state::text from public.solicitations where id = :'fc1'), 'published', 'fc1 is published');
select is((select funding_cents from public.solicitation_funding where solicitation_id = :'fc1'), 16000000::bigint,
  'publish freezes the funding amount in solicitation_funding');
select is(app.funding_cents(:'fc1'), 16000000::bigint, 'funding_cents reads the frozen amount');
select ok(not ((select data from public.solicitations where id = :'fc1') ? 'fundingAmountCents'),
  'publish removes the funding amount from the public data');
select ok(not jsonb_path_exists((select published_snapshot from public.solicitations where id = :'fc1'),
                                '$.**.fundingAmountCents'),
  'the published snapshot carries no funding amount');
select is((select (data ->> 'estimateCents')::bigint from public.solicitations where id = :'fc1'), 15000000::bigint,
  'the rest of the data is unchanged');
select is((select (detail ->> 'funding_cents')::bigint from public.audit_log
           where solicitation_id = :'fc1' and action = 'publish_solicitation'), 16000000::bigint,
  'the publish audit records the funding amount (staff-only audit log)');

-- ===========================================================================
-- After publish: who reads the frozen amount
-- ===========================================================================
select tests.act_as_anon();
select is((select count(*)::int from public.solicitations where id = :'fc1'), 1,
  'after publish: anon reads the released row');
select ok(not jsonb_path_exists((select to_jsonb(s) from public.solicitations s where s.id = :'fc1'),
                                '$.**.fundingAmountCents'),
  'after publish: nothing anon can read in the row holds the funding amount');
select throws_ok(format($$select count(*) from public.solicitation_funding where solicitation_id = %L$$, :'fc1'),
  '42501', null, 'after publish: anon cannot read the funding table at all (0 rows)');

select tests.act_as(:'bidder');
select is((select count(*)::int from public.solicitations where id = :'fc1'), 1,
  'after publish: a bidder reads the released row');
select ok(not jsonb_path_exists((select to_jsonb(s) from public.solicitations s where s.id = :'fc1'),
                                '$.**.fundingAmountCents'),
  'after publish: nothing a bidder can read in the row holds the funding amount');
select is((select count(*)::int from public.solicitation_funding where solicitation_id in (:'fc1', :'p_funded')), 0,
  'after publish: a bidder reads 0 funding rows');

select tests.act_as(:'other_agency');
select is((select count(*)::int from public.solicitation_funding where solicitation_id in (:'fc1', :'p_funded')), 0,
  'after publish: another agency reads 0 funding rows');

select tests.act_as(:'author');
select is((select funding_cents from public.solicitation_funding where solicitation_id = :'fc1'), 16000000::bigint,
  'after publish: the owning agency reads the funding amount');
select tests.act_as(:'r3');
select is((select funding_cents from public.solicitation_funding where solicitation_id = :'fc1'), 16000000::bigint,
  'after publish: any office staff member reads the funding amount');

-- ===========================================================================
-- Nobody changes it after publish
-- ===========================================================================
select tests.act_as(:'author');
select throws_ok(format($$update public.solicitation_funding set funding_cents = 1 where solicitation_id = %L$$, :'fc1'),
  '42501', null, 'the agency cannot update the funding amount');
select tests.act_as(:'r1');
select throws_ok(format($$update public.solicitation_funding set funding_cents = 1 where solicitation_id = %L$$, :'fc1'),
  '42501', null, 'office staff cannot update the funding amount');
select throws_ok(format($$delete from public.solicitation_funding where solicitation_id = %L$$, :'fc1'),
  '42501', null, 'office staff cannot delete the funding amount');
select throws_ok(format($$insert into public.solicitation_funding (solicitation_id, funding_cents) values (%L, 1)$$, :'fc2'),
  '42501', null, 'office staff cannot insert a funding amount');
select tests.act_as_service_role();
select throws_ok(format($$update public.solicitation_funding set funding_cents = 1 where solicitation_id = %L$$, :'fc1'),
  '42501', null, 'service_role cannot update the funding amount');

reset role;
select throws_ok(format($$update public.solicitation_funding set funding_cents = 1 where solicitation_id = %L$$, :'fc1'),
  'P0001', null, 'even the table owner cannot update the funding amount (append-only trigger)');
select throws_ok(format($$delete from public.solicitation_funding where solicitation_id = %L$$, :'fc1'),
  'P0001', null, 'even the table owner cannot delete the funding amount');
select throws_ok(format($$update public.solicitations set data = data || '{"fundingAmountCents": 1}' where id = %L$$, :'fc1'),
  'P0001', null, 'the published row is frozen');

select * from finish();
rollback;
