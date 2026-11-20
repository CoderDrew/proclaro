-- 0023: the award: agency pick from the posted recap (reason rules), office posting with a second-person check
-- (slice 2b, Task 10).
begin;

select plan(110);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

-- The error a statement raises, as 'sqlstate|message', or 'ok'.
create function tests.aw_error(p_sql text)
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
grant execute on function tests.aw_error(text) to anon, authenticated, service_role;

-- A closed solicitation (due an hour ago) with two schedule items, one additive alternate and the given funding.
create function tests.aw_sol(p_agency uuid, p_author uuid, p_funding bigint default 15000000)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select tests.make_published_solicitation(p_agency, p_author, now() - interval '1 hour',
    jsonb_build_object('fundingAmountCents', p_funding, 'schedule', jsonb_build_object(
      'items', jsonb_build_array(jsonb_build_object('name', 'Base bid', 'description', 'Site work'),
                                 jsonb_build_object('name', 'Item 2', 'description', 'Roofing')),
      'alternates', jsonb_build_array(jsonb_build_object('kind', 'additive', 'description', 'Canopy')))));
$$;

-- ---------------------------------------------------------------------------
-- Shape and privileges
-- ---------------------------------------------------------------------------
select has_table('public', 'award_picks', 'public.award_picks exists');
select has_table('public', 'awards', 'public.awards exists');
select col_is_pk('public', 'awards', 'solicitation_id', 'awards: solicitation_id is the primary key');
select fk_ok('public', 'awards', 'pick_id', 'public', 'award_picks', 'id', 'awards.pick_id references award_picks');
select policies_are('public', 'awards', array['awards_read'], 'awards: only the awards_read policy');
select policies_are('public', 'award_picks', array[]::name[], 'award_picks: no policy');
select has_function('app', 'posted_recap', array['uuid'], 'app.posted_recap exists');
select has_function('app', 'latest_award_pick', array['uuid'], 'app.latest_award_pick exists');
select has_function('app', 'award_pick_fresh', array['evaluations'], 'app.award_pick_fresh exists');
select hasnt_function('app', 'was_award_preparer', array['uuid', 'uuid'], 'no any-past-sender helper (Ruling 12)');
select has_function('app', 'award_differs', array['jsonb', 'uuid'], 'app.award_differs exists');
select has_function('app', 'build_award', array['jsonb', 'uuid'], 'app.build_award exists');
select has_function('app', 'require_award_checker', array['evaluations'], 'app.require_award_checker exists');

select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where (n.nspname = 'app' and p.proname in ('posted_recap', 'latest_award_pick', 'award_pick_fresh',
                                                       'require_award_checker'))
               or (n.nspname = 'public' and p.proname in ('pick_award', 'current_award_pick', 'award_check_info',
                                                          'send_award_to_check', 'disagree_award', 'post_award',
                                                          'post_award_alone'))),
  'award functions: security definer with an empty search_path');
select ok((select bool_and(not has_function_privilege(r, f, 'execute'))
             from unnest(array['app.posted_recap(uuid)', 'app.latest_award_pick(uuid)',
                               'app.award_pick_fresh(public.evaluations)', 'app.award_differs(jsonb, uuid)',
                               'app.build_award(jsonb, uuid)', 'app.require_award_checker(public.evaluations)']) f
             cross join unnest(array['anon', 'authenticated', 'service_role']) r),
  'app award helpers: no execute for API roles');
select ok((select bool_and(has_function_privilege('authenticated', f, 'execute')
                           and not has_function_privilege('anon', f, 'execute')
                           and not has_function_privilege('service_role', f, 'execute')
                           and not has_function_privilege('public', f, 'execute'))
             from unnest(array['public.pick_award(uuid, uuid, text)', 'public.current_award_pick(uuid)',
                               'public.award_check_info(uuid)', 'public.send_award_to_check(uuid)',
                               'public.disagree_award(uuid, text)', 'public.post_award(uuid)',
                               'public.post_award_alone(uuid)']) f),
  'public award functions: authenticated only');
