-- 0018: bid review outcomes, evaluation state and derived review statuses (slice 2b, Task 4).
begin;

select plan(95);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000ef1', 'RO Office', 'office'),
  ('00000000-0000-0000-0000-000000000ea1', 'RO Agency', 'agency'),
  ('00000000-0000-0000-0000-000000000ea2', 'RO Other Agency', 'agency');
\set agency '00000000-0000-0000-0000-000000000ea1'
select tests.make_user('ro.author@test.test', :'agency') as author \gset
select tests.make_user('ro.other@test.test', '00000000-0000-0000-0000-000000000ea2') as other_author \gset
select tests.make_user('ro.office@test.test', '00000000-0000-0000-0000-000000000ef1') as office_u \gset
select tests.make_bidder('ro.a@test.test', 'RO Bidder A') as bidder_a \gset
select tests.make_bidder('ro.b@test.test', 'RO Bidder B') as bidder_b \gset
select tests.make_bidder('ro.c@test.test', 'RO Bidder C') as bidder_c \gset
select tests.make_bidder('ro.d@test.test', 'RO Bidder D') as bidder_d \gset
select tests.make_bidder('ro.e@test.test', 'RO Bidder E') as bidder_e \gset

-- The error a statement raises, as 'sqlstate|message', or 'ok'.
create function tests.ro_error(p_sql text)
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
grant execute on function tests.ro_error(text) to anon, authenticated, service_role;

\set auto_signed 'signed original not received by the bid due time'
\set auto_bond 'bid bond not received by the cure deadline'

-- ---------------------------------------------------------------------------
-- Shape and privileges
-- ---------------------------------------------------------------------------
select has_table('public', 'evaluations', 'evaluations exists');
select has_table('public', 'bid_outcomes', 'bid_outcomes exists');
select has_table('public', 'flagged_decisions', 'flagged_decisions exists');
select enum_has_labels('public', 'evaluation_stage',
  array['bid_review', 'recap_check', 'recap_posted', 'award_check', 'awarded', 'all_rejected'], 'evaluation_stage labels');
select enum_has_labels('public', 'bid_outcome', array['accepted', 'accepted_flagged', 'non_responsive'], 'bid_outcome labels');
select enum_has_labels('public', 'non_responsive_ground', array['late_upload', 'wrong_form', 'missing_signature'],
  'non_responsive_ground labels');
