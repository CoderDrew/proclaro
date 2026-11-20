-- 0022: the recap workflow: prepare, second-person check, post and freeze; the all-rejected memo (slice 2b, Task 9).
begin;

select plan(88);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

-- The error a statement raises, as 'sqlstate|message', or 'ok'.
create function tests.rw_error(p_sql text)
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
grant execute on function tests.rw_error(text) to anon, authenticated, service_role;

-- A closed solicitation (due an hour ago) with two schedule items and no alternates, and the given funding amount.
create function tests.rw_sol(p_agency uuid, p_author uuid, p_funding bigint default 15000000)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select tests.make_published_solicitation(p_agency, p_author, now() - interval '1 hour',
    jsonb_build_object('fundingAmountCents', p_funding, 'schedule', jsonb_build_object(
      'items', jsonb_build_array(jsonb_build_object('name', 'Base bid', 'description', 'Site work'),
                                 jsonb_build_object('name', 'Item 2', 'description', 'Roofing')),
      'alternates', '[]'::jsonb)));
$$;

-- ---------------------------------------------------------------------------
-- Shape and privileges
-- ---------------------------------------------------------------------------
select has_table('public', 'recaps', 'public.recaps exists');
select enum_has_labels('public', 'recap_kind', array['recap', 'all_rejected'], 'recap_kind labels');
select col_is_pk('public', 'recaps', 'solicitation_id', 'recaps: solicitation_id is the primary key');
select policies_are('public', 'recaps', array['recaps_read'], 'recaps: only the recaps_read policy');
select has_function('app', 'was_evaluation_reviewer', array['uuid', 'uuid'], 'app.was_evaluation_reviewer exists');
select has_function('app', 'require_recap_ready', array['uuid', 'timestamptz'], 'app.require_recap_ready exists');
select has_function('app', 'posted_stage', array['jsonb'], 'app.posted_stage exists');
select has_function('public', 'send_recap_to_check', array['uuid'], 'public.send_recap_to_check exists');
select has_function('public', 'disagree_recap', array['uuid', 'text'], 'public.disagree_recap exists');
select has_function('public', 'post_recap', array['uuid'], 'public.post_recap exists');
select has_function('public', 'post_recap_alone', array['uuid'], 'public.post_recap_alone exists');
select has_function('public', 'recap_draft', array['uuid'], 'public.recap_draft exists');
select hasnt_function('app', 'build_recap', array['uuid'], 'the one-argument build_recap is gone (p_now added)');

select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where (n.nspname = 'app' and p.proname in ('was_evaluation_reviewer', 'require_recap_ready'))
               or (n.nspname = 'public' and p.proname in ('send_recap_to_check', 'disagree_recap', 'post_recap',
                                                          'post_recap_alone', 'recap_draft'))),
  'recap workflow functions: security definer with an empty search_path');
select ok(not has_function_privilege('authenticated', 'app.was_evaluation_reviewer(uuid, uuid)', 'execute')
      and not has_function_privilege('anon', 'app.was_evaluation_reviewer(uuid, uuid)', 'execute')
      and not has_function_privilege('service_role', 'app.was_evaluation_reviewer(uuid, uuid)', 'execute')
      and not has_function_privilege('authenticated', 'app.require_recap_ready(uuid, timestamptz)', 'execute')
      and not has_function_privilege('service_role', 'app.require_recap_ready(uuid, timestamptz)', 'execute')
      and not has_function_privilege('authenticated', 'app.posted_stage(jsonb)', 'execute'),
  'app recap workflow helpers: no execute for API roles');
select ok((select bool_and(has_function_privilege('authenticated', f, 'execute')
                           and not has_function_privilege('anon', f, 'execute')
                           and not has_function_privilege('service_role', f, 'execute')
                           and not has_function_privilege('public', f, 'execute'))
             from unnest(array['public.send_recap_to_check(uuid)', 'public.disagree_recap(uuid, text)',
                               'public.post_recap(uuid)', 'public.post_recap_alone(uuid)',
                               'public.recap_draft(uuid)']) f),
  'public recap workflow functions: authenticated only');
