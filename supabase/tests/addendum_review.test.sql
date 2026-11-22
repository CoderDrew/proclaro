-- 0028: addendum review and the two-person check. start_addendum_review, reassign_addendum_review, return_addendum,
-- send_addendum_to_check, approve_addendum_check, disagree_addendum, approve_addendum_alone, reopen_addendum_review,
-- and app.was_addendum_round_reviewer (round-scoped same-person rule, read from the audit log).
begin;

select plan(87);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000281', 'AR Office', 'office'),
  ('00000000-0000-0000-0000-000000000282', 'AR Agency', 'agency');

select tests.make_user('ar.author@test.test', '00000000-0000-0000-0000-000000000282') as author \gset
select tests.make_user('ar.r1@test.test',     '00000000-0000-0000-0000-000000000281') as r1 \gset
select tests.make_user('ar.r2@test.test',     '00000000-0000-0000-0000-000000000281') as r2 \gset
select tests.make_user('ar.r3@test.test',     '00000000-0000-0000-0000-000000000281') as r3 \gset

-- s1: open for bids (the review scenarios). s2: closed later (bids_closed). s3: closes between now() and the
-- wall clock (the clock_timestamp() re-check).
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000282', :'author',
  now() + interval '20 days') as s1 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000282', :'author',
  now() + interval '20 days') as s2 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000282', :'author',
  now() + interval '20 days') as s3 \gset

-- ===========================================================================
-- Schema objects and grants
-- ===========================================================================
select has_function('public', 'start_addendum_review', array['uuid'], 'start_addendum_review(uuid) exists');
select has_function('public', 'reassign_addendum_review', array['uuid', 'uuid'], 'reassign_addendum_review exists');
select has_function('public', 'return_addendum', array['uuid', 'jsonb'], 'return_addendum exists');
select has_function('public', 'send_addendum_to_check', array['uuid'], 'send_addendum_to_check exists');
select has_function('public', 'approve_addendum_check', array['uuid'], 'approve_addendum_check exists');
select has_function('public', 'disagree_addendum', array['uuid', 'text'], 'disagree_addendum exists');
select has_function('public', 'approve_addendum_alone', array['uuid'], 'approve_addendum_alone exists');
select has_function('public', 'reopen_addendum_review', array['uuid', 'text'], 'reopen_addendum_review exists');
select has_function('app', 'was_addendum_round_reviewer', array['addenda', 'uuid'],
  'app.was_addendum_round_reviewer exists');
select ok(not has_function_privilege('authenticated', 'app.was_addendum_round_reviewer(public.addenda, uuid)',
  'execute'), 'app.was_addendum_round_reviewer is not callable through the API');
select ok(not has_function_privilege('anon', 'public.start_addendum_review(uuid)', 'execute'),
  'anon cannot execute start_addendum_review');

-- ===========================================================================
-- Happy path: the author drafts and submits Addendum 1; r1 reviews, r2 checks.
-- ===========================================================================
select tests.act_as(:'author');
select public.start_addendum(:'s1') as a1 \gset
reset role;
select data as d1 from public.addenda where id = :'a1' \gset
select tests.act_as(:'author');
select public.save_addendum(:'a1', :'d1'::jsonb, 'Clarifies the roofing scope.');
select public.submit_addendum(:'a1');

-- The agency can call none of the review functions.
select throws_ok(format('select public.start_addendum_review(%L)', :'a1'), 'P0001', 'not_authorized',
  'agency: start_addendum_review is not_authorized');
select throws_ok(format('select public.reassign_addendum_review(%L, %L)', :'a1', :'r1'), 'P0001', 'not_authorized',
  'agency: reassign_addendum_review is not_authorized');
select throws_ok(format('select public.return_addendum(%L, %L)', :'a1', '[{"field": null, "body": "x"}]'),
  'P0001', 'not_authorized', 'agency: return_addendum is not_authorized');