select enum_has_labels('public', 'flag_decision', array['accept', 'reject'], 'flag_decision labels');
select has_function('app', 'lock_evaluation', array['uuid'], 'app.lock_evaluation exists');
select has_function('app', 'require_stage', array['evaluations', 'evaluation_stage'], 'app.require_stage exists');
select has_function('app', 'current_outcome', array['uuid'], 'app.current_outcome exists');
select has_function('app', 'bid_review_status', array['uuid', 'timestamp with time zone'], 'app.bid_review_status exists');
select ok(not has_function_privilege('authenticated', 'app.bid_review_status(uuid, timestamptz)', 'execute')
      and not has_function_privilege('authenticated', 'app.lock_evaluation(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'app.current_outcome(uuid)', 'execute'),
  'app helpers: no execute for authenticated');
select ok(has_function_privilege('authenticated', 'public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text)', 'execute')
      and has_function_privilege('authenticated', 'public.review_bids(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text)', 'execute')
      and not has_function_privilege('service_role', 'public.review_bids(uuid)', 'execute'),
  'set_bid_outcome and review_bids: authenticated only');
select ok(not has_table_privilege('authenticated', 'public.evaluations', 'select')
      and not has_table_privilege('authenticated', 'public.evaluations', 'update')
      and not has_table_privilege('authenticated', 'public.evaluations', 'insert')
      and not has_table_privilege('service_role', 'public.evaluations', 'select')
      and not has_table_privilege('anon', 'public.evaluations', 'select'),
  'evaluations: no whole-table select and no write grants');
select ok(has_column_privilege('authenticated', 'public.evaluations', 'solicitation_id', 'select')
      and has_column_privilege('authenticated', 'public.evaluations', 'stage', 'select')
      and has_column_privilege('authenticated', 'public.evaluations', 'flags_released_at', 'select')
      and has_column_privilege('authenticated', 'public.evaluations', 'updated_at', 'select'),
  'evaluations: authenticated may select the stage columns');
select ok(not has_column_privilege('authenticated', 'public.evaluations', 'recap_draft', 'select')
      and not has_column_privilege('authenticated', 'public.evaluations', 'recap_preparer_id', 'select')
      and not has_column_privilege('authenticated', 'public.evaluations', 'award_preparer_id', 'select'),
  'evaluations: authenticated cannot select recap_draft or the preparer ids');
select ok(not has_any_column_privilege('anon', 'public.evaluations', 'select')
      and not has_any_column_privilege('service_role', 'public.evaluations', 'select'),
  'evaluations: anon and service_role have no column select');
select ok(not has_table_privilege('authenticated', 'public.bid_outcomes', 'select')
      and not has_table_privilege('service_role', 'public.bid_outcomes', 'insert')
      and not has_table_privilege('anon', 'public.bid_outcomes', 'select')
      and not has_table_privilege('authenticated', 'public.flagged_decisions', 'select')
      and not has_table_privilege('service_role', 'public.flagged_decisions', 'select'),
  'bid_outcomes and flagged_decisions: no API privileges');
select policies_are('public', 'evaluations', array['evaluations_read'], 'evaluations has only evaluations_read');

-- ---------------------------------------------------------------------------
-- Fixtures
--   sol (closed an hour ago): A all fine; B no signed original; C paper bond, no bond original (pending cure).
--   sol2 (closed): D electronic choice with no bond file (Ruling 7, pending cure); E all fine.
--   sol_open (due in an hour): F.
-- ---------------------------------------------------------------------------
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour') as sol \gset
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour') as sol2 \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 hour') as sol_open \gset

select tests.make_closed_bid(:'sol', :'bidder_a', '{100,200}', '{5}', 'paper', null, true, true) as bid_a \gset
select tests.make_closed_bid(:'sol', :'bidder_b', '{300,400}', '{5}', 'paper', null, false, true) as bid_b \gset
select tests.make_closed_bid(:'sol', :'bidder_c', '{500,600}', '{5}', 'paper', null, true, false) as bid_c \gset
select tests.make_closed_bid(:'sol2', :'bidder_d', '{1,1}', '{1}', 'paper', null, true, true) as bid_d \gset
-- D's sealed version becomes electronic with no bond file (version rows are append-only: seal a v2 with its own
-- counted signed original).
insert into public.bid_versions (bid_id, version, submitted_at, submitted_by, item_cents, alternate_cents,
                                 bid_bond_choice, bidder_legal_name)
select :'bid_d', 2, s.bid_due_at - interval '90 minutes', :'bidder_d', '{1,1}', '{1}', 'electronic', 'RO Bidder D'
  from public.solicitations s where s.id = :'sol2';
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
select :'sol2', b.id, b.reference, 2, 'signed_form', s.bid_due_at - interval '1 hour', :'bidder_d', s.bid_due_at - interval '1 hour'
  from public.bids b join public.solicitations s on s.id = b.solicitation_id where b.id = :'bid_d';
select tests.make_closed_bid(:'sol2', :'bidder_e', '{1,1}', '{1}', 'paper', null, true, true) as bid_e \gset
select tests.make_closed_bid(:'sol_open', :'bidder_a', '{1,1}', '{1}', 'paper', null, true, true) as bid_f \gset

select bid_due_at as sol_due from public.solicitations where id = :'sol' \gset
select app.cure_due_at(:'sol_due') as cure_due \gset