select ok(has_table_privilege('anon', 'public.recaps', 'select')
      and has_table_privilege('authenticated', 'public.recaps', 'select')
      and not has_table_privilege('authenticated', 'public.recaps', 'insert')
      and not has_table_privilege('authenticated', 'public.recaps', 'update')
      and not has_table_privilege('authenticated', 'public.recaps', 'delete')
      and not has_table_privilege('anon', 'public.recaps', 'insert')
      and not has_table_privilege('service_role', 'public.recaps', 'select')
      and not has_table_privilege('service_role', 'public.recaps', 'insert'),
  'recaps: select for anon and authenticated only; no write grant for any API role');
select is(app.posted_stage('{"kind": "all_rejected"}'), 'all_rejected'::public.evaluation_stage,
  'posted_stage: memo -> all_rejected');
select is(app.posted_stage('{"kind": "recap"}'), 'recap_posted'::public.evaluation_stage,
  'posted_stage: recap -> recap_posted');

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000009f1', 'RW Office', 'office'),
  ('00000000-0000-0000-0000-0000000009a1', 'RW Agency', 'agency');
\set agency '00000000-0000-0000-0000-0000000009a1'
\set office '00000000-0000-0000-0000-0000000009f1'
select tests.make_user('rw.author@test.test', :'agency') as author \gset
select tests.make_user('rw.r1@test.test', :'office') as r1 \gset
select tests.make_user('rw.r2@test.test', :'office') as r2 \gset
select tests.make_user('rw.r3@test.test', :'office') as r3 \gset
select tests.make_bidder('rw.a@test.test', 'RW Bidder A') as bidder_a \gset
select tests.make_bidder('rw.b@test.test', 'RW Bidder B') as bidder_b \gset
select tests.make_bidder('rw.c@test.test', 'RW Bidder C') as bidder_c \gset

-- sol: three accepted bids. sol_stale: two accepted bids, one later voided. sol_block: a pending cure and an
-- undecided bid. sol_memo (Review Focus 6): funding 99,999,999, bases 100,000,000 and 100,000,001.
select tests.rw_sol(:'agency', :'author') as sol \gset
select tests.rw_sol(:'agency', :'author') as sol_stale \gset
select tests.rw_sol(:'agency', :'author') as sol_block \gset
select tests.rw_sol(:'agency', :'author', 99999999) as sol_memo \gset

select tests.make_closed_bid(:'sol', :'bidder_a', '{3000000,1000000}', '{}', 'paper', null, true, true) as bid_a \gset
select tests.make_closed_bid(:'sol', :'bidder_b', '{3500000,1000000}', '{}', 'paper', null, true, true) as bid_b \gset
select tests.make_closed_bid(:'sol', :'bidder_c', '{4000000,1000000}', '{}', 'paper', null, true, true) as bid_c \gset
select tests.make_closed_bid(:'sol_stale', :'bidder_a', '{3000000,1000000}', '{}', 'paper', null, true, true) as st_a \gset
select tests.make_closed_bid(:'sol_stale', :'bidder_b', '{3500000,1000000}', '{}', 'paper', null, true, true) as st_b \gset
select tests.make_closed_bid(:'sol_block', :'bidder_a', '{3000000,1000000}', '{}', 'paper', null, true, false) as bl_a \gset
select tests.make_closed_bid(:'sol_block', :'bidder_b', '{3500000,1000000}', '{}', 'paper', null, true, true) as bl_b \gset
select tests.make_closed_bid(:'sol_memo', :'bidder_a', '{60000000,40000000}', '{}', 'paper', null, true, true) as m_a \gset
select tests.make_closed_bid(:'sol_memo', :'bidder_b', '{60000000,40000001}', '{}', 'paper', null, true, true) as m_b \gset
select reference as ref_bl_a from public.bids where id = :'bl_a' \gset
select id as st_a_signed from public.bid_original_log where bid_id = :'st_a' and item = 'signed_form' \gset

