-- 0032: questions and answers. public.questions (RLS: the asker's org or the office), public.addendum_answers (no
-- grants), ask_question, my_questions, office_questions, agency_questions, close_question, save_addendum_answer,
-- remove_addendum_answer, addendum_answers_draft, published_answers, and publish_addendum marking questions answered.
-- Pins Review Focus 4 (question identity can't leak) and 6 (the questions deadline moves with an addendum).
begin;

select plan(121);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000004d1', 'QA Office', 'office'),
  ('00000000-0000-0000-0000-0000000004d2', 'QA Agency', 'agency'),
  ('00000000-0000-0000-0000-0000000004d3', 'QA Other Agency', 'agency');

select tests.make_user('qa.author@test.test', '00000000-0000-0000-0000-0000000004d2') as author \gset
select tests.make_user('qa.other@test.test',  '00000000-0000-0000-0000-0000000004d3') as other_agency \gset
select tests.make_user('qa.r1@test.test',     '00000000-0000-0000-0000-0000000004d1') as r1 \gset
select tests.make_user('qa.r2@test.test',     '00000000-0000-0000-0000-0000000004d1') as r2 \gset
select tests.make_bidder('qa.a@test.test', 'QA Bidder A') as bidder_a \gset
select tests.make_bidder('qa.b@test.test', 'QA Bidder B') as bidder_b \gset
select org_id as org_a from public.profiles where user_id = :'bidder_a' \gset
-- A second user in A's organization (bidder-org profiles are guarded: set the flag register_bidder sets).
select set_config('app.registering', :'org_a', true);
select tests.make_user('qa.a2@test.test', :'org_a') as bidder_a2 \gset
select set_config('app.registering', '', true);

-- Test-only helper (rolled back): publish an approved addendum as the calling office user, with the paths, snapshot
-- and due time publish_addendum expects.
create function tests.t7_publish(p_addendum uuid)
returns int
language plpgsql
as $$
declare
  v_add public.addenda;
  v_n   int;
begin
  select * into v_add from public.addenda where id = p_addendum;
  v_n := v_add.number + 1;
  perform tests.stage_version_files(v_add.solicitation_id, v_n);
  return public.publish_addendum(
    p_addendum,
    format('solicitations/%s/v%s/rfb.pdf', v_add.solicitation_id, v_n),
    format('solicitations/%s/v%s/bid-form.pdf', v_add.solicitation_id, v_n),
    format('solicitations/%s/v%s/addendum.pdf', v_add.solicitation_id, v_n),
    jsonb_build_object('data', v_add.data - 'fundingAmountCents', 'clauses', '{}'::jsonb, 'settings', '{}'::jsonb),
    tests.bid_due_at(v_add.data),
    (v_add.data ->> 'fundingAmountCents')::bigint);
end;
$$;
grant execute on function tests.t7_publish(uuid) to authenticated;

-- ===========================================================================
-- Schema objects and grants
-- ===========================================================================
select has_type('public', 'question_status', 'question_status exists');
select enum_has_labels('public', 'question_status', array['open', 'answered', 'closed'], 'question_status labels');
select enum_has_labels('public', 'question_close_reason', array['duplicate', 'out_of_scope'],
  'question_close_reason labels');
select has_table('public', 'questions', 'questions exists');
select has_table('public', 'addendum_answers', 'addendum_answers exists');
select col_is_pk('public', 'addendum_answers', array['addendum_id', 'question_id'],
  'addendum_answers primary key is (addendum_id, question_id)');
select fk_ok('public', 'addendum_answers', 'question_id', 'public', 'questions', 'id',
  'addendum_answers.question_id references questions');
select fk_ok('public', 'questions', 'answered_in', 'public', 'addenda', 'id', 'questions.answered_in references addenda');
select col_not_null('public', 'questions', 'asked_by', 'questions.asked_by is not null');
select col_not_null('public', 'questions', 'org_id', 'questions.org_id is not null');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.questions'::regclass)
      and (select c.relrowsecurity from pg_class c where c.oid = 'public.addendum_answers'::regclass),
  'RLS is on for questions and addendum_answers');
