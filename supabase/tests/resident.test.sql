-- 0019: office verification of resident certificates (slice 2b, Task 5).
begin;

select plan(44);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000fe1', 'RV Office', 'office'),
  ('00000000-0000-0000-0000-000000000fa1', 'RV Agency', 'agency');
\set agency '00000000-0000-0000-0000-000000000fa1'
select tests.make_user('rv.author@test.test', :'agency') as author \gset
select tests.make_user('rv.office@test.test', '00000000-0000-0000-0000-000000000fe1') as office_u \gset
select tests.make_bidder('rv.a@test.test', 'RV Claimant Co') as bidder_a \gset
select tests.make_bidder('rv.b@test.test', 'RV Plain Co') as bidder_b \gset
select tests.make_bidder('rv.c@test.test', 'RV Claimant Two Co') as bidder_c \gset

-- A claim, as register_bidder records it (certificate present iff claimed).
update public.bidder_companies set resident_claimed = true, resident_certificate = 'CR-0042'
 where org_id = (select org_id from public.profiles where user_id = :'bidder_a');
update public.bidder_companies set resident_claimed = true, resident_certificate = 'CR-0077'
 where org_id = (select org_id from public.profiles where user_id = :'bidder_c');

create function tests.rv_error(p_sql text)
returns text
language plpgsql
as $$
declare
  v_state text; v_msg text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return v_state || '|' || v_msg;