-- ---------------------------------------------------------------------------
-- app.lock_evaluation
-- ---------------------------------------------------------------------------
select is(tests.ro_error(format('select app.lock_evaluation(%L)', :'sol_open')), 'P0001|sealed', 'lock_evaluation: open -> sealed');
select is(tests.ro_error(format('select app.lock_evaluation(%L)', gen_random_uuid())), 'P0001|sealed',
  'lock_evaluation: unknown solicitation -> sealed');
select is((app.lock_evaluation(:'sol')).stage, 'bid_review'::public.evaluation_stage, 'lock_evaluation: created at bid_review');
select app.lock_evaluation(:'sol');
select is((select count(*)::int from public.evaluations where solicitation_id = :'sol'), 1,
  'lock_evaluation twice: exactly one evaluations row');
select is((select count(*)::int from public.evaluations where solicitation_id = :'sol_open'), 0, 'no row for the open one');
select is((select cure_due_at from public.cure_deadlines where solicitation_id = :'sol'), :'cure_due'::timestamptz,
  'lock_evaluation froze the cure deadline (Ruling 3)');

-- app.require_stage
select is(tests.ro_error(format($q$select app.require_stage(e, 'recap_check') from public.evaluations e where e.solicitation_id = %L$q$, :'sol')),
  'P0001|invalid_state', 'require_stage: wrong stage -> invalid_state');
select is(tests.ro_error(format($q$select app.require_stage(e, 'bid_review') from public.evaluations e where e.solicitation_id = %L$q$, :'sol')),
  'ok', 'require_stage: matching stage passes');

-- ---------------------------------------------------------------------------
-- Derived statuses before any outcome
-- ---------------------------------------------------------------------------
select is((select row(status, reason)::text from app.bid_review_status(:'bid_a')), row('undecided', null::text)::text,
  'A with no outcome: undecided');
select is((select row(status, reason)::text from app.bid_review_status(:'bid_b')), row('non_responsive', :'auto_signed')::text,
  'B: non_responsive, signed original reason (verbatim)');
select is((select row(status, reason)::text from app.bid_review_status(:'bid_c')), row('pending_cure', null::text)::text,
  'C: pending_cure');
select is((select status from app.bid_review_status(:'bid_c', :'cure_due'::timestamptz - interval '1 second')), 'pending_cure',
  'C one second before the cure deadline: pending_cure');
select is((select row(status, reason)::text from app.bid_review_status(:'bid_c', :'cure_due'::timestamptz)),
  row('non_responsive', :'auto_bond')::text, 'C at the cure deadline: non_responsive, bond reason (verbatim)');
select is((select status from app.bid_review_status(:'bid_d')), 'pending_cure', 'D electronic, no bond file: pending_cure');
select is((app.current_outcome(:'bid_a')).id, null::uuid, 'current_outcome with no rows: null');

-- ---------------------------------------------------------------------------
-- set_bid_outcome
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, 'Looks fine')$q$, :'bid_f')),
  'P0001|sealed', 'before close: sealed');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, 'Looks fine')$q$, gen_random_uuid())),
  'P0001|not_found', 'unknown bid: not_found');

select public.set_bid_outcome(:'bid_a', 'accepted', null, 'All documents in order') as out_a1 \gset
select isnt(:'out_a1'::uuid, null::uuid, 'A accepted: returns the outcome id');
reset role;
select is((select row(status, reason)::text from app.bid_review_status(:'bid_a')), row('accepted', null::text)::text,
  'A: accepted');
select tests.act_as(:'office_u');
select public.set_bid_outcome(:'bid_a', 'accepted_flagged', null, 'Mailed form total differs from portal entry') as out_a2 \gset
reset role;
select is((select row(status, reason)::text from app.bid_review_status(:'bid_a')),
  row('flagged', 'Mailed form total differs from portal entry')::text, 'A flagged: the note is the reason');