select policies_are('public', 'questions', array['questions_read'], 'questions has only the read policy');
select ok(has_table_privilege('authenticated', 'public.questions', 'select')
      and not has_table_privilege('authenticated', 'public.questions', 'insert')
      and not has_table_privilege('authenticated', 'public.questions', 'update')
      and not has_table_privilege('authenticated', 'public.questions', 'delete'),
  'questions: authenticated may select, never write');
select ok(not has_table_privilege('anon', 'public.questions', 'select')
      and not has_table_privilege('service_role', 'public.questions', 'select')
      and not has_table_privilege('service_role', 'public.questions', 'insert'),
  'questions: no grant to anon or service_role (Review Focus 4)');
select ok(not has_table_privilege('authenticated', 'public.addendum_answers', 'select')
      and not has_table_privilege('authenticated', 'public.addendum_answers', 'insert')
      and not has_table_privilege('anon', 'public.addendum_answers', 'select')
      and not has_table_privilege('service_role', 'public.addendum_answers', 'select'),
  'addendum_answers: no direct grants to any API role');
select is(
  (select count(*)::int from pg_proc p
    where p.oid in ('public.ask_question(uuid, text, text)'::regprocedure,
                    'public.my_questions(uuid)'::regprocedure,
                    'public.office_questions(uuid)'::regprocedure,
                    'public.agency_questions(uuid)'::regprocedure,
                    'public.close_question(uuid, public.question_close_reason)'::regprocedure,
                    'public.save_addendum_answer(uuid, uuid, text, text)'::regprocedure,
                    'public.remove_addendum_answer(uuid, uuid)'::regprocedure,
                    'public.addendum_answers_draft(uuid)'::regprocedure,
                    'public.published_answers(uuid)'::regprocedure,
                    'public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)'::regprocedure)
      and p.prosecdef and p.proconfig @> array['search_path=""']),
  10, 'every 0032 function is security definer with an empty search_path');
select ok(has_function_privilege('authenticated', 'public.ask_question(uuid, text, text)', 'execute')
      and has_function_privilege('authenticated', 'public.my_questions(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.office_questions(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.agency_questions(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.close_question(uuid, public.question_close_reason)', 'execute')
      and has_function_privilege('authenticated', 'public.save_addendum_answer(uuid, uuid, text, text)', 'execute')
      and has_function_privilege('authenticated', 'public.remove_addendum_answer(uuid, uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.addendum_answers_draft(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.published_answers(uuid)', 'execute'),
  'authenticated executes every public 0032 function');
select ok(has_function_privilege('anon', 'public.published_answers(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.ask_question(uuid, text, text)', 'execute')
      and not has_function_privilege('anon', 'public.my_questions(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.office_questions(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.agency_questions(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.addendum_answers_draft(uuid)', 'execute')
      and not has_function_privilege('service_role', 'public.ask_question(uuid, text, text)', 'execute')
      and not has_function_privilege('service_role', 'public.published_answers(uuid)', 'execute'),
  'anon executes only published_answers; service_role none');

-- Review Focus 4: no identity columns in agency_questions, no body in published_answers (the functions' results).
create view tests.t7_agency_questions as select * from public.agency_questions(null::uuid);
create view tests.t7_published_answers as select * from public.published_answers(null::uuid);
select columns_are('tests', 't7_agency_questions',
  array['id', 'body', 'reference', 'asked_at', 'status', 'answered_in_number', 'in_draft'],
  'agency_questions returns exactly id, body, reference, asked_at, status, answered_in_number, in_draft');
select hasnt_column('tests', 't7_agency_questions', 'asked_by', 'agency_questions has no asked_by');
select hasnt_column('tests', 't7_agency_questions', 'org_id', 'agency_questions has no org_id');
select hasnt_column('tests', 't7_agency_questions', 'org_name', 'agency_questions has no org_name');
select columns_are('tests', 't7_published_answers', array['addendum_number', 'published_question', 'answer'],
  'published_answers returns exactly addendum_number, published_question, answer');
select hasnt_column('tests', 't7_published_answers', 'body', 'published_answers has no body');

-- ===========================================================================
-- Fixtures
--   s1: main board (questionsDue today + 14).
--   s2: questionsDue yesterday; approved addendum 1 moves it to today + 14 (Review Focus 6).
--   s3 / s4: questionsDue 30 minutes after / before the wall clock, written in settings.timezone.
--   s5: bids closed.
-- ===========================================================================
select timezone as tz from public.settings where id = 1 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000004d2', :'author',
  now() + interval '20 days') as s1 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000004d2', :'author',
  now() + interval '20 days',
  jsonb_build_object('questionsDue', jsonb_build_object('date', to_char(app.today() - 1, 'YYYY-MM-DD'),
                                                        'time', '13:00'))) as s2 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000004d2', :'author',
  now() + interval '20 days',
  jsonb_build_object('questionsDue', jsonb_build_object(
    'date', to_char((clock_timestamp() + interval '30 minutes') at time zone :'tz', 'YYYY-MM-DD'),
    'time', to_char((clock_timestamp() + interval '30 minutes') at time zone :'tz', 'HH24:MI')))) as s3 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000004d2', :'author',
  now() + interval '20 days',
  jsonb_build_object('questionsDue', jsonb_build_object(
    'date', to_char((clock_timestamp() - interval '30 minutes') at time zone :'tz', 'YYYY-MM-DD'),
    'time', to_char((clock_timestamp() - interval '30 minutes') at time zone :'tz', 'HH24:MI')))) as s4 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000004d2', :'author',
  now() + interval '20 days') as s5 \gset
