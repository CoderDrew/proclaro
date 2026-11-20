-- Workflow functions: state transitions, role checks, numbering, clause locks, audit.
begin;

select plan(84);

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres). Own orgs, users and clauses; no dependency on seed data.
-- ---------------------------------------------------------------------------
insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000006f1', 'WF Office',   'office'),
  ('00000000-0000-0000-0000-0000000006a1', 'WF Agency A', 'agency'),
  ('00000000-0000-0000-0000-0000000006b1', 'WF Agency B', 'agency');

select tests.make_user('wf.author@test.test',  '00000000-0000-0000-0000-0000000006a1') as author \gset
select tests.make_user('wf.author.b@test.test','00000000-0000-0000-0000-0000000006b1') as author_b \gset
select tests.make_user('wf.r1@test.test',      '00000000-0000-0000-0000-0000000006f1') as r1 \gset
select tests.make_user('wf.r2@test.test',      '00000000-0000-0000-0000-0000000006f1') as r2 \gset

insert into public.clauses (key, version, body) values
  ('wf-clause-a', 1, 'Plain clause A.'),
  ('wf-clause-b', 1, 'Plain clause B.');

-- 6s1 happy path, 6s2 check/locks, 6s3 disagree/edit/fallback, 6s4 + 6s5 numbering/return.
insert into public.solicitations (id, agency_id, created_by, data)
select v.id::uuid, '00000000-0000-0000-0000-0000000006a1', :'author',
       tests.solicitation_data(jsonb_build_object('title', v.title, 'shortTitle', 'Short'))
from (values
  ('00000000-0000-0000-0000-0000000006c1', 'Happy path'),
  ('00000000-0000-0000-0000-0000000006c2', 'Check and locks'),
  ('00000000-0000-0000-0000-0000000006c3', 'Disagree and fallback'),
  ('00000000-0000-0000-0000-0000000006c4', 'Numbering one'),
  ('00000000-0000-0000-0000-0000000006c5', 'Numbering two')
) as v(id, title);

-- ---------------------------------------------------------------------------
-- Happy path: submit -> start_review -> send_to_check -> approve_check -> publish
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select lives_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000006c1')$$,
  'author submits own draft');