select is((app.current_outcome(:'bid_a')).id, :'out_a2'::uuid, 'current_outcome: the latest row');
select is((select count(*)::int from public.bid_outcomes where bid_id = :'bid_a'), 2, 'A: two outcome rows (append-only history)');
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_a' and action = 'set_bid_outcome'), 2,
  'A: two set_bid_outcome audit rows');
select is((select detail from public.bid_audit_log where bid_id = :'bid_a' and action = 'set_bid_outcome' order by id desc limit 1),
  jsonb_build_object('outcome_id', :'out_a2'::uuid, 'version', 1, 'outcome', 'accepted_flagged', 'ground', null,
                     'note', 'Mailed form total differs from portal entry', 'previous_outcome_id', :'out_a1'::uuid),
  'audit detail: outcome_id, version, outcome, ground, note, previous_outcome_id');
select is((select set_by from public.bid_outcomes where id = :'out_a2'), :'office_u'::uuid, 'set_by is the caller');

-- B: automatic non-responsive is locked
select tests.act_as(:'office_u');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, 'Override')$q$, :'bid_b')),
  'P0001|outcome_locked', 'B accepted: outcome_locked');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'non_responsive', 'wrong_form', 'Override')$q$, :'bid_b')),
  'P0001|outcome_locked', 'B non_responsive: outcome_locked');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, '')$q$, :'bid_b')),
  'P0001|outcome_locked', 'B: outcome_locked precedes reason_required');

-- C: an outcome may be recorded while the cure is pending; the status stays pending_cure.
select isnt(public.set_bid_outcome(:'bid_c', 'accepted', null, 'Pending bond only'), null::uuid, 'C accepted while pending: allowed');
reset role;
select is((select status from app.bid_review_status(:'bid_c')), 'pending_cure', 'C: still pending_cure after an accepted row');
select is((select row(status, reason)::text from app.bid_review_status(:'bid_c', :'cure_due'::timestamptz)),
  row('non_responsive', :'auto_bond')::text, 'C accepted, at the cure deadline: non_responsive (automatic wins)');

-- Validation
select tests.act_as(:'office_u');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'non_responsive', null, 'No ground')$q$, :'bid_a')),
  'P0001|invalid_data', 'non_responsive with a null ground: invalid_data');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', 'late_upload', 'Ground given')$q$, :'bid_a')),
  'P0001|invalid_data', 'accepted with a ground: invalid_data');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, null, null, 'No outcome')$q$, :'bid_a')),
  'P0001|invalid_data', 'null outcome: invalid_data');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, '   ')$q$, :'bid_a')),
  'P0001|reason_required', 'blank note: reason_required');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'non_responsive', null, null)$q$, :'bid_a')),
  'P0001|reason_required', 'null note: reason_required precedes invalid_data');
select tests.act_as(:'bidder_a');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, 'Mine')$q$, :'bid_a')),
  'P0001|not_authorized', 'bidder: not_authorized');
select tests.act_as(:'author');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, 'Agency')$q$, :'bid_a')),
  'P0001|not_authorized', 'agency author: not_authorized');
select tests.act_as_anon();
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, 'Anon')$q$, :'bid_a')),
  '42501|permission denied for function set_bid_outcome', 'anon: no execute privilege');
reset role;
select is((select count(*)::int from public.bid_outcomes where bid_id = :'bid_a'), 2, 'rejected calls wrote no outcome rows');

-- ---------------------------------------------------------------------------
-- Office ground, flagged decisions (sol2, bid E), and the electronic-no-file cure (D)
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select public.set_bid_outcome(:'bid_e', 'accepted_flagged', null, 'Signature page looks different') as out_e1 \gset
select isnt(public.set_bid_outcome(:'bid_d', 'accepted', null, 'Bond to follow'), null::uuid, 'D accepted while pending cure');
reset role;
select is((select status from app.bid_review_status(:'bid_d')), 'pending_cure', 'D: pending_cure after an accepted row');
insert into public.flagged_decisions (solicitation_id, bid_id, outcome_id, decision, reason, decided_by)
values (:'sol2', :'bid_e', :'out_e1', 'accept', 'Signature verified by phone', :'author');
select is((select row(status, reason)::text from app.bid_review_status(:'bid_e')),
  row('flag_accepted', 'Signature verified by phone')::text, 'E flag accepted: the decision reason');