select ok(has_table_privilege('anon', 'public.awards', 'select')
      and has_table_privilege('authenticated', 'public.awards', 'select')
      and not has_table_privilege('authenticated', 'public.awards', 'insert')
      and not has_table_privilege('authenticated', 'public.awards', 'update')
      and not has_table_privilege('authenticated', 'public.awards', 'delete')
      and not has_table_privilege('anon', 'public.awards', 'insert')
      and not has_table_privilege('service_role', 'public.awards', 'select')
      and not has_table_privilege('service_role', 'public.awards', 'insert'),
  'awards: select for anon and authenticated only; no write grant for any API role');
select ok((select bool_and(not has_table_privilege(r, 'public.award_picks', p))
             from unnest(array['anon', 'authenticated', 'service_role']) r
             cross join unnest(array['select', 'insert', 'update', 'delete']) p),
  'award_picks: no API privileges');
select ok(not has_column_privilege('authenticated', 'public.evaluations', 'award_preparer_id', 'select')
      and not has_column_privilege('authenticated', 'public.evaluations', 'award_disagreed_at', 'select'),
  'evaluations.award_preparer_id and award_disagreed_at have no API grant');

-- Pure helpers.
select is(app.award_differs('{"expectedWinnerBidId": "00000000-0000-0000-0000-000000000001"}',
                            '00000000-0000-0000-0000-000000000002'), true, 'award_differs: another bid -> true');
select is(app.award_differs('{"expectedWinnerBidId": "00000000-0000-0000-0000-000000000001"}',
                            '00000000-0000-0000-0000-000000000001'), false, 'award_differs: the expected winner -> false');
select is(app.award_differs('{"expectedWinnerBidId": null}', '00000000-0000-0000-0000-000000000001'), false,
  'award_differs: tied (no expected winner) -> false');
select is(app.build_award('{"rows": []}', '00000000-0000-0000-0000-000000000001'), null::jsonb,
  'build_award: a bid not in the rows -> null');

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000af1', 'AW Office', 'office'),
  ('00000000-0000-0000-0000-000000000aa1', 'AW Agency', 'agency'),
  ('00000000-0000-0000-0000-000000000aa2', 'AW Other Agency', 'agency');
\set agency '00000000-0000-0000-0000-000000000aa1'
\set agency2 '00000000-0000-0000-0000-000000000aa2'
\set office '00000000-0000-0000-0000-000000000af1'
select tests.make_user('aw.author@test.test', :'agency') as author \gset
select tests.make_user('aw.other@test.test', :'agency2') as other_agency \gset
select tests.make_user('aw.r1@test.test', :'office') as r1 \gset
select tests.make_user('aw.r2@test.test', :'office') as r2 \gset
select tests.make_bidder('aw.a@test.test', 'AW Bidder A') as bidder_a \gset
select tests.make_bidder('aw.b@test.test', 'AW Bidder B') as bidder_b \gset
select tests.make_bidder('aw.c@test.test', 'AW Bidder C') as bidder_c \gset
select tests.make_bidder('aw.d@test.test', 'AW Bidder D') as bidder_d \gset

-- sol: A rank 1 (expected winner), B rank 2, C withdrawn, D non-responsive; alternate 1 is selected.
-- sol_tie: A and B tied at rank 1. sol_alone: A rank 1, B rank 2 (fallback). sol_memo: all bids over funding.
select tests.aw_sol(:'agency', :'author') as sol \gset
select tests.aw_sol(:'agency', :'author') as sol_tie \gset
select tests.aw_sol(:'agency', :'author') as sol_alone \gset
select tests.aw_sol(:'agency', :'author', 99999999) as sol_memo \gset