-- r1 sets every outcome on sol, sol_stale and sol_memo; on sol_block only bid B.
select tests.act_as(:'r1');
select public.set_bid_outcome(:'bid_a', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bid_b', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bid_c', 'accepted', null, 'In order');
select public.set_bid_outcome(:'st_a', 'accepted', null, 'In order');
select public.set_bid_outcome(:'st_b', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bl_b', 'accepted', null, 'In order');
select public.set_bid_outcome(:'m_a', 'accepted', null, 'In order');
select public.set_bid_outcome(:'m_b', 'accepted', null, 'In order');
reset role;

select is(app.was_evaluation_reviewer(:'sol', :'r1'), true, 'was_evaluation_reviewer: r1 set outcomes -> true');
select is(app.was_evaluation_reviewer(:'sol', :'r2'), false, 'was_evaluation_reviewer: r2 has done nothing -> false');
select is(app.was_evaluation_reviewer(:'sol_block', :'r3'), false, 'was_evaluation_reviewer: another solicitation -> false');
select is(tests.rw_error(format('select app.require_recap_ready(%L)', :'sol')), 'ok',
  'require_recap_ready: all bids resolved -> ok');
select is(tests.rw_error(format('select app.require_recap_ready(%L)', :'sol_block')), 'P0001|cure_pending',
  'require_recap_ready: raises the first blocker');

-- ---------------------------------------------------------------------------
-- Review Focus 5: the same person cannot both prepare and check.
-- ---------------------------------------------------------------------------
select tests.act_as(:'r2');
select is(public.recap_draft(:'sol'), null::jsonb, 'recap_draft: nothing under check -> null');
select is(tests.rw_error(format('select public.post_recap(%L)', :'sol')), 'P0001|invalid_state',
  'post_recap in bid_review -> invalid_state');
select is(tests.rw_error(format('select public.disagree_recap(%L, %L)', :'sol', 'x')), 'P0001|invalid_state',
  'disagree_recap in bid_review -> invalid_state');

select tests.act_as(:'r1');
select public.send_recap_to_check(:'sol');
reset role;
select is((select stage::text from public.evaluations where solicitation_id = :'sol'), 'recap_check',
  'r1 send_recap_to_check -> stage recap_check');
select is((select recap_draft from public.evaluations where solicitation_id = :'sol'), app.build_recap(:'sol'),
  'recap_draft = app.build_recap(sol)');
select is((select recap_preparer_id from public.evaluations where solicitation_id = :'sol'), :'r1'::uuid,
  'recap_preparer_id = r1');
select is((select detail from public.bid_audit_log
            where solicitation_id = :'sol' and action = 'send_recap_to_check' and actor_id = :'r1'),
  '{"kind": "recap"}'::jsonb, 'send_recap_to_check audited with {kind}');

select recap_draft as draft from public.evaluations where solicitation_id = :'sol' \gset
select tests.act_as(:'r2');
select is(public.recap_draft(:'sol'), jsonb_build_object('recap', :'draft'::jsonb, 'preparedBy', 'rw.r1@test.test',
                                                          'canCheck', true, 'canRecall', false),
  'recap_draft (office): the draft, the preparer name, and r2 may check (0025)');
select is(tests.rw_error(format('select recap_draft from public.evaluations where solicitation_id = %L', :'sol')),
  '42501|permission denied for table evaluations', 'evaluations.recap_draft has no API grant');

select tests.act_as(:'r1');
select is(tests.rw_error(format('select public.set_bid_outcome(%L, %L, null, %L)', :'bid_a', 'accepted', 'Again')),
  'P0001|invalid_state', 'set_bid_outcome in recap_check -> invalid_state');
select is(tests.rw_error(format('select public.send_recap_to_check(%L)', :'sol')), 'P0001|invalid_state',
  'send_recap_to_check in recap_check -> invalid_state');
select is(tests.rw_error(format('select public.post_recap_alone(%L)', :'sol')), 'P0001|invalid_state',
  'post_recap_alone in recap_check -> invalid_state');
select is(tests.rw_error(format('select public.post_recap(%L)', :'sol')), 'P0001|same_person',
  'r1 (preparer) post_recap -> same_person');
select is(tests.rw_error(format('select public.disagree_recap(%L, %L)', :'sol', 'Looks wrong')), 'P0001|same_person',
  'r1 (preparer) disagree_recap -> same_person');

select tests.act_as(:'r2');
select is(tests.rw_error(format('select public.disagree_recap(%L, %L)', :'sol', '')), 'P0001|comment_required',
  'r2 disagree_recap with a blank comment -> comment_required');
select is(tests.rw_error(format('select public.disagree_recap(%L, %L)', :'sol', '   ')), 'P0001|comment_required',
  'r2 disagree_recap with a whitespace comment -> comment_required');
select public.disagree_recap(:'sol', 'Bid C ground is wrong');
reset role;
select is((select stage::text from public.evaluations where solicitation_id = :'sol'), 'bid_review',
  'r2 disagree_recap -> back to bid_review');
select is((select recap_draft from public.evaluations where solicitation_id = :'sol'), null::jsonb,
  'disagree_recap clears recap_draft');
select is((select detail from public.bid_audit_log
            where solicitation_id = :'sol' and action = 'disagree_recap' and actor_id = :'r2'),
  '{"comment": "Bid C ground is wrong"}'::jsonb, 'disagree_recap audited with {comment}');
select is(app.was_evaluation_reviewer(:'sol', :'r2'), false, 'disagreeing does not make r2 a reviewer');

-- r2 now sets an outcome, so r2 reviewed these bids too.
select tests.act_as(:'r2');
select public.set_bid_outcome(:'bid_c', 'accepted', null, 'Rechecked: ground is fine');
select tests.act_as(:'r1');
select public.send_recap_to_check(:'sol');
select tests.act_as(:'r2');
select is(tests.rw_error(format('select public.post_recap(%L)', :'sol')), 'P0001|same_person',
  'r2 set an outcome -> post_recap same_person');
select is(tests.rw_error(format('select public.disagree_recap(%L, %L)', :'sol', 'Again')), 'P0001|same_person',
  'r2 set an outcome -> disagree_recap same_person');

select tests.act_as(:'r3');
select public.post_recap(:'sol');
reset role;
select is((select count(*)::int from public.recaps where solicitation_id = :'sol'), 1, 'r3 post_recap -> one recaps row');
select is((select row(kind::text, prepared_by, checked_by, single_reviewer)::text from public.recaps
            where solicitation_id = :'sol'),
  row('recap', :'r1'::uuid, :'r3'::uuid, false)::text,
  'recaps row: kind recap, prepared_by r1, checked_by r3, single_reviewer false');
select is((select snapshot from public.recaps where solicitation_id = :'sol'), app.build_recap(:'sol'),
  'recaps snapshot is the checked draft');
select is((select stage::text from public.evaluations where solicitation_id = :'sol'), 'recap_posted',
  'post_recap -> stage recap_posted');
select is((select detail from public.bid_audit_log
            where solicitation_id = :'sol' and action = 'post_recap' and actor_id = :'r3'),
  '{"kind": "recap"}'::jsonb, 'post_recap audited with {kind}');

select tests.act_as(:'r3');
select is(tests.rw_error(format('select public.post_recap(%L)', :'sol')), 'P0001|invalid_state',
  'post_recap after posting -> invalid_state');
select is(tests.rw_error(format('select public.send_recap_to_check(%L)', :'sol')), 'P0001|invalid_state',
  'send_recap_to_check after posting -> invalid_state');
select is(public.recap_draft(:'sol') -> 'preparedBy', '"rw.r1@test.test"'::jsonb,
  'recap_draft after post_recap still returns the checked draft');
reset role;

-- ---------------------------------------------------------------------------
-- The posted row is public, append-only and unique per solicitation.
-- ---------------------------------------------------------------------------
select tests.act_as_anon();
select is((select count(*)::int from public.recaps where solicitation_id = :'sol'), 1, 'anon reads the posted recap');
select tests.act_as(:'bidder_a');
select is((select count(*)::int from public.recaps where solicitation_id = :'sol'), 1, 'a bidder reads the posted recap');

select tests.act_as_anon();
select is(tests.rw_error(format('update public.recaps set single_reviewer = true where solicitation_id = %L', :'sol')),
  '42501|permission denied for table recaps', 'anon cannot update recaps');
select is(tests.rw_error(format('delete from public.recaps where solicitation_id = %L', :'sol')),
  '42501|permission denied for table recaps', 'anon cannot delete recaps');
select tests.act_as(:'r3');
select is(tests.rw_error(format('update public.recaps set single_reviewer = true where solicitation_id = %L', :'sol')),
  '42501|permission denied for table recaps', 'office cannot update recaps');
select is(tests.rw_error(format('delete from public.recaps where solicitation_id = %L', :'sol')),
  '42501|permission denied for table recaps', 'office cannot delete recaps');
select tests.act_as_service_role();
select is(tests.rw_error(format('update public.recaps set single_reviewer = true where solicitation_id = %L', :'sol')),
  '42501|permission denied for table recaps', 'service_role cannot update recaps');
select is(tests.rw_error(format('delete from public.recaps where solicitation_id = %L', :'sol')),
  '42501|permission denied for table recaps', 'service_role cannot delete recaps');
reset role;
select is(tests.rw_error(format('update public.recaps set single_reviewer = true, checked_by = null where solicitation_id = %L', :'sol')),
  'P0001|recaps is append-only: UPDATE is not allowed', 'owner update on recaps -> append-only trigger');
select is(tests.rw_error(format('delete from public.recaps where solicitation_id = %L', :'sol')),
  'P0001|recaps is append-only: DELETE is not allowed', 'owner delete on recaps -> append-only trigger');
select is(tests.rw_error(format(
  'insert into public.recaps (solicitation_id, kind, snapshot, prepared_by, checked_by, single_reviewer) values (%L, %L, %L, %L, null, true)',
  :'sol', 'recap', '{"kind": "recap"}', :'r1')),
  '23505|duplicate key value violates unique constraint "recaps_pkey"', 'a second recap for the same solicitation fails');
select is(tests.rw_error(format(
  'insert into public.recaps (solicitation_id, kind, snapshot, prepared_by, checked_by, single_reviewer) values (%L, %L, %L, %L, %L, true)',
  :'sol_block', 'recap', '{"kind": "recap"}', :'r1', :'r3')),
  '23514|new row for relation "recaps" violates check constraint "recaps_single_reviewer_check"',
  'recaps: single_reviewer must equal (checked_by is null)');

-- ---------------------------------------------------------------------------
-- Stale: a status changes after the draft was frozen. Since 0025 (Ruling 14) void_bid_original refuses outside
-- bid_review, so the change is written directly here, standing in for a race the API no longer allows.
-- ---------------------------------------------------------------------------
select tests.act_as(:'r1');
select public.send_recap_to_check(:'sol_stale');
select is(tests.rw_error(format('select public.void_bid_original(%L, %L)', :'st_a_signed', 'Logged against the wrong bid')),
  'P0001|invalid_state', 'void_bid_original in recap_check -> invalid_state (Ruling 14)');
reset role;
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, voids_entry_id, reason, logged_by)
select solicitation_id, bid_id, reference, version, item, id, 'Logged against the wrong bid', :'r1'
  from public.bid_original_log where id = :'st_a_signed';