select throws_ok(format('select public.send_addendum_to_check(%L)', :'a1'), 'P0001', 'not_authorized',
  'agency: send_addendum_to_check is not_authorized');
select throws_ok(format('select public.approve_addendum_check(%L)', :'a1'), 'P0001', 'not_authorized',
  'agency: approve_addendum_check is not_authorized');
select throws_ok(format('select public.disagree_addendum(%L, %L)', :'a1', 'x'), 'P0001', 'not_authorized',
  'agency: disagree_addendum is not_authorized');
select throws_ok(format('select public.approve_addendum_alone(%L)', :'a1'), 'P0001', 'not_authorized',
  'agency: approve_addendum_alone is not_authorized');
select throws_ok(format('select public.reopen_addendum_review(%L, %L)', :'a1', 'x'), 'P0001', 'not_authorized',
  'agency: reopen_addendum_review is not_authorized');

select tests.act_as(:'r1');
select throws_ok(format('select public.start_addendum_review(%L)', gen_random_uuid()), 'P0001', 'not_found',
  'start review of a missing addendum is not_found');
select throws_ok(format('select public.send_addendum_to_check(%L)', :'a1'), 'P0001', 'invalid_state',
  'send to check from submitted is invalid_state');
select throws_ok(format('select public.reassign_addendum_review(%L, %L)', :'a1', :'r2'), 'P0001', 'invalid_state',
  'reassign from submitted is invalid_state');
select lives_ok(format('select public.start_addendum_review(%L)', :'a1'), 'r1 starts the review');
reset role;
select is((select row(state::text, reviewer_id = :'r1'::uuid, checker_id is null)::text
             from public.addenda where id = :'a1'),
          row('in_review', true, true)::text, 'submitted -> in_review with r1 as reviewer');
select throws_ok(format('select public.start_addendum_review(%L)', :'a1'), 'P0001', 'invalid_state',
  'starting a review twice is invalid_state');
select tests.act_as(:'r2');
select throws_ok(format('select public.approve_addendum_check(%L)', :'a1'), 'P0001', 'invalid_state',
  'approve check from in_review is invalid_state');
select throws_ok(format('select public.disagree_addendum(%L, %L)', :'a1', 'x'), 'P0001', 'invalid_state',
  'disagree from in_review is invalid_state');
select tests.act_as(:'r1');
select throws_ok(format('select public.reopen_addendum_review(%L, %L)', :'a1', 'x'), 'P0001', 'invalid_state',
  'reopen from in_review is invalid_state');

select tests.act_as(:'r2');
select throws_ok(format('select public.send_addendum_to_check(%L)', :'a1'), 'P0001', 'not_authorized',
  'a non-reviewer cannot send to check');
select tests.act_as(:'r1');
select lives_ok(format('select public.send_addendum_to_check(%L)', :'a1'), 'r1 sends to check');
reset role;
select is((select state::text from public.addenda where id = :'a1'), 'in_check', 'in_review -> in_check');

select tests.act_as(:'r1');
select throws_ok(format('select public.approve_addendum_check(%L)', :'a1'), 'P0001', 'same_person',
  'the reviewer cannot approve the check');
select throws_ok(format('select public.disagree_addendum(%L, %L)', :'a1', 'x'), 'P0001', 'same_person',
  'the reviewer cannot disagree with their own review');

select tests.act_as(:'r2');
select throws_ok(format('select public.disagree_addendum(%L, %L)', :'a1', '  '), 'P0001', 'comment_required',
  'disagree without a comment is comment_required');
select lives_ok(format('select public.disagree_addendum(%L, %L)', :'a1', 'Name the roofing sheet.'),
  'r2 disagrees');
reset role;
select is((select state::text from public.addenda where id = :'a1'), 'in_review', 'in_check -> in_review');
select is((select row(field, body, kind::text, author_id = :'r2'::uuid)::text
             from public.addendum_comments where addendum_id = :'a1'),
          row(null::text, 'Name the roofing sheet.', 'disagree', true)::text,
  'disagree inserts one disagree comment by r2');