insert into public.flagged_decisions (solicitation_id, bid_id, outcome_id, decision, reason, decided_by, decided_at)
values (:'sol2', :'bid_e', :'out_e1', 'reject', 'Signature could not be verified', :'author', now() + interval '1 second');
select is((select row(status, reason)::text from app.bid_review_status(:'bid_e')),
  row('flag_rejected', 'Signature could not be verified')::text, 'E flag rejected: the latest decision reason');
select tests.act_as(:'office_u');
select public.set_bid_outcome(:'bid_e', 'non_responsive', 'missing_signature', 'Unsigned form') as out_e2 \gset
reset role;
select is((select row(status, reason)::text from app.bid_review_status(:'bid_e')),
  row('non_responsive', 'missing signature')::text, 'E office ground: the ground label; the old decision no longer applies');
select tests.act_as(:'office_u');
select public.set_bid_outcome(:'bid_e', 'non_responsive', 'late_upload', 'Uploaded after the due time') as out_e3 \gset
reset role;
select is((select reason from app.bid_review_status(:'bid_e')), 'late upload', 'ground label: late upload');
select tests.act_as(:'office_u');
select public.set_bid_outcome(:'bid_e', 'non_responsive', 'wrong_form', 'Old form revision') as out_e4 \gset
reset role;
select is((select reason from app.bid_review_status(:'bid_e')), 'wrong form', 'ground label: wrong form');
select is(tests.ro_error(format($q$insert into public.bid_outcomes (solicitation_id, bid_id, version, outcome, note, set_by)
  values (%L, %L, 1, 'non_responsive', 'x', %L)$q$, :'sol2', :'bid_e', :'office_u')),
  '23514|new row for relation "bid_outcomes" violates check constraint "bid_outcomes_ground_matches"',
  'table check: ground iff non_responsive');

-- ---------------------------------------------------------------------------
-- review_bids
-- ---------------------------------------------------------------------------
select reference as ref_a, bidder_org_id as org_a from public.bids where id = :'bid_a' \gset
select tests.act_as(:'office_u');
select is((select count(*)::int from public.review_bids(:'sol')), 3, 'review_bids: three rows for this solicitation');
select is((select array_agg(row(r.bid_id, r.status, r.status_reason)::text order by r.base_total_cents)
             from public.review_bids(:'sol') r),
  array[row(:'bid_a'::uuid, 'flagged', 'Mailed form total differs from portal entry')::text,
        row(:'bid_b'::uuid, 'non_responsive', :'auto_signed')::text,
        row(:'bid_c'::uuid, 'pending_cure', null::text)::text],
  'review_bids: statuses and reasons');
select is((select row(r.reference, r.version, r.bidder_name, r.bidder_org_id, r.base_total_cents, r.alternate_cents,
                      r.apprentice_commitment, r.outcome_id, r.outcome, r.ground, r.note)::text
             from public.review_bids(:'sol') r where r.bid_id = :'bid_a'),
  row(:'ref_a', 1, 'RO Bidder A', :'org_a'::uuid, 300::bigint, '{5}'::bigint[], null::boolean,
      :'out_a2'::uuid, 'accepted_flagged'::public.bid_outcome, null::public.non_responsive_ground,
      'Mailed form total differs from portal entry')::text,
  'review_bids: A columns (as submitted, current outcome)');
select is((select row(r.cure_status, r.cure_due_at)::text from public.review_bids(:'sol') r where r.bid_id = :'bid_c'),
  row('pending', :'cure_due'::timestamptz)::text, 'review_bids: C cure pending with its deadline');