select tests.set_bid_due(:'s5', now() - interval '1 minute');

insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path, bid_due_at)
select s.id, 1, s.published_snapshot, format('solicitations/%s/v1/rfb.pdf', s.id),
       format('solicitations/%s/v1/bid-form.pdf', s.id), s.bid_due_at
  from public.solicitations s where s.id in (:'s1', :'s2');

insert into public.addenda (solicitation_id, number, state, data, narrative, created_by, reviewer_id, checker_id)
select s.id, 1, 'approved',
       s.data || jsonb_build_object(
         'fundingAmountCents', 15000000,
         'questionsDue', jsonb_build_object('date', to_char(app.today() + 14, 'YYYY-MM-DD'), 'time', '13:00')),
       'Extends the questions deadline.', :'author', :'r1', :'r2'
  from public.solicitations s where s.id = :'s2'
returning id as add_s2 \gset

-- ===========================================================================
-- ask_question
-- ===========================================================================
select tests.act_as(:'bidder_a');
select public.ask_question(:'s1', '  Is the canopy steel? Asked by Acme Roofing.  ', ' Item 2 ') as q1 \gset
select public.ask_question(:'s1', 'Duplicate of the canopy question.', '') as q3 \gset
select public.ask_question(:'s1', 'What is the paving depth?', null) as q4 \gset
select tests.act_as(:'bidder_b');
select public.ask_question(:'s1', 'Bidder B private question.', 'Section 02 41 00') as q2 \gset

reset role;
select is((select body from public.questions where id = :'q1'), 'Is the canopy steel? Asked by Acme Roofing.',
  'ask_question stores the trimmed body');
select is((select reference from public.questions where id = :'q1'), 'Item 2', 'and the trimmed reference');
select is((select reference from public.questions where id = :'q4'), '', 'a null reference is stored as empty');
select ok((select asked_by = :'bidder_a'::uuid and org_id = :'org_a'::uuid and status = 'open'
             from public.questions where id = :'q1'),
  'asked_by and org_id are the caller''s; status starts open');

select tests.act_as(:'bidder_a');
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s1', '   ', ''), 'P0001', 'invalid_question',
  'an empty body raises invalid_question');
select throws_ok(format('select public.ask_question(%L, null, %L)', :'s1', ''), 'P0001', 'invalid_question',
  'a null body raises invalid_question');
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s1', repeat('x', 4001), ''), 'P0001',
  'invalid_question', 'a 4001-character body raises invalid_question');
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s1', 'Fine.', repeat('r', 201)), 'P0001',
  'invalid_question', 'a 201-character reference raises invalid_question');
select lives_ok(format('select public.ask_question(%L, %L, %L)', :'s1', repeat('x', 4000), repeat('r', 200)),
  'a 4000-character body and a 200-character reference are accepted');
select throws_ok(format('select public.ask_question(%L, %L, %L)', gen_random_uuid(), 'Q?', ''), 'P0001', 'not_open',
  'an unknown solicitation raises not_open');
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s5', 'Q?', ''), 'P0001', 'questions_closed',
  'bids closed raises questions_closed');

