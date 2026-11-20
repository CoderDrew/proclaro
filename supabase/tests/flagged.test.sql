-- 0020: agency decisions on flagged bids (slice 2b, Task 7).
begin;

select plan(66);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000007f1', 'FL Office', 'office'),
  ('00000000-0000-0000-0000-0000000007a1', 'FL Agency', 'agency'),
  ('00000000-0000-0000-0000-0000000007a2', 'FL Other Agency', 'agency');
\set agency '00000000-0000-0000-0000-0000000007a1'
select tests.make_user('fl.author@test.test', :'agency') as author \gset
select tests.make_user('fl.other@test.test', '00000000-0000-0000-0000-0000000007a2') as other_author \gset
select tests.make_user('fl.office@test.test', '00000000-0000-0000-0000-0000000007f1') as office_u \gset
select tests.make_bidder('fl.a@test.test', 'FL Bidder A') as bidder_a \gset
select tests.make_bidder('fl.b@test.test', 'FL Bidder B') as bidder_b \gset
select tests.make_bidder('fl.c@test.test', 'FL Bidder C') as bidder_c \gset

-- The error a statement raises, as 'sqlstate|message', or 'ok'.
create function tests.fl_error(p_sql text)
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
grant execute on function tests.fl_error(text) to anon, authenticated, service_role;

-- Run an app.* helper as the given user without switching role (API roles cannot execute app helpers).
create function tests.fl_claims(p_user uuid)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
$$;

-- ---------------------------------------------------------------------------
-- Shape and privileges
-- ---------------------------------------------------------------------------
select has_function('app', 'require_solicitation_agency', array['uuid'], 'app.require_solicitation_agency exists');
select has_function('public', 'send_flags_to_agency', array['uuid'], 'send_flags_to_agency exists');
select has_function('public', 'agency_flagged_bids', array['uuid'], 'agency_flagged_bids exists');
select has_function('public', 'decide_flagged_bid', array['uuid', 'flag_decision', 'text'], 'decide_flagged_bid exists');
select ok(not has_function_privilege('authenticated', 'app.require_solicitation_agency(uuid)', 'execute')
      and not has_function_privilege('anon', 'app.require_solicitation_agency(uuid)', 'execute'),
  'app.require_solicitation_agency: no execute for API roles');
select ok(has_function_privilege('authenticated', 'public.send_flags_to_agency(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.agency_flagged_bids(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.decide_flagged_bid(uuid, public.flag_decision, text)', 'execute'),
  'the three functions: authenticated may execute');
select ok(not has_function_privilege('anon', 'public.send_flags_to_agency(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.agency_flagged_bids(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.decide_flagged_bid(uuid, public.flag_decision, text)', 'execute')
      and not has_function_privilege('service_role', 'public.agency_flagged_bids(uuid)', 'execute')
      and not has_function_privilege('service_role', 'public.decide_flagged_bid(uuid, public.flag_decision, text)', 'execute'),
  'the three functions: no execute for anon or service_role');
select is((select proargnames from pg_proc
            where oid = 'public.agency_flagged_bids(uuid)'::regprocedure),
  array['p_solicitation_id', 'outcome_id', 'reference', 'note', 'base_total_cents', 'decision', 'decision_reason', 'decided_at'],
  'agency_flagged_bids: only reference, note, base total and the decision (no bidder name, items or alternates)');

-- ---------------------------------------------------------------------------
-- Fixtures
--   sol (closed): A (to be flagged), B (to be accepted), C (to be non-responsive, office ground). No cure due.
--   sol_cure (closed): D paper bond with no bond original (pending cure).
--   sol_none (closed): E (accepted, nothing flagged).
--   sol_open (due in an hour).
-- ---------------------------------------------------------------------------
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour') as sol \gset
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour') as sol_cure \gset
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour') as sol_none \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 hour') as sol_open \gset