select tests.act_as(:'r1');
select public.send_addendum_to_check(:'a1');
select tests.act_as(:'r2');
select lives_ok(format('select public.approve_addendum_check(%L)', :'a1'), 'r2 approves the check');
reset role;
select is((select row(state::text, reviewer_id = :'r1'::uuid, checker_id = :'r2'::uuid, single_reviewer)::text
             from public.addenda where id = :'a1'),
          row('approved', true, true, false)::text, 'in_check -> approved with r2 as checker');
select is((select detail from public.audit_log
            where action = 'approve_addendum_check' and detail ->> 'addendum_id' = :'a1'),
          jsonb_build_object('addendum_id', :'a1', 'number', 1, 'from', 'in_check', 'to', 'approved',
                             'checker_id', :'r2'),
  'approve_addendum_check is audited with the addendum id, number and checker');

-- reopen: reviewer or checker, with a reason.
select tests.act_as(:'r3');
select throws_ok(format('select public.reopen_addendum_review(%L, %L)', :'a1', 'x'), 'P0001', 'not_authorized',
  'office staff who are neither reviewer nor checker cannot reopen');
select tests.act_as(:'r2');
select throws_ok(format('select public.reopen_addendum_review(%L, %L)', :'a1', ' '), 'P0001', 'reason_required',
  'reopen without a reason is reason_required');
select lives_ok(format('select public.reopen_addendum_review(%L, %L)', :'a1', 'Bid date typo.'),
  'the checker reopens the review');
reset role;
select is((select row(state::text, reviewer_id = :'r1'::uuid, checker_id is null)::text
             from public.addenda where id = :'a1'),
          row('in_review', true, true)::text, 'approved -> in_review, the checker is cleared');

-- A new round: r1 is still the reviewer; r2 (last round's checker) may check again.
select tests.act_as(:'r1');
select public.send_addendum_to_check(:'a1');
select throws_ok(format('select public.approve_addendum_check(%L)', :'a1'), 'P0001', 'same_person',
  'after reopen the reviewer still cannot approve the check');
select tests.act_as(:'r2');
select lives_ok(format('select public.approve_addendum_check(%L)', :'a1'), 'r2 approves the new round');

reset role;
select is((select jsonb_object_agg(action, n order by action) from (
             select action, count(*)::int as n from public.audit_log
              where detail ->> 'addendum_id' = :'a1' group by action) x),
          jsonb_build_object('start_addendum', 1, 'submit_addendum', 1, 'start_addendum_review', 1,
                             'send_addendum_to_check', 3, 'disagree_addendum', 1, 'approve_addendum_check', 2,
                             'reopen_addendum_review', 1),
  'each successful call wrote exactly one audit row (refused calls wrote none)');
select is((select detail from public.audit_log
            where action = 'reopen_addendum_review' and detail ->> 'addendum_id' = :'a1'),
          jsonb_build_object('addendum_id', :'a1', 'number', 1, 'from', 'approved', 'to', 'in_review',
                             'reason', 'Bid date typo.', 'reviewer_id', :'r1', 'previous_checker_id', :'r2',
                             'previous_single_reviewer', false),
  'reopen_addendum_review is audited with the reason and the previous checker');

-- ===========================================================================
-- Reassignment: r1 -> r2. r1 reviewed in this round, so r1 cannot check.
-- ===========================================================================
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, narrative, created_by, latest_submitted_at)
select '00000000-0000-0000-0000-000000000284', :'s1', 2, 'submitted', s.data, 'Second.', :'author', now()
  from public.solicitations s where s.id = :'s1';

select tests.act_as(:'r1');
select public.start_addendum_review('00000000-0000-0000-0000-000000000284');
select tests.act_as(:'r3');
select throws_ok(format('select public.reassign_addendum_review(%L, %L)', '00000000-0000-0000-0000-000000000284',
    :'author'), 'P0001', 'not_authorized', 'reassigning to a non-office user is not_authorized');