select tests.act_as(:'author');
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s1', 'Q?', ''), 'P0001', 'not_authorized',
  'an agency user calling ask_question raises not_authorized');
select tests.act_as(:'r1');
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s1', 'Q?', ''), 'P0001', 'not_authorized',
  'an office user calling ask_question raises not_authorized');
select tests.act_as_anon();
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s1', 'Q?', ''), '42501', null,
  'anon cannot call ask_question');

-- Audit: one row per question, no body, and no actor (the agency reads audit_log for its own solicitations).
reset role;
select is((select count(*)::int from public.audit_log where solicitation_id = :'s1' and action = 'ask_question'), 5,
  'one ask_question audit row per question');
select tests.act_as(:'author');
select ok((select bool_and(actor_id is null and detail = jsonb_build_object('question_id', detail ->> 'question_id'))
             from public.audit_log where solicitation_id = :'s1' and action = 'ask_question'),
  'the agency reads ask_question audit rows with no actor and only the question id (Review Focus 4)');
select is((select count(*)::int from public.audit_log
            where solicitation_id = :'s1' and (detail::text like '%canopy%' or actor_id in (:'bidder_a', :'bidder_b'))),
  0, 'no audit row the agency can read carries a question body or an asker');

-- ===========================================================================
-- Review Focus 6: the questions deadline, read in settings.timezone from the current published snapshot
-- ===========================================================================
select tests.act_as(:'bidder_a');
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s2', 'Late question.', ''), 'P0001',
  'questions_closed', 'ask_question after questionsDue raises questions_closed');
select lives_ok(format('select public.ask_question(%L, %L, %L)', :'s3', 'Just in time.', ''),
  'questionsDue 30 minutes ahead in settings.timezone is still open');
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s4', 'Just too late.', ''), 'P0001',
  'questions_closed', 'questionsDue 30 minutes ago in settings.timezone is closed');

select tests.act_as(:'r1');
select is(tests.t7_publish(:'add_s2'), 2, 'an addendum moving questionsDue later is published on s2');
select tests.act_as(:'bidder_a');
select lives_ok(format('select public.ask_question(%L, %L, %L)', :'s2', 'Late question.', ''),
  'after the addendum moves questionsDue later, the same call succeeds');

-- ===========================================================================
-- Review Focus 4: reads
-- ===========================================================================
select tests.act_as(:'bidder_b');
select is((select count(*)::int from public.questions where org_id = :'org_a'), 0,
  'another bidder reads 0 of A''s rows from questions');
select is((select count(*)::int from public.questions where id = :'q1'), 0, 'another bidder cannot read q1 by id');
select is((select count(*)::int from public.questions where solicitation_id = :'s1'), 1,
  'bidder B reads only its own question');
select is((select count(*)::int from public.my_questions(:'s1')), 1, 'my_questions: B sees one question');

select tests.act_as(:'bidder_a2');
select is((select count(*)::int from public.questions where solicitation_id = :'s1'), 4,
  'a colleague in A''s organization reads A''s questions');
select is((select count(*)::int from public.my_questions(:'s1')), 4, 'my_questions is scoped to the caller''s org');

select tests.act_as(:'author');
select is((select count(*)::int from public.questions), 0, 'the agency reads 0 rows from questions');
select tests.act_as(:'r1');
select is((select count(*)::int from public.questions where solicitation_id = :'s1'), 5,
  'the office reads every question');
select tests.act_as_anon();
select throws_ok('select count(*) from public.questions', '42501', null, 'anon has no grant on questions');

select tests.act_as(:'bidder_a');
select ok((select body = 'Is the canopy steel? Asked by Acme Roofing.' and reference = 'Item 2' and status = 'open'
                  and answered_in_number is null and close_reason is null
             from public.my_questions(:'s1') where id = :'q1'),
  'my_questions returns the body, reference and status');
select throws_ok(format('select * from public.office_questions(%L)', :'s1'), 'P0001', 'not_authorized',
  'a bidder cannot call office_questions');
select throws_ok(format('select * from public.agency_questions(%L)', :'s1'), 'P0001', 'not_authorized',
  'a bidder cannot call agency_questions');