end;
$$;
grant execute on function tests.rv_error(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Shape and privileges
-- ---------------------------------------------------------------------------
select has_table('public', 'resident_verifications', 'resident_verifications exists');
select has_function('app', 'resident_verified', array['uuid'], 'app.resident_verified exists');
select has_function('app', 'resident_unverified', array['uuid'], 'app.resident_unverified exists');
select has_function('public', 'verify_resident', array['uuid', 'boolean', 'text'], 'public.verify_resident exists');
select has_function('public', 'resident_claims', array['uuid'], 'public.resident_claims exists');
select ok(not has_function_privilege('authenticated', 'app.resident_verified(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'app.resident_unverified(uuid)', 'execute')
      and not has_function_privilege('anon', 'app.resident_verified(uuid)', 'execute')
      and not has_function_privilege('service_role', 'app.resident_unverified(uuid)', 'execute')
      and not has_function_privilege('public', 'app.resident_verified(uuid)', 'execute'),
  'app helpers: no execute for public, anon, authenticated or service_role');
select ok(has_function_privilege('authenticated', 'public.verify_resident(uuid, boolean, text)', 'execute')
      and has_function_privilege('authenticated', 'public.resident_claims(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.verify_resident(uuid, boolean, text)', 'execute')
      and not has_function_privilege('anon', 'public.resident_claims(uuid)', 'execute')
      and not has_function_privilege('service_role', 'public.verify_resident(uuid, boolean, text)', 'execute')
      and not has_function_privilege('service_role', 'public.resident_claims(uuid)', 'execute')
      and not has_function_privilege('public', 'public.verify_resident(uuid, boolean, text)', 'execute')
      and not has_function_privilege('public', 'public.resident_claims(uuid)', 'execute'),
  'verify_resident and resident_claims: authenticated only');
select ok(not has_table_privilege('authenticated', 'public.resident_verifications', 'select')
      and not has_table_privilege('authenticated', 'public.resident_verifications', 'insert')
      and not has_table_privilege('anon', 'public.resident_verifications', 'select')
      and not has_table_privilege('service_role', 'public.resident_verifications', 'select')
      and not has_table_privilege('service_role', 'public.resident_verifications', 'insert'),
  'resident_verifications: no API privileges');

-- ---------------------------------------------------------------------------
-- Fixtures
--   sol (closed): claimant A, plain B.   sol2 (closed): claimant C (moved to recap_check).
--   sol_open (due in an hour): claimant A.
-- ---------------------------------------------------------------------------
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour') as sol \gset
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour') as sol2 \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 hour') as sol_open \gset
select tests.make_closed_bid(:'sol', :'bidder_a', '{100,200}', '{5}', 'paper', null, true, true) as bid_a \gset
select tests.make_closed_bid(:'sol', :'bidder_b', '{300,400}', '{5}', 'paper', null, true, true) as bid_b \gset
select tests.make_closed_bid(:'sol2', :'bidder_c', '{1,1}', '{1}', 'paper', null, true, true) as bid_c \gset
select tests.make_closed_bid(:'sol_open', :'bidder_a', '{1,1}', '{1}', 'paper', null, true, true) as bid_f \gset

-- Helper predicates (app helpers run as the table owner here).
select is(app.resident_verified(:'bid_a'), false, 'resident_verified: false with no row');
select is(app.resident_unverified(:'bid_a'), true, 'resident_unverified: claimant with no row');
select is(app.resident_unverified(:'bid_b'), false, 'resident_unverified: false for a non-claimant');
select is(app.resident_verified(gen_random_uuid()), false, 'resident_verified: false for an unknown bid');
select is(app.resident_unverified(gen_random_uuid()), false, 'resident_unverified: false for an unknown bid');

-- ---------------------------------------------------------------------------
-- verify_resident: errors
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select is(tests.rv_error(format($q$select public.verify_resident(%L, true, 'Checked')$q$, gen_random_uuid())),
  'P0001|not_found', 'unknown bid: not_found');
select is(tests.rv_error(format($q$select public.verify_resident(%L, true, 'Checked')$q$, :'bid_f')),
  'P0001|sealed', 'before close: sealed');
select is(tests.rv_error(format($q$select public.verify_resident(%L, true, 'Checked')$q$, :'bid_b')),
  'P0001|invalid_state', 'non-claimant: invalid_state');
select is(tests.rv_error(format($q$select public.verify_resident(%L, null, 'Checked')$q$, :'bid_a')),
  'P0001|invalid_data', 'null verdict: invalid_data');
select is(tests.rv_error(format($q$select public.verify_resident(%L, true, '   ')$q$, :'bid_a')),
  'P0001|reason_required', 'blank note: reason_required');
select is(tests.rv_error(format($q$select public.verify_resident(%L, true, null)$q$, :'bid_a')),
  'P0001|reason_required', 'null note: reason_required');
select tests.act_as(:'bidder_a');
select is(tests.rv_error(format($q$select public.verify_resident(%L, true, 'Mine')$q$, :'bid_a')),
  'P0001|not_authorized', 'bidder: not_authorized');
select tests.act_as(:'author');
select is(tests.rv_error(format($q$select public.verify_resident(%L, true, 'Agency')$q$, :'bid_a')),
  'P0001|not_authorized', 'agency author: not_authorized');
select tests.act_as_anon();
select is(tests.rv_error(format($q$select public.verify_resident(%L, true, 'Anon')$q$, :'bid_a')),
  '42501|permission denied for function verify_resident', 'anon: no execute privilege');
reset role;
select is((select count(*)::int from public.resident_verifications where solicitation_id in (:'sol', :'sol2')), 0,
  'rejected calls wrote no rows');

-- ---------------------------------------------------------------------------
-- verify_resident: success, overturn
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select public.verify_resident(:'bid_a', true, 'Certificate checked against the registry') as ver1 \gset
select isnt(:'ver1'::uuid, null::uuid, 'verify_resident: returns the row id');
reset role;
select is(app.resident_verified(:'bid_a'), true, 'resident_verified: true after a verifying row');
select is(app.resident_unverified(:'bid_a'), false, 'resident_unverified: false once a row exists');
select is((select certificate from public.resident_verifications where id = :'ver1'), 'CR-0042',
  'the certificate is copied from the company row');
select is((select row(verified, note, verified_by, solicitation_id, bid_id)::text from public.resident_verifications where id = :'ver1'),
  row(true, 'Certificate checked against the registry', :'office_u'::uuid, :'sol'::uuid, :'bid_a'::uuid)::text,
  'row: verdict, note, verifier, solicitation, bid');
select is((select detail from public.bid_audit_log where bid_id = :'bid_a' and action = 'verify_resident' order by id desc limit 1),
  jsonb_build_object('verified', true, 'certificate', 'CR-0042', 'note', 'Certificate checked against the registry'),
  'audit detail: verified, certificate, note');

-- The company row changes later; an earlier row keeps the certificate it checked.
update public.bidder_companies set resident_certificate = 'CR-0042B'
 where org_id = (select org_id from public.profiles where user_id = :'bidder_a');
select tests.act_as(:'office_u');
select public.verify_resident(:'bid_a', false, 'Certificate expired') as ver2 \gset
reset role;
select is(app.resident_verified(:'bid_a'), false, 'resident_verified: a later false row wins');
select is((select certificate from public.resident_verifications where id = :'ver2'), 'CR-0042B', 'the new row copies the current certificate');
select is((select certificate from public.resident_verifications where id = :'ver1'), 'CR-0042', 'the old row is unchanged');
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_a' and action = 'verify_resident'), 2,
  'two verify_resident audit rows');