select lives_ok(format('select public.reassign_addendum_review(%L, %L)', '00000000-0000-0000-0000-000000000284',
    :'r2'), 'r3 reassigns the review from r1 to r2');
reset role;
select is((select reviewer_id from public.addenda where id = '00000000-0000-0000-0000-000000000284'), :'r2'::uuid,
  'r2 is now the reviewer');
select is((select detail from public.audit_log
            where action = 'reassign_addendum_review'
              and detail ->> 'addendum_id' = '00000000-0000-0000-0000-000000000284'),
          jsonb_build_object('addendum_id', '00000000-0000-0000-0000-000000000284', 'number', 2,
                             'old_reviewer_id', :'r1', 'new_reviewer_id', :'r2'),
  'reassign_addendum_review is audited once with the old and new reviewer');
select is((select app.was_addendum_round_reviewer(a, :'r1') from public.addenda a
            where a.id = '00000000-0000-0000-0000-000000000284'), true,
  'was_addendum_round_reviewer: the reassigned-away reviewer counts');
select is((select app.was_addendum_round_reviewer(a, :'r3') from public.addenda a
            where a.id = '00000000-0000-0000-0000-000000000284'), false,
  'was_addendum_round_reviewer: the reassigning office user does not count');
select is((select app.was_addendum_round_reviewer(a, :'r2') from public.addenda a where a.id = :'a1'), false,
  'was_addendum_round_reviewer: another addendum''s history is not mixed in (r2 reviews 284, only checked a1)');
select is((select app.was_addendum_round_reviewer(a, :'r3') from public.addenda a where a.id = :'a1'), false,
  'was_addendum_round_reviewer: r3 never reviewed a1');

select tests.act_as(:'r2');
select public.send_addendum_to_check('00000000-0000-0000-0000-000000000284');
select tests.act_as(:'r1');
select throws_ok(format('select public.approve_addendum_check(%L)', '00000000-0000-0000-0000-000000000284'),
  'P0001', 'same_person', 'after reassignment, r1 approving the check is same_person');
select throws_ok(format('select public.disagree_addendum(%L, %L)', '00000000-0000-0000-0000-000000000284', 'x'),
  'P0001', 'same_person', 'after reassignment, r1 disagreeing is same_person');
select tests.act_as(:'r3');
select lives_ok(format('select public.approve_addendum_check(%L)', '00000000-0000-0000-0000-000000000284'),
  'r3, who never reviewed, approves the check');

-- ===========================================================================
-- Return to the agency: in_review -> draft with return comments.
-- ===========================================================================
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, narrative, created_by, latest_submitted_at)
select '00000000-0000-0000-0000-000000000285', :'s1', 3, 'submitted', s.data, 'Third.', :'author', now()
  from public.solicitations s where s.id = :'s1';
select tests.act_as(:'r1');
select public.start_addendum_review('00000000-0000-0000-0000-000000000285');

select tests.act_as(:'r2');
select throws_ok(format('select public.return_addendum(%L, %L)', '00000000-0000-0000-0000-000000000285',
    '[{"field": null, "body": "x"}]'), 'P0001', 'not_authorized', 'a non-reviewer cannot return the addendum');
select tests.act_as(:'r1');
select throws_ok(format('select public.return_addendum(%L, %L)', '00000000-0000-0000-0000-000000000285', '[]'),
  'P0001', 'invalid_comments', 'return with an empty array is invalid_comments');
select throws_ok(format('select public.return_addendum(%L, %L)', '00000000-0000-0000-0000-000000000285',
    '[{"field": "narrative", "body": "  "}]'), 'P0001', 'invalid_comments',
  'return with a blank comment body is invalid_comments');
select throws_ok(format('select public.return_addendum(%L, %L)', '00000000-0000-0000-0000-000000000285',
    '{"field": null, "body": "x"}'), 'P0001', 'invalid_comments', 'return with an object, not an array, is invalid_comments');