select tests.act_as(:'r1');
select ok((select org_name = 'QA Bidder A' and asker_name = 'qa.a@test.test'
             from public.office_questions(:'s1') where id = :'q1'),
  'office_questions names the asker and organization');
select is((select count(*)::int from public.office_questions(:'s1')), 5, 'office_questions lists every question');

select tests.act_as(:'author');
select throws_ok(format('select * from public.office_questions(%L)', :'s1'), 'P0001', 'not_authorized',
  'the agency cannot call office_questions');
select throws_ok(format('select * from public.my_questions(%L)', :'s1'), 'P0001', 'not_authorized',
  'the agency cannot call my_questions');
select is((select count(*)::int from public.agency_questions(:'s1')), 5, 'agency_questions lists every question');
select ok((select body = 'Is the canopy steel? Asked by Acme Roofing.' and status = 'open' and not in_draft
             from public.agency_questions(:'s1') where id = :'q1'),
  'agency_questions returns the body and status');
select tests.act_as(:'other_agency');
select throws_ok(format('select * from public.agency_questions(%L)', :'s1'), 'P0001', 'not_authorized',
  'another agency cannot call agency_questions');

-- ===========================================================================
-- Answers in a draft addendum
-- ===========================================================================
select tests.act_as(:'author');
select public.start_addendum(:'s1') as ad1 \gset
select lives_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q1',
                       '  Is the canopy steel?  ', 'No, aluminum.'),
  'the agency saves an answer');
select lives_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q1',
                       'Is the canopy steel?', 'Yes, galvanized steel.'),
  'saving again updates the answer (upsert)');
select lives_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q4',
                       'What is the paving depth?', 'Four inches.'),
  'the agency picks a second question');
select is((select count(*)::int from public.addendum_answers_draft(:'ad1')), 2, 'addendum_answers_draft lists both');
select ok((select published_question = 'Is the canopy steel?' and answer = 'Yes, galvanized steel.'
             from public.addendum_answers_draft(:'ad1') where question_id = :'q1'),
  'the upsert kept one row with the trimmed, latest texts');
select ok((select in_draft from public.agency_questions(:'s1') where id = :'q1')
      and not (select in_draft from public.agency_questions(:'s1') where id = :'q2'),
  'agency_questions marks the questions picked into the draft');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q2', '   ', 'Answer.'),
  'P0001', 'invalid_data', 'an empty published question raises invalid_data');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q2', 'Q?', repeat('a', 4001)),
  'P0001', 'invalid_data', 'a 4001-character answer raises invalid_data');
select tests.act_as(:'bidder_a');
select public.ask_question(:'s3', 'Question on another solicitation.', '') as q_s3 \gset
select tests.act_as(:'author');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q_s3', 'Q?', 'A.'),
  'P0001', 'not_found', 'a question from another solicitation raises not_found');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', gen_random_uuid(), 'Q?', 'A.'),
  'P0001', 'not_found', 'an unknown question raises not_found');

select tests.act_as(:'other_agency');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q2', 'Q?', 'A.'),
  'P0001', 'not_authorized', 'another agency cannot save an answer');
select throws_ok(format('select * from public.addendum_answers_draft(%L)', :'ad1'), 'P0001', 'not_authorized',
  'another agency cannot read the draft answers');
select tests.act_as(:'r1');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q2', 'Q?', 'A.'),
  'P0001', 'not_authorized', 'the office cannot save an answer');
select is((select count(*)::int from public.addendum_answers_draft(:'ad1')), 2,
  'the office reads the draft answers');
select tests.act_as(:'bidder_a');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q1', 'Q?', 'A.'),
  'P0001', 'not_authorized', 'a bidder cannot save an answer');
select throws_ok(format('select * from public.addendum_answers_draft(%L)', :'ad1'), 'P0001', 'not_authorized',
  'a bidder cannot read the draft answers');
select tests.act_as_anon();
select throws_ok(format('select * from public.addendum_answers_draft(%L)', :'ad1'), '42501', null,
  'anon cannot read the draft answers');