select is((select r.cure_status from public.review_bids(:'sol') r where r.bid_id = :'bid_a'), 'ok', 'review_bids: A cure ok');
select is(tests.ro_error(format('select * from public.review_bids(%L)', :'sol_open')), 'P0001|sealed', 'review_bids before close: sealed');
reset role;
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_c' and action = 'bid_cure_determination'), 0,
  'no cure determination audited before the deadline');
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_a' and action = 'bid_close_determination'), 1,
  'review_bids inherits the opened_bids close-determination audit (one row)');
select tests.act_as(:'author');
select is(tests.ro_error(format('select * from public.review_bids(%L)', :'sol')), 'P0001|not_authorized',
  'review_bids as agency author: not_authorized');
select tests.act_as(:'bidder_a');
select is(tests.ro_error(format('select * from public.review_bids(%L)', :'sol')), 'P0001|not_authorized',
  'review_bids as bidder: not_authorized');
reset role;

-- ---------------------------------------------------------------------------
-- evaluations_read
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select is((select count(*)::int from public.evaluations where solicitation_id = :'sol'), 1, 'office reads the evaluation');
select tests.act_as(:'author');
select is((select stage from public.evaluations where solicitation_id = :'sol'), 'bid_review'::public.evaluation_stage,
  'owning agency author reads the stage');
select is(tests.ro_error(format('select recap_draft from public.evaluations where solicitation_id = %L', :'sol')),
  '42501|permission denied for table evaluations', 'owning agency author: recap_draft is not selectable');
select tests.act_as(:'other_author');
select is((select count(*)::int from public.evaluations where solicitation_id = :'sol'), 0, 'another agency reads 0 rows');
select tests.act_as(:'bidder_a');
select is((select count(*)::int from public.evaluations where solicitation_id = :'sol'), 0, 'bidder reads 0 rows');
select tests.act_as_anon();
select throws_ok(format('select * from public.evaluations where solicitation_id = %L', :'sol'), '42501', null,
  'anon: 42501 on evaluations');
reset role;

-- ---------------------------------------------------------------------------
-- Append-only: bid_outcomes and flagged_decisions, every role
-- ---------------------------------------------------------------------------
select is(array[
    tests.ro_error(format('update public.bid_outcomes set note = %L where bid_id = %L', 'x', :'bid_a')),
    tests.ro_error(format('delete from public.bid_outcomes where bid_id = %L', :'bid_a')),
    tests.ro_error(format('update public.flagged_decisions set reason = %L where bid_id = %L', 'x', :'bid_e')),
    tests.ro_error(format('delete from public.flagged_decisions where bid_id = %L', :'bid_e'))],
  array['P0001|bid_outcomes is append-only: UPDATE is not allowed', 'P0001|bid_outcomes is append-only: DELETE is not allowed',
        'P0001|flagged_decisions is append-only: UPDATE is not allowed', 'P0001|flagged_decisions is append-only: DELETE is not allowed'],
  'table owner: update/delete raise (trigger)');
select tests.act_as(:'office_u');
select is(array[
    tests.ro_error(format('update public.bid_outcomes set note = %L where bid_id = %L', 'x', :'bid_a')),
    tests.ro_error(format('delete from public.bid_outcomes where bid_id = %L', :'bid_a')),
    tests.ro_error(format('update public.flagged_decisions set reason = %L where bid_id = %L', 'x', :'bid_e')),
    tests.ro_error(format('delete from public.flagged_decisions where bid_id = %L', :'bid_e'))],
  array['42501|permission denied for table bid_outcomes', '42501|permission denied for table bid_outcomes',
        '42501|permission denied for table flagged_decisions', '42501|permission denied for table flagged_decisions'],
  'authenticated (office): update/delete raise 42501');