select tests.act_as(:'r3');
select is(tests.rw_error(format('select public.post_recap(%L)', :'sol_stale')), 'P0001|recap_stale',
  'a status changed after send -> post_recap recap_stale');
reset role;
select is((select count(*)::int from public.recaps where solicitation_id = :'sol_stale'), 0, 'stale: nothing posted');
select is((select stage::text from public.evaluations where solicitation_id = :'sol_stale'), 'recap_check',
  'stale: stage stays recap_check');

-- ---------------------------------------------------------------------------
-- Readiness: a pending cure, then an undecided bid.
-- ---------------------------------------------------------------------------
select tests.act_as(:'r1');
select is(tests.rw_error(format('select public.send_recap_to_check(%L)', :'sol_block')), 'P0001|cure_pending',
  'send_recap_to_check with a pending cure -> cure_pending');
select is(tests.rw_error(format('select public.post_recap_alone(%L)', :'sol_block')), 'P0001|cure_pending',
  'post_recap_alone with a pending cure -> cure_pending');
select public.log_bid_original(:'sol_block', :'ref_bl_a', 1, 'bid_bond');
select is(tests.rw_error(format('select public.send_recap_to_check(%L)', :'sol_block')), 'P0001|undecided_bids',
  'send_recap_to_check with an undecided bid -> undecided_bids');