-- ===========================================================================
-- close_question
-- ===========================================================================
select tests.act_as(:'r1');
select throws_ok(format('select public.close_question(%L, %L)', :'q4', 'out_of_scope'), 'P0001',
  'question_in_addendum', 'closing a question in a draft raises question_in_addendum');
select lives_ok(format('select public.close_question(%L, %L)', :'q3', 'duplicate'), 'the office closes q3');
select throws_ok(format('select public.close_question(%L, %L)', :'q3', 'duplicate'), 'P0001', 'question_not_open',
  'closing a closed question raises question_not_open');
select throws_ok(format('select public.close_question(%L, null)', :'q2'), 'P0001', 'reason_required',
  'closing without a reason raises reason_required');
select throws_ok(format('select public.close_question(%L, %L)', gen_random_uuid(), 'duplicate'), 'P0001',
  'not_found', 'closing an unknown question raises not_found');
reset role;
select ok((select status = 'closed' and close_reason = 'duplicate' and closed_by = :'r1'::uuid and closed_at is not null
             from public.questions where id = :'q3'),
  'close_question records the status, reason, closer and time');
select is((select detail from public.audit_log where solicitation_id = :'s1' and action = 'close_question'),
  jsonb_build_object('question_id', :'q3', 'reason', 'duplicate'), 'close_question is audited without the body');

select tests.act_as(:'author');
select throws_ok(format('select public.close_question(%L, %L)', :'q2', 'duplicate'), 'P0001', 'not_authorized',
  'the agency cannot close a question');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad1', :'q3', 'Q?', 'A.'),
  'P0001', 'question_not_open', 'a closed question cannot be answered');
select tests.act_as(:'bidder_a');
select is((select status::text || ':' || close_reason::text from public.my_questions(:'s1') where id = :'q3'),
  'closed:duplicate', 'the asker sees the closed status and reason');

-- remove_addendum_answer: q4 leaves the draft (it goes into the withdrawn addendum below instead).
select tests.act_as(:'bidder_b');
select throws_ok(format('select public.remove_addendum_answer(%L, %L)', :'ad1', :'q4'), 'P0001', 'not_authorized',
  'a bidder cannot remove an answer');
select tests.act_as(:'author');
select lives_ok(format('select public.remove_addendum_answer(%L, %L)', :'ad1', :'q4'), 'the agency removes q4');
select is((select count(*)::int from public.addendum_answers_draft(:'ad1')), 1, 'one answer is left');
select ok(not (select in_draft from public.agency_questions(:'s1') where id = :'q4'), 'q4 is no longer in the draft');

-- ===========================================================================
-- Publish: the answered question is marked, and the public sees only the published texts
-- ===========================================================================
-- The review path is pinned in addendum_review.test.sql; approve directly here.
reset role;
update public.addenda set state = 'approved', reviewer_id = :'r1', checker_id = :'r2', narrative = 'Answers.'
 where id = :'ad1';

-- The writer keeps one published answer per question: a question that is no longer open blocks the publish.
insert into public.addendum_answers (addendum_id, question_id, published_question, answer)
values (:'ad1', :'q3', 'Closed question.', 'Should not publish.');
select tests.act_as(:'r1');
select throws_ok(format('select tests.t7_publish(%L)', :'ad1'), 'P0001', 'question_not_open',
  'publish_addendum refuses an answer to a question that is not open');
reset role;
delete from public.addendum_answers where addendum_id = :'ad1' and question_id = :'q3';

select tests.act_as(:'r1');
select is(tests.t7_publish(:'ad1'), 2, 'addendum 1 is published as version 2');
reset role;
select ok((select status = 'answered' and answered_in = :'ad1'::uuid from public.questions where id = :'q1'),
  'after publish the question is answered in addendum 1');
select ok((select status = 'open' and answered_in is null from public.questions where id = :'q2'),
  'a question not in the addendum stays open');