-- ---------------------------------------------------------------------------
-- resident_claims
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select is((select count(*)::int from public.resident_claims(:'sol')), 1, 'resident_claims: one row for the fixture solicitation');
select is((select row(r.bid_id, r.certificate, r.verified, r.note)::text from public.resident_claims(:'sol') r),
  row(:'bid_a'::uuid, 'CR-0042B', false, 'Certificate expired')::text, 'resident_claims: the latest verdict and note');
select is((select r.verified_at is not null from public.resident_claims(:'sol') r), true, 'resident_claims: verified_at set');
select is((select row(r.bid_id, r.certificate, r.verified, r.note, r.verified_at)::text from public.resident_claims(:'sol2') r),
  row(:'bid_c'::uuid, 'CR-0077', null::boolean, null::text, null::timestamptz)::text,
  'resident_claims: unverified claim shows null verified');
select is(tests.rv_error(format('select * from public.resident_claims(%L)', :'sol_open')), 'P0001|sealed', 'resident_claims before close: sealed');
select tests.act_as(:'bidder_a');
select is(tests.rv_error(format('select * from public.resident_claims(%L)', :'sol')), 'P0001|not_authorized', 'resident_claims as bidder: not_authorized');
select tests.act_as(:'author');
select is(tests.rv_error(format('select * from public.resident_claims(%L)', :'sol')), 'P0001|not_authorized', 'resident_claims as agency: not_authorized');
reset role;

-- ---------------------------------------------------------------------------
-- Stage gate
-- ---------------------------------------------------------------------------
select app.lock_evaluation(:'sol2');
update public.evaluations set stage = 'recap_check' where solicitation_id = :'sol2';
select tests.act_as(:'office_u');
select is(tests.rv_error(format($q$select public.verify_resident(%L, true, 'Checked')$q$, :'bid_c')),
  'P0001|invalid_state', 'recap_check: invalid_state');
reset role;

-- ---------------------------------------------------------------------------
-- Append-only
-- ---------------------------------------------------------------------------
select is(array[
    tests.rv_error(format('update public.resident_verifications set note = %L where bid_id = %L', 'x', :'bid_a')),
    tests.rv_error(format('delete from public.resident_verifications where bid_id = %L', :'bid_a')),
    tests.rv_error('truncate public.resident_verifications')],
  array['P0001|resident_verifications is append-only: UPDATE is not allowed',
        'P0001|resident_verifications is append-only: DELETE is not allowed',
        'P0001|resident_verifications is append-only: TRUNCATE is not allowed'],
  'table owner: update/delete/truncate raise (trigger)');
select tests.act_as(:'office_u');
select is(tests.rv_error(format('update public.resident_verifications set note = %L where bid_id = %L', 'x', :'bid_a')),
  '42501|permission denied for table resident_verifications', 'office: update denied');
select is(tests.rv_error(format('delete from public.resident_verifications where bid_id = %L', :'bid_a')),
  '42501|permission denied for table resident_verifications', 'office: delete denied');
reset role;

select * from finish();
rollback;