select tests.make_closed_bid(:'sol', :'bidder_a', '{3000000,1000000}', '{500000}', 'paper', null, true, true) as bid_a \gset
select tests.make_closed_bid(:'sol', :'bidder_b', '{3500000,1000000}', '{600000}', 'paper', null, true, true) as bid_b \gset
select tests.make_closed_bid(:'sol', :'bidder_c', '{2000000,1000000}', '{100000}', 'paper', null, true, true) as bid_c \gset
select tests.make_closed_bid(:'sol', :'bidder_d', '{2500000,1000000}', '{100000}', 'paper', null, true, true) as bid_d \gset
insert into public.bid_withdrawals (bid_id, version, withdrawn_by) values (:'bid_c', 1, :'bidder_c');
select reference as ref_b from public.bids where id = :'bid_b' \gset
select tests.make_closed_bid(:'sol_tie', :'bidder_a', '{3000000,1000000}', '{500000}', 'paper', null, true, true) as tie_a \gset
select tests.make_closed_bid(:'sol_tie', :'bidder_b', '{3000000,1000000}', '{500000}', 'paper', null, true, true) as tie_b \gset
select tests.make_closed_bid(:'sol_alone', :'bidder_a', '{3000000,1000000}', '{500000}', 'paper', null, true, true) as al_a \gset
select tests.make_closed_bid(:'sol_alone', :'bidder_b', '{3500000,1000000}', '{600000}', 'paper', null, true, true) as al_b \gset
select tests.make_closed_bid(:'sol_memo', :'bidder_a', '{60000000,40000000}', '{0}', 'paper', null, true, true) as m_a \gset

select tests.act_as(:'r1');
select public.set_bid_outcome(:'bid_a', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bid_b', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bid_d', 'non_responsive', 'wrong_form', 'Wrong bid form');
select public.set_bid_outcome(:'tie_a', 'accepted', null, 'In order');
select public.set_bid_outcome(:'tie_b', 'accepted', null, 'In order');
select public.set_bid_outcome(:'al_a', 'accepted', null, 'In order');
select public.set_bid_outcome(:'al_b', 'accepted', null, 'In order');
select public.set_bid_outcome(:'m_a', 'accepted', null, 'In order');

-- Before the recap is posted (bid_review), nobody can pick.
select tests.act_as(:'author');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol', :'bid_a')), 'P0001|invalid_state',
  'pick_award in bid_review -> invalid_state');
select is((select count(*)::int from public.current_award_pick(:'sol')), 0, 'current_award_pick: no pick -> no row');

-- Post the recaps (fallback, for fixture brevity) and the memo.
select tests.act_as(:'r1');
select public.post_recap_alone(:'sol');
select public.post_recap_alone(:'sol_tie');
select public.post_recap_alone(:'sol_alone');
select public.post_recap_alone(:'sol_memo');
reset role;

select snapshot as recap from public.recaps where solicitation_id = :'sol' \gset
select is(:'recap'::jsonb ->> 'expectedWinnerBidId', :'bid_a', 'fixture: A is the expected winner');
select is(:'recap'::jsonb -> 'selectedAlternates', '[1]'::jsonb, 'fixture: alternate 1 is selected');
select is(jsonb_array_length(:'recap'::jsonb -> 'rows'), 2, 'fixture: only A and B are recap rows');
select is((select snapshot ->> 'expectedWinnerBidId' from public.recaps where solicitation_id = :'sol_tie'), null,
  'fixture: tied rank 1 -> no expected winner');
select is(app.posted_recap(:'sol'), :'recap'::jsonb, 'posted_recap: the posted snapshot');
select is(app.posted_recap(:'sol_memo'), null::jsonb, 'posted_recap: the memo -> null');
select is(app.build_award(:'recap'::jsonb, :'bid_b') ->> 'amountCents',
  (select r ->> 'totalCents' from jsonb_array_elements(:'recap'::jsonb -> 'rows') r where r ->> 'bidId' = :'bid_b'),
  'build_award: amountCents is the row totalCents');

-- ---------------------------------------------------------------------------
-- Reason rules
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol', :'bid_a')), 'ok',
  'pick_award: the expected winner with no reason -> ok');
select is((select row(bid_id, reason, differs_from_expected)::text from public.current_award_pick(:'sol')),
  row(:'bid_a'::uuid, null::text, false)::text, 'current_award_pick: A, no reason, does not differ');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol', :'bid_b')), 'P0001|reason_required',
  'pick_award: another bid with no reason -> reason_required');