select matches((select number from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1'),
  '^\d{2}-\d{4}$', 'first submission assigns a YY-NNNN number');
select ok((select latest_submitted_at is not null from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1'),
  'submit sets latest_submitted_at');

select tests.act_as(:'r1');
select lives_ok($$select public.start_review('00000000-0000-0000-0000-0000000006c1')$$,
  'office staff starts review');
select is((select reviewer_id from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1'),
  :'r1'::uuid, 'start_review makes the caller the reviewer');
select lives_ok($$select public.send_to_check('00000000-0000-0000-0000-0000000006c1')$$,
  'reviewer sends to check');

select tests.act_as(:'r2');
select lives_ok($$select public.approve_check('00000000-0000-0000-0000-0000000006c1')$$,
  'second staff member approves the check');

select tests.act_as(:'r1');
select lives_ok(
  $$select public.publish_solicitation('00000000-0000-0000-0000-0000000006c1',
      'solicitations/00000000-0000-0000-0000-0000000006c1/v1/rfb.pdf',
      'solicitations/00000000-0000-0000-0000-0000000006c1/v1/bid-form.pdf',
      '{"text":"snapshot"}'::jsonb,
      tests.bid_due_at((select data from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1')), 15000000)$$,
  'reviewer publishes');

reset role;
select is((select state::text from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1'),
  'published', 'happy path ends published');
select matches((select number from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1'),
  '^\d{2}-\d{4}$', 'published number is YY-NNNN');
select is((select version from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1'),
  1, 'published version is 1');
select is((select release_date from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1'),
  app.today() + 7, 'release_date comes from data.releaseDate');
select ok((select published_at is not null and bid_due_at is not null and published_snapshot = '{"text":"snapshot"}'::jsonb
                  and rfb_path like 'solicitations/%/v1/rfb.pdf' and bid_form_path like 'solicitations/%/v1/bid-form.pdf'
           from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1'),
  'publish stores published_at, bid_due_at, snapshot and paths');
select is((select checker_id from public.solicitations where id = '00000000-0000-0000-0000-0000000006c1'),
  :'r2'::uuid, 'approve_check records the checker');
select is((select count(*)::int from public.audit_log where solicitation_id = '00000000-0000-0000-0000-0000000006c1'),
  5, 'happy path writes 5 audit rows');
select is((select array_agg(action order by id) from public.audit_log where solicitation_id = '00000000-0000-0000-0000-0000000006c1'),
  array['submit_solicitation','start_review','send_to_check','approve_check','publish_solicitation'],
  'audit actions equal the function names, in order');
select is((select array_agg(actor_id order by id) from public.audit_log where solicitation_id = '00000000-0000-0000-0000-0000000006c1'),
  array[:'author'::uuid, :'r1'::uuid, :'r1'::uuid, :'r2'::uuid, :'r1'::uuid],
  'audit records the actor of each step');

-- ---------------------------------------------------------------------------
-- Any function on a published row raises invalid_state
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select throws_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000006c1')$$,
  'P0001', 'invalid_state', 'published: submit raises invalid_state');
select throws_ok($$select public.acknowledge_warning('00000000-0000-0000-0000-0000000006c1', 'W1', null)$$,
  'P0001', 'invalid_state', 'published: acknowledge_warning raises invalid_state');

select tests.act_as(:'r1');
select throws_ok($$select public.start_review('00000000-0000-0000-0000-0000000006c1')$$,
  'P0001', 'invalid_state', 'published: start_review raises invalid_state');
select throws_ok(format($$select public.reassign_review('00000000-0000-0000-0000-0000000006c1', %L)$$, :'r1'),
  'P0001', 'invalid_state', 'published: reassign_review raises invalid_state');
select throws_ok($$select public.office_update_data('00000000-0000-0000-0000-0000000006c1', '{"title":"x"}', 'why')$$,
  'P0001', 'invalid_state', 'published: office_update_data raises invalid_state');
select throws_ok($$select public.return_to_agency('00000000-0000-0000-0000-0000000006c1', '[{"field":"title","body":"x"}]')$$,
  'P0001', 'invalid_state', 'published: return_to_agency raises invalid_state');
select throws_ok($$select public.send_to_check('00000000-0000-0000-0000-0000000006c1')$$,
  'P0001', 'invalid_state', 'published: send_to_check raises invalid_state');
select throws_ok($$select public.approve_alone('00000000-0000-0000-0000-0000000006c1')$$,
  'P0001', 'invalid_state', 'published: approve_alone raises invalid_state');
select throws_ok(
  $$select public.publish_solicitation('00000000-0000-0000-0000-0000000006c1', 'a', 'b', '{}', now(), 15000000)$$,
  'P0001', 'invalid_state', 'published: publish_solicitation raises invalid_state');

select tests.act_as(:'r2');
select throws_ok($$select public.approve_check('00000000-0000-0000-0000-0000000006c1')$$,
  'P0001', 'invalid_state', 'published: approve_check raises invalid_state');
select throws_ok($$select public.disagree('00000000-0000-0000-0000-0000000006c1', 'no', null)$$,
  'P0001', 'invalid_state', 'published: disagree raises invalid_state');

reset role;
select is((select count(*)::int from public.audit_log where solicitation_id = '00000000-0000-0000-0000-0000000006c1'),
  5, 'rejected calls on a published row write no audit rows');

-- ---------------------------------------------------------------------------
-- Clause locks; same-person rule on approve_check
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select lives_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000006c2')$$, 'submit 6c2');
select tests.act_as(:'r1');
select lives_ok($$select public.start_review('00000000-0000-0000-0000-0000000006c2')$$, 'start_review 6c2');
select lives_ok($$select public.send_to_check('00000000-0000-0000-0000-0000000006c2')$$, 'send_to_check 6c2');

reset role;
select is((select count(*)::int from public.solicitation_clause_locks where solicitation_id = '00000000-0000-0000-0000-0000000006c2'),
  (select count(distinct key)::int from public.clauses), 'send_to_check locks one row per clause key');
select is((select clause_version from public.solicitation_clause_locks
           where solicitation_id = '00000000-0000-0000-0000-0000000006c2' and clause_key = 'wf-clause-a'),
  1, 'lock holds the latest clause version at send time');

-- An admin edits clause A after the send.
insert into public.clauses (key, version, body) values ('wf-clause-a', 2, 'Plain clause A, revised.');

select tests.act_as(:'r1');
select throws_ok($$select public.approve_check('00000000-0000-0000-0000-0000000006c2')$$,
  'P0001', 'same_person', 'the reviewer cannot approve the check');

select tests.act_as(:'r2');
select lives_ok($$select public.approve_check('00000000-0000-0000-0000-0000000006c2')$$,
  'another staff member approves the check');

reset role;
select is((select state::text from public.solicitations where id = '00000000-0000-0000-0000-0000000006c2'),
  'approved', 'approve_check moves in_check to approved');
select is((select clause_version from public.solicitation_clause_locks
           where solicitation_id = '00000000-0000-0000-0000-0000000006c2' and clause_key = 'wf-clause-a'),
  1, 'a new clause version and approve_check leave the lock unchanged');
select is((select count(*)::int from public.solicitation_clause_locks where solicitation_id = '00000000-0000-0000-0000-0000000006c2'),
  (select count(distinct key)::int from public.clauses), 'lock count unchanged by approve_check');

-- ---------------------------------------------------------------------------
-- Disagree (Review Focus 3), office edit with reason, reassign, approve alone
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select lives_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000006c3')$$, 'submit 6c3');
select tests.act_as(:'r1');
select lives_ok($$select public.start_review('00000000-0000-0000-0000-0000000006c3')$$, 'start_review 6c3');
select lives_ok($$select public.send_to_check('00000000-0000-0000-0000-0000000006c3')$$, 'send_to_check 6c3');

select tests.act_as(:'r1');
select throws_ok($$select public.disagree('00000000-0000-0000-0000-0000000006c3', 'self check', null)$$,
  'P0001', 'same_person', 'the reviewer cannot disagree as checker');

select tests.act_as(:'r2');
select lives_ok($$select public.disagree('00000000-0000-0000-0000-0000000006c3', 'Scope is unclear.', 'scope')$$,
  'checker disagrees with a comment');
select throws_ok($$select public.approve_check('00000000-0000-0000-0000-0000000006c3')$$,
  'P0001', 'invalid_state', 'after disagree, approve_check by the checker raises invalid_state');

reset role;
select is((select state::text from public.solicitations where id = '00000000-0000-0000-0000-0000000006c3'),
  'in_review', 'disagree moves in_check back to in_review');
select is((select count(*)::int from public.solicitation_clause_locks where solicitation_id = '00000000-0000-0000-0000-0000000006c3'),
  0, 'disagree deletes the clause locks');
select is((select count(*)::int from public.comments
           where solicitation_id = '00000000-0000-0000-0000-0000000006c3' and kind = 'disagree' and field = 'scope'
             and author_id = :'r2'::uuid),
  1, 'disagree inserts a disagree comment on the field');

-- office_update_data
select tests.act_as(:'r2');
select throws_ok($$select public.office_update_data('00000000-0000-0000-0000-0000000006c3', '{"title":"x"}', 'not mine')$$,
  'P0001', 'not_authorized', 'only the reviewer can edit');

select tests.act_as(:'r1');
select throws_ok(
  $$select public.office_update_data('00000000-0000-0000-0000-0000000006c3',
      (select data from public.solicitations where id = '00000000-0000-0000-0000-0000000006c3') || '{"title":"Fixed"}', '')$$,
  'P0001', 'reason_required', 'blank reason raises reason_required');
select throws_ok(
  $$select public.office_update_data('00000000-0000-0000-0000-0000000006c3', '{"title":"Fixed"}', '   ')$$,
  'P0001', 'reason_required', 'whitespace reason raises reason_required');
select lives_ok(
  $$select public.office_update_data('00000000-0000-0000-0000-0000000006c3',
      (select data from public.solicitations where id = '00000000-0000-0000-0000-0000000006c3') || '{"title":"Fixed title"}',
      'Typo in title')$$,
  'reviewer edits data with a reason');

reset role;
select is((select data->>'title' from public.solicitations where id = '00000000-0000-0000-0000-0000000006c3'),
  'Fixed title', 'office edit takes effect');
select is((select detail from public.audit_log
           where solicitation_id = '00000000-0000-0000-0000-0000000006c3' and action = 'office_update_data'),
  '{"reason":"Typo in title","changes":[{"key":"title","old":"Disagree and fallback","new":"Fixed title"}]}'::jsonb,
  'audit detail has the reason and only the changed key with old and new values');

-- reassign_review
select tests.act_as(:'r2');
select throws_ok(format($$select public.reassign_review('00000000-0000-0000-0000-0000000006c3', %L)$$, :'author'),
  'P0001', 'not_authorized', 'cannot reassign to a non-office user');
select lives_ok(format($$select public.reassign_review('00000000-0000-0000-0000-0000000006c3', %L)$$, :'r2'),
  'office staff reassigns the review');
reset role;
select is((select detail from public.audit_log
           where solicitation_id = '00000000-0000-0000-0000-0000000006c3' and action = 'reassign_review'),
  jsonb_build_object('old_reviewer_id', :'r1'::uuid, 'new_reviewer_id', :'r2'::uuid),
  'reassign audit records old and new reviewer');
select tests.act_as(:'r2');
select lives_ok(format($$select public.reassign_review('00000000-0000-0000-0000-0000000006c3', %L)$$, :'r1'),
  'reassign back to r1');

-- approve_alone
select tests.act_as(:'r2');
select throws_ok($$select public.approve_alone('00000000-0000-0000-0000-0000000006c3')$$,
  'P0001', 'not_authorized', 'only the reviewer can approve alone');
select tests.act_as(:'r1');
select lives_ok($$select public.approve_alone('00000000-0000-0000-0000-0000000006c3')$$,
  'reviewer approves alone');

reset role;
select ok((select state = 'approved' and fallback_approved and checker_id is null
           from public.solicitations where id = '00000000-0000-0000-0000-0000000006c3'),
  'approve_alone approves with fallback_approved and no checker');
select is((select detail from public.audit_log
           where solicitation_id = '00000000-0000-0000-0000-0000000006c3' and action = 'approve_alone'),
  '{"fallback":"no second reviewer available"}'::jsonb, 'approve_alone audit records the fallback');
select is((select count(*)::int from public.solicitation_clause_locks where solicitation_id = '00000000-0000-0000-0000-0000000006c3'),
  (select count(distinct key)::int from public.clauses), 'approve_alone locks the clauses');
select is((select clause_version from public.solicitation_clause_locks
           where solicitation_id = '00000000-0000-0000-0000-0000000006c3' and clause_key = 'wf-clause-a'),
  2, 'approve_alone locks the latest clause version');

-- ---------------------------------------------------------------------------
-- Role checks
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select lives_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000006c5')$$, 'submit 6c5');
select throws_ok($$select public.start_review('00000000-0000-0000-0000-0000000006c5')$$,
  'P0001', 'not_authorized', 'an agency author cannot start a review');

select tests.act_as(:'author_b');
select throws_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000006c4')$$,
  'P0001', 'not_authorized', 'another agency cannot submit the draft');

select tests.act_as(:'r1');
select throws_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000006c4')$$,
  'P0001', 'not_authorized', 'office staff cannot submit a draft');

-- ---------------------------------------------------------------------------
-- Numbering, warning acks, return to agency, resubmission
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
select lives_ok($$select public.acknowledge_warning('00000000-0000-0000-0000-0000000006c4', 'W1', 'title')$$,
  'author acknowledges a warning on a draft');
select lives_ok($$select public.acknowledge_warning('00000000-0000-0000-0000-0000000006c4', 'W1', 'title')$$,
  'acknowledging again is an upsert');
select tests.act_as(:'r1');
select throws_ok($$select public.acknowledge_warning('00000000-0000-0000-0000-0000000006c4', 'W2', null)$$,
  'P0001', 'not_authorized', 'office staff cannot acknowledge on a draft');

select tests.act_as(:'author');
select lives_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000006c4')$$, 'submit 6c4');

reset role;
select is((select count(*)::int from public.warning_acks where solicitation_id = '00000000-0000-0000-0000-0000000006c4'),
  1, 'repeated acknowledgement keeps one row');
select is(
  (select split_part(number, '-', 2)::int from public.solicitations where id = '00000000-0000-0000-0000-0000000006c4'),
  (select split_part(number, '-', 2)::int + 1 from public.solicitations where id = '00000000-0000-0000-0000-0000000006c5'),
  'submissions in the same fiscal year get consecutive numbers');
select ok(
  (select count(distinct fiscal_year) = 1 and count(distinct split_part(number, '-', 1)) = 1
   from public.solicitations where id in ('00000000-0000-0000-0000-0000000006c4', '00000000-0000-0000-0000-0000000006c5')),
  'both numbers share the fiscal year prefix');
select is(
  (select split_part(number, '-', 1) from public.solicitations where id = '00000000-0000-0000-0000-0000000006c4'),
  (select lpad((fiscal_year % 100)::text, 2, '0') from public.solicitations where id = '00000000-0000-0000-0000-0000000006c4'),
  'YY is the fiscal-year end year mod 100');

select tests.act_as(:'r1');
select lives_ok($$select public.start_review('00000000-0000-0000-0000-0000000006c4')$$, 'start_review 6c4');
select lives_ok($$select public.acknowledge_warning('00000000-0000-0000-0000-0000000006c4', 'W2', 'estimate')$$,
  'reviewer acknowledges a warning while in review');
select lives_ok(
  $$select public.return_to_agency('00000000-0000-0000-0000-0000000006c4',
      '[{"field":"title","body":"Fix the title."},{"field":null,"body":"General note."}]')$$,
  'reviewer returns to agency with comments');

reset role;
select is((select state::text from public.solicitations where id = '00000000-0000-0000-0000-0000000006c4'),
  'draft', 'return_to_agency moves in_review to draft');
select is((select count(*)::int from public.comments
           where solicitation_id = '00000000-0000-0000-0000-0000000006c4' and kind = 'return'),
  2, 'return inserts one return comment per item');
select is((select count(*)::int from public.warning_acks where solicitation_id = '00000000-0000-0000-0000-0000000006c4'),
  0, 'return deletes the warning acknowledgements');

select number as num_6c4 from public.solicitations where id = '00000000-0000-0000-0000-0000000006c4' \gset
select tests.act_as(:'author');
select lives_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000006c4')$$, 'resubmit 6c4');
reset role;
select is((select number from public.solicitations where id = '00000000-0000-0000-0000-0000000006c4'),
  :'num_6c4', 'resubmission keeps its number');

select * from finish();
rollback;