select tests.make_closed_bid(:'sol', :'bidder_a', '{100,200}', '{5}', 'paper', null, true, true) as bid_a \gset
select tests.make_closed_bid(:'sol', :'bidder_b', '{300,400}', '{7}', 'paper', null, true, true) as bid_b \gset
select tests.make_closed_bid(:'sol', :'bidder_c', '{500,600}', '{9}', 'paper', null, true, true) as bid_c \gset
select tests.make_closed_bid(:'sol_cure', :'bidder_a', '{1,1}', '{1}', 'paper', null, true, false) as bid_d \gset
select tests.make_closed_bid(:'sol_none', :'bidder_b', '{1,1}', '{1}', 'paper', null, true, true) as bid_e \gset
select reference as ref_a from public.bids where id = :'bid_a' \gset

-- ---------------------------------------------------------------------------
-- app.require_solicitation_agency
-- ---------------------------------------------------------------------------
select tests.fl_claims(:'author');
select is(tests.fl_error(format('select app.require_solicitation_agency(%L)', :'sol')), 'ok',
  'require_solicitation_agency: owning agency passes');
select is(tests.fl_error(format('select app.require_solicitation_agency(%L)', gen_random_uuid())), 'P0001|not_authorized',
  'require_solicitation_agency: unknown solicitation -> not_authorized');
select tests.fl_claims(:'other_author');
select is(tests.fl_error(format('select app.require_solicitation_agency(%L)', :'sol')), 'P0001|not_authorized',
  'require_solicitation_agency: another agency -> not_authorized');
select tests.fl_claims(:'office_u');
select is(tests.fl_error(format('select app.require_solicitation_agency(%L)', :'sol')), 'P0001|not_authorized',
  'require_solicitation_agency: office -> not_authorized');
select tests.fl_claims(:'bidder_a');
select is(tests.fl_error(format('select app.require_solicitation_agency(%L)', :'sol')), 'P0001|not_authorized',
  'require_solicitation_agency: bidder -> not_authorized');
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is(tests.fl_error(format('select app.require_solicitation_agency(%L)', :'sol')), 'P0001|not_authorized',
  'require_solicitation_agency: no user -> not_authorized');
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- Outcomes: A flagged, C non-responsive; B still undecided
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select public.set_bid_outcome(:'bid_a', 'accepted_flagged', null, 'Missing addendum acknowledgment') as out_a1 \gset
select public.set_bid_outcome(:'bid_c', 'non_responsive', 'wrong_form', 'Old form revision') as out_c \gset
select public.set_bid_outcome(:'bid_e', 'accepted', null, 'All in order') as out_e \gset
reset role;

-- Before release: nothing for the agency, and no decision possible.
select tests.act_as(:'author');
select is((select count(*)::int from public.agency_flagged_bids(:'sol')), 0, 'before release: the agency gets 0 rows');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', 'Fine')$q$, :'out_a1')),
  'P0001|invalid_state', 'before release: decide_flagged_bid -> invalid_state');
reset role;

-- ---------------------------------------------------------------------------
-- send_flags_to_agency
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select is(tests.fl_error(format('select public.send_flags_to_agency(%L)', :'sol')), 'P0001|not_authorized',
  'send_flags_to_agency: agency -> not_authorized');
select tests.act_as(:'bidder_a');
select is(tests.fl_error(format('select public.send_flags_to_agency(%L)', :'sol')), 'P0001|not_authorized',
  'send_flags_to_agency: bidder -> not_authorized');
select tests.act_as(:'office_u');
select is(tests.fl_error(format('select public.send_flags_to_agency(%L)', :'sol_open')), 'P0001|sealed',
  'send_flags_to_agency: before close -> sealed');
select is(tests.fl_error(format('select public.send_flags_to_agency(%L)', :'sol_cure')), 'P0001|cure_pending',
  'send_flags_to_agency: a pending cure -> cure_pending');
select is(tests.fl_error(format('select public.send_flags_to_agency(%L)', :'sol')), 'P0001|undecided_bids',
  'send_flags_to_agency: an undecided bid -> undecided_bids');