select is(tests.aw_error(format('select public.pick_award(%L, %L, %L)', :'sol', :'bid_b', '   ')), 'P0001|reason_required',
  'pick_award: another bid with a blank reason -> reason_required');
select is(tests.aw_error(format('select public.pick_award(%L, %L, %L)', :'sol', :'bid_c', 'x')), 'P0001|not_in_recap',
  'pick_award: a withdrawn bid -> not_in_recap');
select is(tests.aw_error(format('select public.pick_award(%L, %L, %L)', :'sol', :'bid_d', 'x')), 'P0001|not_in_recap',
  'pick_award: a non-responsive bid -> not_in_recap');
select is(tests.aw_error(format('select public.pick_award(%L, %L, %L)', :'sol', :'tie_a', 'x')), 'P0001|not_in_recap',
  'pick_award: a bid of another solicitation -> not_in_recap');
select is(tests.aw_error(format('select public.pick_award(%L, null, %L)', :'sol', 'x')), 'P0001|not_in_recap',
  'pick_award: no bid -> not_in_recap');
select is(tests.aw_error(format('select public.pick_award(%L, %L, %L)', :'sol', :'bid_b', ' A cannot meet the start date ')),
  'ok', 'pick_award: B with a reason -> ok');
select is((select row(bid_id, reason, differs_from_expected)::text from public.current_award_pick(:'sol')),
  row(:'bid_b'::uuid, 'A cannot meet the start date', true)::text,
  'current_award_pick: B (the latest pick), with its reason, differs from expected');
select is((select reference from public.current_award_pick(:'sol')), :'ref_b', 'current_award_pick: the reference');
reset role;
select is((select detail from public.bid_audit_log
            where solicitation_id = :'sol' and action = 'pick_award' and bid_id = :'bid_b'),
  jsonb_build_object('bid_id', :'bid_b'::uuid, 'reason', 'A cannot meet the start date', 'differs_from_expected', true),
  'pick_award audited with {bid_id, reason, differs_from_expected}');
select is((select count(*)::int from public.award_picks where solicitation_id = :'sol'), 2,
  'two picks kept (append-only)');

-- Tied fixture: any pick needs a reason.
select tests.act_as(:'author');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol_tie', :'tie_a')), 'P0001|reason_required',
  'tied rank 1: pick_award with no reason -> reason_required');
select is(tests.aw_error(format('select public.pick_award(%L, %L, %L)', :'sol_tie', :'tie_a', 'Earlier start date')), 'ok',
  'tied rank 1: pick_award with a reason -> ok');
select is((select differs_from_expected from public.current_award_pick(:'sol_tie')), false,
  'tied rank 1: the pick does not differ (there is no expected winner)');

-- Only the owning agency picks; the office or the owning agency reads.
select tests.act_as(:'other_agency');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol', :'bid_a')), 'P0001|not_authorized',
  'another agency: pick_award -> not_authorized');
select is(tests.aw_error(format('select * from public.current_award_pick(%L)', :'sol')), 'P0001|not_authorized',
  'another agency: current_award_pick -> not_authorized');
select tests.act_as(:'bidder_a');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol', :'bid_a')), 'P0001|not_authorized',
  'bidder: pick_award -> not_authorized');
select is(tests.aw_error(format('select * from public.current_award_pick(%L)', :'sol')), 'P0001|not_authorized',
  'bidder: current_award_pick -> not_authorized');
select tests.act_as(:'r1');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol', :'bid_a')), 'P0001|not_authorized',
  'office: pick_award -> not_authorized');
select is((select bid_id from public.current_award_pick(:'sol')), :'bid_b'::uuid, 'office reads the current pick');
select tests.act_as_anon();
select is(tests.aw_error(format('select * from public.current_award_pick(%L)', :'sol')),
  '42501|permission denied for function current_award_pick', 'anon: current_award_pick has no execute');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol', :'bid_a')),
  '42501|permission denied for function pick_award', 'anon: pick_award has no execute');

-- ---------------------------------------------------------------------------
-- Review Focus 5: the person who sent the award to check cannot post or disagree.
-- ---------------------------------------------------------------------------
select tests.act_as(:'r2');
select is(tests.aw_error(format('select public.post_award(%L)', :'sol')), 'P0001|invalid_state',
  'post_award in recap_posted -> invalid_state');