select throws_ok(format('select public.return_addendum(%L, %L)', '00000000-0000-0000-0000-000000000285',
    '["x"]'), 'P0001', 'invalid_comments', 'return with a non-object element is invalid_comments');
select lives_ok(format('select public.return_addendum(%L, %L)', '00000000-0000-0000-0000-000000000285',
    '[{"field": "narrative", "body": "Explain why the date moves."}]'), 'r1 returns the addendum');
reset role;
select is((select state::text from public.addenda where id = '00000000-0000-0000-0000-000000000285'), 'draft',
  'in_review -> draft');
select is((select row(field, body, kind::text, author_id = :'r1'::uuid)::text
             from public.addendum_comments where addendum_id = '00000000-0000-0000-0000-000000000285'),
          row('narrative', 'Explain why the date moves.', 'return', true)::text,
  'return inserts one return comment');
select is((select count(*)::int from public.audit_log
            where action = 'return_addendum' and detail ->> 'addendum_id' = '00000000-0000-0000-0000-000000000285'),
          1, 'return_addendum writes exactly one audit row');

-- ===========================================================================
-- Approve alone: reviewer, in_review -> approved (as slice 1's approve_alone), single_reviewer = true, fallback recorded.
-- ===========================================================================
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, narrative, created_by, latest_submitted_at)
select '00000000-0000-0000-0000-000000000286', :'s1', 4, 'submitted', s.data, 'Fourth.', :'author', now()
  from public.solicitations s where s.id = :'s1';
select tests.act_as(:'r1');
select public.start_addendum_review('00000000-0000-0000-0000-000000000286');
select tests.act_as(:'r2');
select throws_ok(format('select public.approve_addendum_alone(%L)', '00000000-0000-0000-0000-000000000286'),
  'P0001', 'not_authorized', 'a non-reviewer cannot approve alone');
select tests.act_as(:'r1');
select public.send_addendum_to_check('00000000-0000-0000-0000-000000000286');
select throws_ok(format('select public.approve_addendum_alone(%L)', '00000000-0000-0000-0000-000000000286'),
  'P0001', 'invalid_state', 'approve alone from in_check is invalid_state');
select tests.act_as(:'r2');
select public.disagree_addendum('00000000-0000-0000-0000-000000000286', 'Back to review.');
select tests.act_as(:'r1');
select lives_ok(format('select public.approve_addendum_alone(%L)', '00000000-0000-0000-0000-000000000286'),
  'the reviewer approves alone');
reset role;
select is((select row(state::text, single_reviewer, checker_id is null)::text
             from public.addenda where id = '00000000-0000-0000-0000-000000000286'),
          row('approved', true, true)::text, 'in_review -> approved with single_reviewer stamped');
select is((select detail from public.audit_log
            where action = 'approve_addendum_alone'
              and detail ->> 'addendum_id' = '00000000-0000-0000-0000-000000000286'),
          jsonb_build_object('addendum_id', '00000000-0000-0000-0000-000000000286', 'number', 4,
                             'from', 'in_review', 'to', 'approved', 'fallback', 'no second reviewer available'),
  'approve_addendum_alone is audited once with the fallback detail');
select tests.act_as(:'r1');
select public.reopen_addendum_review('00000000-0000-0000-0000-000000000286', 'Needs a real check.');
reset role;
select is((select row(state::text, single_reviewer)::text
             from public.addenda where id = '00000000-0000-0000-0000-000000000286'),
          row('in_review', false)::text, 'reopen clears single_reviewer');

-- Reassigning the review to the current checker is same_person. The public functions never leave a checker on an
-- in_review row (start and reopen clear it, disagree runs before a checker is set), so the fixture sets it directly.
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, narrative, created_by, reviewer_id, checker_id,
                            latest_submitted_at)
select '00000000-0000-0000-0000-000000000287', :'s1', 5, 'in_review', s.data, 'Fifth.', :'author', :'r1', :'r2', now()
  from public.solicitations s where s.id = :'s1';