select is(tests.fl_error(format('select public.send_flags_to_agency(%L)', :'sol_none')), 'P0001|invalid_state',
  'send_flags_to_agency: no flagged bid -> invalid_state');
select public.set_bid_outcome(:'bid_b', 'accepted', null, 'All documents in order') as out_b \gset
select is(tests.fl_error(format('select public.send_flags_to_agency(%L)', :'sol')), 'ok',
  'send_flags_to_agency: every bid decided -> ok');
reset role;
select is((select flags_released_at from public.evaluations where solicitation_id = :'sol'), now(),
  'send_flags_to_agency: flags_released_at set');
select is((select flags_released_at from public.evaluations where solicitation_id = :'sol_none'), null::timestamptz,
  'a refused send leaves flags_released_at unset');
-- Idempotent: a second call keeps the first time.
update public.evaluations set flags_released_at = now() - interval '1 hour' where solicitation_id = :'sol';
select tests.act_as(:'office_u');
select public.send_flags_to_agency(:'sol');
reset role;
select is((select flags_released_at from public.evaluations where solicitation_id = :'sol'), now() - interval '1 hour',
  'send_flags_to_agency twice: keeps the first release time');
select is((select count(*)::int from public.bid_audit_log
            where solicitation_id = :'sol' and action = 'send_flags_to_agency' and bid_id is null
              and actor_id = :'office_u' and detail = '{"flagged_count": 1}'::jsonb), 2,
  'send_flags_to_agency: audited with flagged_count each time');

-- ---------------------------------------------------------------------------
-- agency_flagged_bids after release
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select is((select count(*)::int from public.agency_flagged_bids(:'sol')), 1, 'after release: exactly one row');
select is((select row(outcome_id, reference, note, base_total_cents, decision, decision_reason, decided_at)::text
             from public.agency_flagged_bids(:'sol')),
  row(:'out_a1'::uuid, :'ref_a', 'Missing addendum acknowledgment', 300::bigint, null::public.flag_decision,
      null::text, null::timestamptz)::text,
  'the row is A: its outcome, reference, note and base total; no decision yet');
select is((select count(*)::int from public.agency_flagged_bids(:'sol') f where f.reference <> :'ref_a'), 0,
  'no row for B or C');
select is((select count(*)::int from public.agency_flagged_bids(:'sol_none')), 0, 'unreleased solicitation: 0 rows');
select is(tests.fl_error(format('select * from public.agency_flagged_bids(%L)', :'sol_open')), 'P0001|sealed',
  'agency_flagged_bids: before close -> sealed');
select tests.act_as(:'other_author');
select is(tests.fl_error(format('select * from public.agency_flagged_bids(%L)', :'sol')), 'P0001|not_authorized',
  'agency_flagged_bids: another agency -> not_authorized');
select tests.act_as(:'bidder_a');
select is(tests.fl_error(format('select * from public.agency_flagged_bids(%L)', :'sol')), 'P0001|not_authorized',
  'agency_flagged_bids: a bidder -> not_authorized');
select tests.act_as(:'office_u');
select is(tests.fl_error(format('select * from public.agency_flagged_bids(%L)', :'sol')), 'P0001|not_authorized',
  'agency_flagged_bids: the office -> not_authorized');
reset role;

-- ---------------------------------------------------------------------------
-- decide_flagged_bid
-- ---------------------------------------------------------------------------
select tests.act_as(:'other_author');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', 'Fine')$q$, :'out_a1')),
  'P0001|not_authorized', 'decide_flagged_bid: another agency -> not_authorized');
select tests.act_as(:'bidder_a');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', 'Fine')$q$, :'out_a1')),
  'P0001|not_authorized', 'decide_flagged_bid: a bidder -> not_authorized');
select tests.act_as(:'office_u');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', 'Fine')$q$, :'out_a1')),
  'P0001|not_authorized', 'decide_flagged_bid: the office -> not_authorized');