select is(tests.aw_error(format('select public.disagree_award(%L, %L)', :'sol', 'x')), 'P0001|invalid_state',
  'disagree_award in recap_posted -> invalid_state');
select is((select row(prepared_by, can_check, needs_new_pick)::text from public.award_check_info(:'sol')),
  row(null::text, false, false)::text, 'award_check_info in recap_posted: no preparer, cannot check, no new pick needed');

select tests.act_as(:'r1');
select public.send_award_to_check(:'sol');
reset role;
select is((select stage::text from public.evaluations where solicitation_id = :'sol'), 'award_check',
  'r1 send_award_to_check -> award_check');
select is((select award_preparer_id from public.evaluations where solicitation_id = :'sol'), :'r1'::uuid,
  'award_preparer_id = r1');
select is(app.award_pick_fresh((select e from public.evaluations e where e.solicitation_id = :'sol')), true,
  'award_pick_fresh: a pick and no disagreement -> true');
select is((select detail ->> 'bid_id' from public.bid_audit_log
            where solicitation_id = :'sol' and action = 'send_award_to_check' and actor_id = :'r1'),
  :'bid_b', 'send_award_to_check audited with the picked bid');

select tests.act_as(:'author');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol', :'bid_a')), 'P0001|invalid_state',
  'pick_award in award_check -> invalid_state');

select tests.act_as(:'r1');
select is((select row(prepared_by, can_check)::text from public.award_check_info(:'sol')),
  row('aw.r1@test.test', false)::text, 'award_check_info (r1): prepared by r1, cannot check');
select is(tests.aw_error(format('select public.post_award(%L)', :'sol')), 'P0001|same_person',
  'r1 (sender) post_award -> same_person');
select is(tests.aw_error(format('select public.disagree_award(%L, %L)', :'sol', 'Looks wrong')), 'P0001|same_person',
  'r1 (sender) disagree_award -> same_person');
select is(tests.aw_error(format('select public.send_award_to_check(%L)', :'sol')), 'P0001|invalid_state',
  'send_award_to_check in award_check -> invalid_state');
select is(tests.aw_error(format('select public.post_award_alone(%L)', :'sol')), 'P0001|invalid_state',
  'post_award_alone in award_check -> invalid_state');

select tests.act_as(:'r2');
select is((select can_check from public.award_check_info(:'sol')), true, 'award_check_info (r2): can check');
select is(tests.aw_error(format('select public.disagree_award(%L, %L)', :'sol', '  ')), 'P0001|comment_required',
  'r2 disagree_award with a blank comment -> comment_required');
select public.disagree_award(:'sol', 'Confirm the start date with the agency');
reset role;
select is((select stage::text from public.evaluations where solicitation_id = :'sol'), 'recap_posted',
  'r2 disagree_award -> back to recap_posted');
select is((select detail from public.bid_audit_log
            where solicitation_id = :'sol' and action = 'disagree_award' and actor_id = :'r2'),
  '{"comment": "Confirm the start date with the agency"}'::jsonb, 'disagree_award audited with {comment}');

-- Ruling 11 (scenario a): the rejected pick can be neither re-sent nor posted alone.
select tests.act_as(:'r1');
select is((select needs_new_pick from public.award_check_info(:'sol')), true,
  'award_check_info after disagree: needs_new_pick');
select is(tests.aw_error(format('select public.post_award_alone(%L)', :'sol')), 'P0001|invalid_state',
  'after disagree, post_award_alone with the rejected pick -> invalid_state');
select is(tests.aw_error(format('select public.send_award_to_check(%L)', :'sol')), 'P0001|invalid_state',
  'after disagree, send_award_to_check with the rejected pick -> invalid_state');
reset role;
select is(app.award_pick_fresh((select e from public.evaluations e where e.solicitation_id = :'sol')), false,
  'award_pick_fresh: no pick since the disagreement -> false');