reset role;
select is((select stage::text from public.evaluations where solicitation_id = :'sol_block'), 'bid_review',
  'refused sends leave the stage at bid_review');

-- ---------------------------------------------------------------------------
-- Review Focus 6: all bids rejected, posted through the single-reviewer fallback.
-- ---------------------------------------------------------------------------
select tests.act_as(:'r1');
select public.post_recap_alone(:'sol_memo');
reset role;
select is((select kind::text from public.recaps where solicitation_id = :'sol_memo'), 'all_rejected',
  'memo: kind all_rejected');
select is((select snapshot ->> 'reason' from public.recaps where solicitation_id = :'sol_memo'), 'over_funding',
  'memo: reason over_funding');
select is((select snapshot -> 'rows' from public.recaps where solicitation_id = :'sol_memo'), '[]'::jsonb,
  'memo: rows []');
select is((select row(prepared_by, checked_by, single_reviewer)::text from public.recaps
            where solicitation_id = :'sol_memo'),
  row(:'r1'::uuid, null::uuid, true)::text, 'memo: prepared_by r1, no checker, single_reviewer true');
select is((select detail from public.bid_audit_log
            where solicitation_id = :'sol_memo' and action = 'post_recap_alone' and actor_id = :'r1'),
  '{"kind": "all_rejected", "fallback": "no second reviewer available"}'::jsonb,
  'post_recap_alone audited with {kind, fallback}');