select tests.act_as(:'author');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', 'Fine')$q$, gen_random_uuid())),
  'P0001|not_authorized', 'decide_flagged_bid: unknown outcome -> not_authorized');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', 'Fine')$q$, :'out_b')),
  'P0001|invalid_state', 'decide_flagged_bid: an accepted (not flagged) outcome -> invalid_state');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', '   ')$q$, :'out_a1')),
  'P0001|reason_required', 'decide_flagged_bid: blank reason -> reason_required');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', null)$q$, :'out_a1')),
  'P0001|reason_required', 'decide_flagged_bid: null reason -> reason_required');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, null, 'Fine')$q$, :'out_a1')),
  'P0001|invalid_data', 'decide_flagged_bid: null decision -> invalid_data');

select public.decide_flagged_bid(:'out_a1', 'reject', '  Missing addendum acknowledgment is material ') as dec_1 \gset
reset role;
select is((select row(status, reason)::text from app.bid_review_status(:'bid_a')),
  row('flag_rejected', 'Missing addendum acknowledgment is material')::text, 'reject: A is flag_rejected with the reason');
select is((select row(solicitation_id, bid_id, outcome_id, decided_by)::text from public.flagged_decisions where id = :'dec_1'),
  row(:'sol'::uuid, :'bid_a'::uuid, :'out_a1'::uuid, :'author'::uuid)::text,
  'the decision row takes bid and solicitation from the outcome row');
select tests.act_as(:'author');
select is((select row(decision, decision_reason)::text from public.agency_flagged_bids(:'sol')),
  row('reject'::public.flag_decision, 'Missing addendum acknowledgment is material')::text,
  'agency_flagged_bids shows the current decision');
select public.decide_flagged_bid(:'out_a1', 'accept', 'Acknowledgment received by email before the due time') as dec_2 \gset
reset role;
select is((select row(status, reason)::text from app.bid_review_status(:'bid_a')),
  row('flag_accepted', 'Acknowledgment received by email before the due time')::text,
  'a revised decision (same transaction): A is flag_accepted');
select is((select count(*)::int from public.flagged_decisions where outcome_id = :'out_a1'), 2,
  'both decisions are kept (append-only)');

-- The office changes A's outcome to accepted_flagged again: a new row, so the old decision no longer applies.
select tests.act_as(:'office_u');
select public.set_bid_outcome(:'bid_a', 'accepted_flagged', null, 'Addendum 2 acknowledgment unsigned') as out_a2 \gset
reset role;
select is((select row(status, reason)::text from app.bid_review_status(:'bid_a')),
  row('flagged', 'Addendum 2 acknowledgment unsigned')::text, 'a new flagged outcome: status flagged, old decision dropped');
select tests.act_as(:'author');
select is((select row(outcome_id, note, decision)::text from public.agency_flagged_bids(:'sol')),
  row(:'out_a2'::uuid, 'Addendum 2 acknowledgment unsigned', null::public.flag_decision)::text,
  'agency_flagged_bids: the new outcome with no decision');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', 'Fine')$q$, :'out_a1')),
  'P0001|invalid_state', 'decide_flagged_bid on the old outcome -> invalid_state');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'reject', '')$q$, :'out_a1')),
  'P0001|invalid_state', 'old outcome with a blank reason: invalid_state comes before reason_required');
select isnt(public.decide_flagged_bid(:'out_a2', 'accept', 'Signed copy on file'), null::uuid,
  'decide_flagged_bid on the new outcome: ok');
reset role;

-- ---------------------------------------------------------------------------
-- Audit: decide_flagged_bid rows visible to the office, not to the agency
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public.bid_audit_log
            where bid_id = :'bid_a' and action = 'decide_flagged_bid' and actor_id = :'author'), 3,
  'decide_flagged_bid: one audit row per decision');