select tests.act_as(:'r3');
select throws_ok(format('select public.reassign_addendum_review(%L, %L)', '00000000-0000-0000-0000-000000000287',
    :'r2'), 'P0001', 'same_person', 'reassigning the review to the current checker is same_person');

-- ===========================================================================
-- After close every transition is bids_closed.
-- ===========================================================================
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, narrative, created_by, reviewer_id,
                            checker_id, latest_submitted_at)
select v.id::uuid, :'s2', v.n, v.st::public.addendum_state, s.data, 'x', :'author', v.rev::uuid, v.chk::uuid, now()
  from public.solicitations s,
       (values ('00000000-0000-0000-0000-000000000291', 1, 'submitted', null,  null),
               ('00000000-0000-0000-0000-000000000292', 2, 'in_review', :'r1', null),
               ('00000000-0000-0000-0000-000000000293', 3, 'in_check',  :'r1', null),
               ('00000000-0000-0000-0000-000000000294', 4, 'approved',  :'r1', :'r2')) v(id, n, st, rev, chk)
 where s.id = :'s2';
select tests.set_bid_due(:'s2', now() - interval '1 second');

select tests.act_as(:'r1');
select throws_ok(format('select public.start_addendum_review(%L)', '00000000-0000-0000-0000-000000000291'),
  'P0001', 'bids_closed', 'after close: start_addendum_review is bids_closed');
select throws_ok(format('select public.reassign_addendum_review(%L, %L)', '00000000-0000-0000-0000-000000000292',
    :'r3'), 'P0001', 'bids_closed', 'after close: reassign_addendum_review is bids_closed');
select throws_ok(format('select public.return_addendum(%L, %L)', '00000000-0000-0000-0000-000000000292',
    '[{"field": null, "body": "x"}]'), 'P0001', 'bids_closed', 'after close: return_addendum is bids_closed');
select throws_ok(format('select public.send_addendum_to_check(%L)', '00000000-0000-0000-0000-000000000292'),
  'P0001', 'bids_closed', 'after close: send_addendum_to_check is bids_closed');
select throws_ok(format('select public.approve_addendum_alone(%L)', '00000000-0000-0000-0000-000000000292'),
  'P0001', 'bids_closed', 'after close: approve_addendum_alone is bids_closed');
select throws_ok(format('select public.reopen_addendum_review(%L, %L)', '00000000-0000-0000-0000-000000000294', 'x'),
  'P0001', 'bids_closed', 'after close: reopen_addendum_review is bids_closed');
select tests.act_as(:'r2');
select throws_ok(format('select public.approve_addendum_check(%L)', '00000000-0000-0000-0000-000000000293'),
  'P0001', 'bids_closed', 'after close: approve_addendum_check is bids_closed');
select throws_ok(format('select public.disagree_addendum(%L, %L)', '00000000-0000-0000-0000-000000000293', 'x'),
  'P0001', 'bids_closed', 'after close: disagree_addendum is bids_closed');
reset role;
select is((select count(*)::int from public.audit_log where solicitation_id = :'s2'), 0,
  'refused calls after close wrote no audit rows');
select is((select count(*)::int from public.addendum_comments a join public.addenda d on d.id = a.addendum_id
            where d.solicitation_id = :'s2'), 0, 'refused calls after close wrote no comments');

-- s3: still open by now() (transaction start) but past due on the wall clock: the re-check after the lock refuses.
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, narrative, created_by, latest_submitted_at)
select '00000000-0000-0000-0000-000000000295', :'s3', 1, 'submitted', s.data, 'x', :'author', now()
  from public.solicitations s where s.id = :'s3';
select tests.set_bid_due(:'s3', clock_timestamp());
select ok(not app.bids_closed(:'s3'), 's3 is not closed by now()');
select tests.act_as(:'r1');
select throws_ok(format('select public.start_addendum_review(%L)', '00000000-0000-0000-0000-000000000295'),
  'P0001', 'bids_closed', 'the clock_timestamp() re-check after the lock raises bids_closed');

select * from finish();
rollback;