select is((select count(*)::int from public.awards where solicitation_id = :'sol'), 0, 'refused: nothing posted');
select is((select stage::text from public.evaluations where solicitation_id = :'sol'), 'recap_posted',
  'refused: stage stays recap_posted');
select tests.act_as(:'author');
select public.pick_award(:'sol', :'bid_b', 'Start date confirmed: A still cannot start');
select tests.act_as(:'r1');
select is((select needs_new_pick from public.award_check_info(:'sol')), false,
  'award_check_info after a new pick: no new pick needed');

-- Ruling 12 (scenario b): two office users finish. r1 sent round 1 and r2 disagreed; r2 sends round 2, r1 checks.
select tests.act_as(:'r2');
select public.send_award_to_check(:'sol');
select is(tests.aw_error(format('select public.post_award(%L)', :'sol')), 'P0001|same_person',
  'r2 (current sender) post_award -> same_person');
select is(tests.aw_error(format('select public.disagree_award(%L, %L)', :'sol', 'x')), 'P0001|same_person',
  'r2 (current sender) disagree_award -> same_person');
select tests.act_as(:'r1');
select is((select row(prepared_by, can_check)::text from public.award_check_info(:'sol')),
  row('aw.r2@test.test', true)::text, 'award_check_info (r1, an earlier sender): can check round 2');
select public.post_award(:'sol');
reset role;
select is((select stage::text from public.evaluations where solicitation_id = :'sol'), 'awarded',
  'r1 (earlier-round sender) post_award -> stage awarded');
select is((select (snapshot ->> 'amountCents')::bigint from public.awards where solicitation_id = :'sol'),
  (select (r ->> 'totalCents')::bigint from jsonb_array_elements(:'recap'::jsonb -> 'rows') r where r ->> 'bidId' = :'bid_b'),
  'awards.snapshot amountCents = the recap row totalCents for B');
select is((select (snapshot ->> 'amountCents')::bigint from public.awards where solicitation_id = :'sol'), 5100000::bigint,
  'B amount: base 4,500,000 plus selected alternate 600,000');
select is((select snapshot from public.awards where solicitation_id = :'sol'),
  jsonb_build_object('bidId', :'bid_b', 'reference', (select reference from public.bids where id = :'bid_b'),
    'bidderName', 'AW Bidder B', 'amountCents', 5100000, 'selectedAlternates', '[1]'::jsonb,
    'alternates', '[{"kind": "additive", "description": "Canopy"}]'::jsonb, 'expectedWinnerBidId', :'bid_a',
    'differsFromExpected', true),
  'awards snapshot: the names.md shape');
select is((select snapshot ? 'reason' from public.awards where solicitation_id = :'sol'), false,
  'awards snapshot has no reason key');
select is((select row(bid_id, prepared_by, checked_by, single_reviewer)::text from public.awards
            where solicitation_id = :'sol'),
  row(:'bid_b'::uuid, :'r2'::uuid, :'r1'::uuid, false)::text,
  'awards row: bid B, prepared_by r2 (round 2 sender), checked_by r1, single_reviewer false');
select is((select pick_id from public.awards where solicitation_id = :'sol'),
  (select id from app.latest_award_pick(:'sol')), 'awards.pick_id is the latest pick');

-- ---------------------------------------------------------------------------
-- pick_required and the single-reviewer fallback.
-- ---------------------------------------------------------------------------
select tests.act_as(:'r1');
select is(tests.aw_error(format('select public.send_award_to_check(%L)', :'sol_alone')), 'P0001|pick_required',
  'send_award_to_check with no pick -> pick_required');
select is(tests.aw_error(format('select public.post_award_alone(%L)', :'sol_alone')), 'P0001|pick_required',
  'post_award_alone with no pick -> pick_required');
select tests.act_as(:'author');
select public.pick_award(:'sol_alone', :'al_a', null);
select tests.act_as(:'r1');
select public.post_award_alone(:'sol_alone');
reset role;
select is((select row(bid_id, prepared_by, checked_by, single_reviewer)::text from public.awards
            where solicitation_id = :'sol_alone'),
  row(:'al_a'::uuid, :'r1'::uuid, null::uuid, true)::text, 'post_award_alone: single_reviewer true, no checker');