select is((select stage::text from public.evaluations where solicitation_id = :'sol_memo'), 'all_rejected',
  'memo: stage all_rejected');
select tests.act_as(:'r2');
select is(tests.rw_error(format('select public.send_recap_to_check(%L)', :'sol_memo')), 'P0001|invalid_state',
  'memo posted: send_recap_to_check -> invalid_state');
select is(tests.rw_error(format('select public.post_recap_alone(%L)', :'sol_memo')), 'P0001|invalid_state',
  'memo posted: post_recap_alone again -> invalid_state');
select tests.act_as_anon();
select is((select (snapshot ->> 'fundingCents')::bigint from public.recaps where solicitation_id = :'sol_memo'),
  99999999::bigint, 'anon reads the posted memo with its funding amount');

-- ---------------------------------------------------------------------------
-- Only the office: agency author, bidder, anon.
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select is(array[
    tests.rw_error(format('select public.send_recap_to_check(%L)', :'sol_block')),
    tests.rw_error(format('select public.disagree_recap(%L, %L)', :'sol_stale', 'x')),
    tests.rw_error(format('select public.post_recap(%L)', :'sol_stale')),
    tests.rw_error(format('select public.post_recap_alone(%L)', :'sol_block')),
    tests.rw_error(format('select public.recap_draft(%L)', :'sol_stale'))],
  array_fill('P0001|not_authorized'::text, array[5]), 'agency author: all four functions and recap_draft -> not_authorized');
select tests.act_as(:'bidder_a');
select is(tests.rw_error(format('select public.recap_draft(%L)', :'sol_stale')), 'P0001|not_authorized',
  'bidder: recap_draft -> not_authorized');
select is(tests.rw_error(format('select public.post_recap(%L)', :'sol_stale')), 'P0001|not_authorized',
  'bidder: post_recap -> not_authorized');
select tests.act_as_anon();
select is(tests.rw_error(format('select public.recap_draft(%L)', :'sol_stale')),
  '42501|permission denied for function recap_draft', 'anon: recap_draft has no execute');
select is(tests.rw_error(format('select public.post_recap(%L)', :'sol_stale')),
  '42501|permission denied for function post_recap', 'anon: post_recap has no execute');
reset role;

select * from finish();
rollback;