select ok((select p.prosrc like '%set_config(''app.publishing_addendum'', '''', true)%'
                  and p.prosrc like '%set item_cents = ''{}''%'
             from pg_proc p
            where p.oid = 'public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)'::regprocedure),
  'publish_addendum keeps the 0030 setting reset and draft reset');

select tests.act_as(:'bidder_a');
select is((select answered_in_number from public.my_questions(:'s1') where id = :'q1'), 1,
  'my_questions shows the answering addendum number');
select tests.act_as(:'author');
select ok((select status = 'answered' and answered_in_number = 1 from public.agency_questions(:'s1') where id = :'q1'),
  'agency_questions shows the answering addendum number');
select tests.act_as(:'r1');
select throws_ok(format('select public.close_question(%L, %L)', :'q1', 'duplicate'), 'P0001', 'question_not_open',
  'closing an answered question raises question_not_open');

select tests.act_as_anon();
select is((select count(*)::int from public.published_answers(:'s1')), 1, 'anon reads one published answer');
select ok((select addendum_number = 1 and published_question = 'Is the canopy steel?'
                  and answer = 'Yes, galvanized steel.'
             from public.published_answers(:'s1')),
  'published_answers returns the published question and answer');
select is((select count(*)::int from public.published_answers(:'s1') p
            where p.published_question like '%Acme%' or p.answer like '%Acme%'), 0,
  'published_answers never returns the original body');

-- ===========================================================================
-- Withdraw: the question stays open and is answered in the next addendum
-- ===========================================================================
select tests.act_as(:'author');
select public.start_addendum(:'s1') as ad2 \gset
select lives_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad2', :'q4',
                       'Paving depth?', 'Withdrawn answer.'),
  'q4 is answered in addendum 2');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad2', :'q1', 'Q?', 'A.'),
  'P0001', 'question_not_open', 'an answered question cannot be answered again');
select lives_ok(format('select public.withdraw_addendum(%L, %L)', :'ad2', 'Not needed.'), 'addendum 2 is withdrawn');
reset role;
select ok((select status = 'open' and answered_in is null from public.questions where id = :'q4'),
  'after withdraw the question is still open');
select tests.act_as(:'author');
select ok(not (select in_draft from public.agency_questions(:'s1') where id = :'q4'),
  'a withdrawn addendum''s answers do not count as in a draft');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad2', :'q4', 'Q?', 'A.'),
  'P0001', 'invalid_state', 'a withdrawn addendum takes no answers');
select throws_ok(format('select public.remove_addendum_answer(%L, %L)', :'ad2', :'q4'),
  'P0001', 'invalid_state', 'a withdrawn addendum''s answers cannot be removed');
select public.start_addendum(:'s1') as ad3 \gset
select lives_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad3', :'q4',
                       'What is the paving depth?', 'Six inches.'),
  'the open question is answered in the next addendum');
reset role;
update public.addenda set state = 'approved', reviewer_id = :'r1', checker_id = :'r2', narrative = 'Paving.'
 where id = :'ad3';
select tests.act_as(:'r1');
select is(tests.t7_publish(:'ad3'), 3, 'the next addendum (number 2) is published as version 3');
select tests.act_as(:'bidder_a');
select ok((select status = 'answered' and answered_in_number = 2 from public.my_questions(:'s1') where id = :'q4'),
  'q4 is answered in Addendum 2');
select tests.act_as_anon();
select results_eq(
  format('select addendum_number, published_question, answer from public.published_answers(%L)', :'s1'),
  $$values (1, 'Is the canopy steel?'::text, 'Yes, galvanized steel.'::text),
           (2, 'What is the paving depth?'::text, 'Six inches.'::text)$$,
  'published_answers is ordered by addendum number and skips the withdrawn addendum''s answer');
select tests.act_as(:'author');
select throws_ok(format('select public.save_addendum_answer(%L, %L, %L, %L)', :'ad3', :'q2', 'Q?', 'A.'),
  'P0001', 'invalid_state', 'a published addendum takes no answers');

-- published_answers outside the public rule: an unreleased solicitation returns nothing.
reset role;
alter table public.solicitations disable trigger solicitations_published_frozen;
update public.solicitations set release_date = app.today() + 1 where id = :'s1';
alter table public.solicitations enable trigger solicitations_published_frozen;
select tests.act_as(:'bidder_a');
select is((select count(*)::int from public.published_answers(:'s1')), 0,
  'published_answers returns nothing for a solicitation that is not publicly readable');
select throws_ok(format('select public.ask_question(%L, %L, %L)', :'s1', 'Q?', ''), 'P0001', 'not_open',
  'ask_question on an unreleased solicitation raises not_open');

select * from finish();
rollback;