select is((select stage::text from public.evaluations where solicitation_id = :'sol_alone'), 'awarded',
  'post_award_alone -> awarded');
select is((select detail ->> 'fallback' from public.bid_audit_log
            where solicitation_id = :'sol_alone' and action = 'post_award_alone' and actor_id = :'r1'),
  'no second reviewer available', 'post_award_alone audited with the fallback');
select is((select snapshot ->> 'differsFromExpected' from public.awards where solicitation_id = :'sol_alone'), 'false',
  'post_award_alone: the expected winner does not differ');

-- The memo: nothing to award.
select tests.act_as(:'author');
select is(tests.aw_error(format('select public.pick_award(%L, %L, null)', :'sol_memo', :'m_a')), 'P0001|invalid_state',
  'all_rejected: pick_award -> invalid_state');
select tests.act_as(:'r1');
select is(tests.aw_error(format('select public.send_award_to_check(%L)', :'sol_memo')), 'P0001|invalid_state',
  'all_rejected: send_award_to_check -> invalid_state');

-- Only the office runs the posting steps.
select tests.act_as(:'author');
select is(array[
    tests.aw_error(format('select public.send_award_to_check(%L)', :'sol_tie')),
    tests.aw_error(format('select public.disagree_award(%L, %L)', :'sol_tie', 'x')),
    tests.aw_error(format('select public.post_award(%L)', :'sol_tie')),
    tests.aw_error(format('select public.post_award_alone(%L)', :'sol_tie')),
    tests.aw_error(format('select * from public.award_check_info(%L)', :'sol_tie'))],
  array_fill('P0001|not_authorized'::text, array[5]), 'agency author: office award functions -> not_authorized');
select tests.act_as(:'bidder_a');
select is(tests.aw_error(format('select public.post_award_alone(%L)', :'sol_tie')), 'P0001|not_authorized',
  'bidder: post_award_alone -> not_authorized');

-- ---------------------------------------------------------------------------
-- The posted award is public; both tables are append-only.
-- ---------------------------------------------------------------------------
select tests.act_as_anon();
select is((select count(*)::int from public.awards where solicitation_id = :'sol'), 1, 'anon reads the awards row');
select is((select snapshot ->> 'bidId' from public.awards where solicitation_id = :'sol'), :'bid_b',
  'anon reads the awarded bid');
select is(tests.aw_error(format('select count(*) from public.award_picks where solicitation_id = %L', :'sol')),
  '42501|permission denied for table award_picks', 'anon cannot read award_picks');
select is(tests.aw_error(format('delete from public.awards where solicitation_id = %L', :'sol')),
  '42501|permission denied for table awards', 'anon cannot delete awards');
select tests.act_as(:'r2');
select is(tests.aw_error(format('update public.awards set single_reviewer = true where solicitation_id = %L', :'sol')),
  '42501|permission denied for table awards', 'office cannot update awards');
select is(tests.aw_error(format('select count(*) from public.award_picks where solicitation_id = %L', :'sol')),
  '42501|permission denied for table award_picks', 'office cannot read award_picks directly');
select tests.act_as_service_role();
select is(tests.aw_error(format('delete from public.award_picks where solicitation_id = %L', :'sol')),
  '42501|permission denied for table award_picks', 'service_role cannot delete award_picks');
reset role;
select is(tests.aw_error(format('update public.awards set single_reviewer = true, checked_by = null where solicitation_id = %L', :'sol')),
  'P0001|awards is append-only: UPDATE is not allowed', 'owner update on awards -> append-only trigger');
select is(tests.aw_error(format('delete from public.award_picks where solicitation_id = %L', :'sol')),
  'P0001|award_picks is append-only: DELETE is not allowed', 'owner delete on award_picks -> append-only trigger');
select is(tests.aw_error(format('update public.award_picks set reason = %L where solicitation_id = %L', 'x', :'sol')),
  'P0001|award_picks is append-only: UPDATE is not allowed', 'owner update on award_picks -> append-only trigger');

select * from finish();
rollback;