select tests.act_as_anon();
select is(array[
    tests.ro_error(format('update public.bid_outcomes set note = %L where bid_id = %L', 'x', :'bid_a')),
    tests.ro_error(format('delete from public.bid_outcomes where bid_id = %L', :'bid_a')),
    tests.ro_error(format('update public.flagged_decisions set reason = %L where bid_id = %L', 'x', :'bid_e')),
    tests.ro_error(format('delete from public.flagged_decisions where bid_id = %L', :'bid_e'))],
  array['42501|permission denied for table bid_outcomes', '42501|permission denied for table bid_outcomes',
        '42501|permission denied for table flagged_decisions', '42501|permission denied for table flagged_decisions'],
  'anon: update/delete raise 42501');
select tests.act_as_service_role();
select is(array[
    tests.ro_error(format('update public.bid_outcomes set note = %L where bid_id = %L', 'x', :'bid_a')),
    tests.ro_error(format('delete from public.bid_outcomes where bid_id = %L', :'bid_a')),
    tests.ro_error(format('update public.flagged_decisions set reason = %L where bid_id = %L', 'x', :'bid_e')),
    tests.ro_error(format('delete from public.flagged_decisions where bid_id = %L', :'bid_e'))],
  array['42501|permission denied for table bid_outcomes', '42501|permission denied for table bid_outcomes',
        '42501|permission denied for table flagged_decisions', '42501|permission denied for table flagged_decisions'],
  'service_role: update/delete raise 42501');
reset role;
select is(tests.ro_error('truncate public.flagged_decisions'),
  'P0001|flagged_decisions is append-only: TRUNCATE is not allowed', 'flagged_decisions: truncate raises (trigger)');
select ok(tests.ro_error('truncate public.bid_outcomes, public.flagged_decisions')
          like 'P0001|% is append-only: TRUNCATE is not allowed', 'bid_outcomes: truncate raises (trigger)');

-- ---------------------------------------------------------------------------
-- Cure deadline in the past (tests.set_bid_due): C becomes automatically non-responsive and locked.
-- C's signed original is re-logged before the new due time so only the bond rule applies.
-- ---------------------------------------------------------------------------
select tests.set_bid_due(:'sol', now() - interval '10 days');
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
select :'sol', b.id, b.reference, 1, 'signed_form', now() - interval '11 days', :'office_u', now() - interval '11 days'
  from public.bids b where b.id = :'bid_c';
select is((select row(status, reason)::text from app.bid_review_status(:'bid_c')), row('non_responsive', :'auto_bond')::text,
  'C past the cure deadline: non_responsive, bond reason');
select tests.act_as(:'office_u');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, 'Too late')$q$, :'bid_c')),
  'P0001|outcome_locked', 'C past the cure deadline: outcome_locked');
select is((select row(r.cure_status, r.status, r.status_reason)::text from public.review_bids(:'sol') r where r.bid_id = :'bid_c'),
  row('failed', 'non_responsive', :'auto_bond')::text, 'review_bids: C failed, non_responsive');
select count(*) from public.review_bids(:'sol');
reset role;
select is((select count(*)::int from public.bid_audit_log
            where bid_id = :'bid_c' and action = 'bid_cure_determination' and detail->>'status' = 'failed'), 1,
  'review_bids: one bid_cure_determination row for C across two reads');

-- ---------------------------------------------------------------------------
-- Stage gate: past bid_review, set_bid_outcome -> invalid_state
-- ---------------------------------------------------------------------------
update public.evaluations set stage = 'recap_check' where solicitation_id = :'sol2';
select tests.act_as(:'office_u');
select is(tests.ro_error(format($q$select public.set_bid_outcome(%L, 'accepted', null, 'Late change')$q$, :'bid_e')),
  'P0001|invalid_state', 'stage recap_check: invalid_state');
reset role;
select is((select count(*)::int from public.bid_outcomes where bid_id = :'bid_e'), 4, 'E: no row added past bid_review');

select * from finish();
rollback;