select is((select detail from public.bid_audit_log
            where bid_id = :'bid_a' and action = 'decide_flagged_bid' and detail->>'outcome_id' = :'out_a1'
              and detail->>'decision' = 'reject'),
  jsonb_build_object('outcome_id', :'out_a1'::uuid, 'decision', 'reject', 'reason', 'Missing addendum acknowledgment is material'),
  'decide_flagged_bid audit detail: outcome_id, decision, reason');
select tests.act_as(:'office_u');
select is((select count(*)::int from public.bid_audit_log
            where solicitation_id = :'sol' and action in ('decide_flagged_bid', 'send_flags_to_agency')), 5,
  'the office sees the decision and release audit rows');
select tests.act_as(:'author');
select is((select count(*)::int from public.bid_audit_log where solicitation_id = :'sol'), 0,
  'the agency sees no bid_audit_log rows');
select is(tests.fl_error('select count(*) from public.flagged_decisions'), '42501|permission denied for table flagged_decisions',
  'the agency cannot read flagged_decisions directly');
reset role;

-- ---------------------------------------------------------------------------
-- Integrity: a decision must match its outcome row's bid and solicitation; an outcome its bid's solicitation
-- ---------------------------------------------------------------------------
select is(left(tests.fl_error(format($q$insert into public.flagged_decisions (solicitation_id, bid_id, outcome_id, decision, reason, decided_by)
  values (%L, %L, %L, 'accept', 'x', %L)$q$, :'sol', :'bid_b', :'out_a2', :'author')), 5), '23503',
  'flagged_decisions: a bid that does not match the outcome row is refused');
select is(left(tests.fl_error(format($q$insert into public.flagged_decisions (solicitation_id, bid_id, outcome_id, decision, reason, decided_by)
  values (%L, %L, %L, 'accept', 'x', %L)$q$, :'sol_none', :'bid_a', :'out_a2', :'author')), 5), '23503',
  'flagged_decisions: a solicitation that does not match the outcome row is refused');
select is(left(tests.fl_error(format($q$insert into public.bid_outcomes (solicitation_id, bid_id, version, outcome, note, set_by)
  values (%L, %L, 1, 'accepted', 'x', %L)$q$, :'sol_none', :'bid_a', :'office_u')), 5), '23503',
  'bid_outcomes: a solicitation that is not the bid''s is refused');

-- ---------------------------------------------------------------------------
-- Stage gate: past bid_review, neither the release nor a decision is possible
-- ---------------------------------------------------------------------------
update public.evaluations set stage = 'recap_check' where solicitation_id = :'sol';
select tests.act_as(:'author');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'reject', 'Too late')$q$, :'out_a2')),
  'P0001|invalid_state', 'decide_flagged_bid past bid_review -> invalid_state');
select tests.act_as(:'office_u');
select is(tests.fl_error(format('select public.send_flags_to_agency(%L)', :'sol')), 'P0001|invalid_state',
  'send_flags_to_agency past bid_review -> invalid_state');
reset role;
select is((select count(*)::int from public.flagged_decisions where solicitation_id = :'sol'), 3,
  'no decision added past bid_review');

-- An automatic non-responsive status hides a flagged bid from the agency: A's signed original is voided.
update public.evaluations set stage = 'bid_review' where solicitation_id = :'sol';
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, voids_entry_id, reason, logged_by)
select r.solicitation_id, r.bid_id, r.reference, r.version, r.item, r.id, 'Logged against the wrong bid', :'office_u'
  from public.bid_original_log r where r.bid_id = :'bid_a' and r.item = 'signed_form';
select tests.act_as(:'author');
select is((select count(*)::int from public.agency_flagged_bids(:'sol')), 0,
  'an automatic non-responsive status takes precedence: the agency no longer sees A');
select is(tests.fl_error(format($q$select public.decide_flagged_bid(%L, 'accept', 'Fine')$q$, :'out_a2')),
  'P0001|invalid_state', 'decide_flagged_bid on an automatically non-responsive bid -> invalid_state');
reset role;

select * from finish();
rollback;
