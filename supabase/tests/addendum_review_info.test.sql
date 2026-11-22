-- 0034: public.addendum_review_info, the office review page's flags. Every can_* flag must match whether the
-- function it stands for would pass its guards for the caller, judged on the effective state.
begin;

select plan(41);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000341', 'RI Office', 'office'),
  ('00000000-0000-0000-0000-000000000342', 'RI Agency', 'agency');

select tests.make_user('ri.author@test.test', '00000000-0000-0000-0000-000000000342') as author \gset
select tests.make_user('ri.r1@test.test',     '00000000-0000-0000-0000-000000000341') as r1 \gset
select tests.make_user('ri.r2@test.test',     '00000000-0000-0000-0000-000000000341') as r2 \gset
select tests.make_user('ri.r3@test.test',     '00000000-0000-0000-0000-000000000341') as r3 \gset
select tests.make_bidder('ri.bidder@test.test', 'RI Bidder') as bidder \gset

-- s1: open (the workflow walk). s2: open, answers-due already passed. s3: closed. s4: not yet released.
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000342', :'author',
  now() + interval '20 days') as s1 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000342', :'author',
  now() + interval '20 days',
  jsonb_build_object('answersDue', jsonb_build_object('date', to_char(app.today() - 1, 'YYYY-MM-DD'),
                                                      'time', '13:00'))) as s2 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000342', :'author',
  now() - interval '1 hour') as s3 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000342', :'author',
  now() + interval '20 days') as s4 \gset
alter table public.solicitations disable trigger solicitations_published_frozen;
update public.solicitations set release_date = app.today() + 3 where id = :'s4';
alter table public.solicitations enable trigger solicitations_published_frozen;

-- The names of the true flags, in column order, comma separated ('' when none). Runs as the current role.
create function pg_temp.flags(p_id uuid) returns text language sql as $$
  select concat_ws(',',
    case when i.can_start then 'start' end, case when i.can_return then 'return' end,
    case when i.can_send then 'send' end, case when i.can_approve then 'approve' end,
    case when i.can_disagree then 'disagree' end, case when i.can_approve_alone then 'approve_alone' end,
    case when i.can_reopen then 'reopen' end, case when i.can_publish then 'publish' end,
    case when i.can_withdraw then 'withdraw' end)
  from public.addendum_review_info(p_id) i;
$$;
grant execute on function pg_temp.flags(uuid) to authenticated;

-- ===========================================================================
-- Shape and grants
-- ===========================================================================
select has_function('public', 'addendum_review_info', array['uuid'], 'addendum_review_info(uuid) exists');
select ok((select p.prosecdef and p.proconfig @> array['search_path=""']
             from pg_proc p where p.oid = 'public.addendum_review_info(uuid)'::regprocedure),
  'addendum_review_info is security definer with an empty search_path');
select ok(has_function_privilege('authenticated', 'public.addendum_review_info(uuid)', 'execute'),
  'authenticated may execute addendum_review_info');
select ok(not has_function_privilege('anon', 'public.addendum_review_info(uuid)', 'execute')
      and not has_function_privilege('service_role', 'public.addendum_review_info(uuid)', 'execute')
      and not has_function_privilege('public', 'public.addendum_review_info(uuid)', 'execute'),
  'anon, service_role and public may not execute addendum_review_info');

-- ===========================================================================
-- s1: draft -> submitted -> in_review -> in_check -> in_review -> (reassigned) -> in_check -> approved
-- ===========================================================================
select tests.act_as(:'author');
select public.start_addendum(:'s1') as a1 \gset
reset role;
select data as d1 from public.addenda where id = :'a1' \gset

select tests.act_as(:'author');
select throws_ok(format('select * from public.addendum_review_info(%L)', :'a1'), 'P0001', 'not_authorized',
  'the agency author cannot read the review flags');
select tests.act_as(:'bidder');
select throws_ok(format('select * from public.addendum_review_info(%L)', :'a1'), 'P0001', 'not_authorized',
  'a bidder cannot read the review flags');
select tests.act_as(:'r1');
select throws_ok(format('select * from public.addendum_review_info(%L)', gen_random_uuid()), 'P0001', 'not_found',
  'an unknown addendum is not_found');

select is(pg_temp.flags(:'a1'), 'withdraw', 'draft: the office may only withdraw');
select is((select row(state, effective_state, reviewer_id, checker_id, after_answers_due)::text
             from public.addendum_review_info(:'a1')),
          row('draft'::public.addendum_state, 'draft'::public.addendum_state, null::uuid, null::uuid, false)::text,
  'draft: state, effective state, no reviewer or checker, answers-due not passed');

select tests.act_as(:'author');
select public.save_addendum(:'a1', :'d1'::jsonb, 'Clarifies the roofing scope.');
select public.submit_addendum(:'a1');

select tests.act_as(:'r1');
select is(pg_temp.flags(:'a1'), 'start,withdraw', 'submitted: any office user may start or withdraw');
select tests.act_as(:'r2');
select is(pg_temp.flags(:'a1'), 'start,withdraw', 'submitted: the same for a second office user');

select tests.act_as(:'r1');
select public.start_addendum_review(:'a1');
select is(pg_temp.flags(:'a1'), 'return,send,approve_alone,withdraw',
  'in_review: the reviewer may return, send to check, approve alone or withdraw');
select is((select reviewer_id from public.addendum_review_info(:'a1')), :'r1'::uuid, 'in_review: r1 is the reviewer');
select tests.act_as(:'r2');
select is(pg_temp.flags(:'a1'), 'withdraw', 'in_review: another office user may only withdraw');
select throws_ok(format('select public.send_addendum_to_check(%L)', :'a1'), 'P0001', 'not_authorized',
  'parity: send_addendum_to_check refuses the non-reviewer');

select tests.act_as(:'r1');
select public.send_addendum_to_check(:'a1');
select is(pg_temp.flags(:'a1'), 'withdraw', 'in_check: the reviewer may not check their own review');
select throws_ok(format('select public.approve_addendum_check(%L)', :'a1'), 'P0001', 'same_person',
  'parity: approve_addendum_check refuses the reviewer');
select tests.act_as(:'r2');
select is(pg_temp.flags(:'a1'), 'approve,disagree,withdraw', 'in_check: another office user may approve or disagree');

select public.disagree_addendum(:'a1', 'Name the roofing sheet.');
select is(pg_temp.flags(:'a1'), 'withdraw', 'back in review: the checker is not the reviewer');
select tests.act_as(:'r1');
select is(pg_temp.flags(:'a1'), 'return,send,approve_alone,withdraw', 'back in review: r1 is still the reviewer');

-- Reassigned to r3: r1 stays a round reviewer (old_reviewer_id), so r1 may not check.
select public.reassign_addendum_review(:'a1', :'r3');
select is(pg_temp.flags(:'a1'), 'withdraw', 'after reassignment the old reviewer has only withdraw');
select tests.act_as(:'r3');
select is(pg_temp.flags(:'a1'), 'return,send,approve_alone,withdraw', 'after reassignment r3 is the reviewer');
select public.send_addendum_to_check(:'a1');
select tests.act_as(:'r1');
select is(pg_temp.flags(:'a1'), 'withdraw', 'in_check: the reassigned-away reviewer of this round may not check');
select throws_ok(format('select public.approve_addendum_check(%L)', :'a1'), 'P0001', 'same_person',
  'parity: approve_addendum_check refuses an earlier reviewer of the round');
select tests.act_as(:'r3');
select is(pg_temp.flags(:'a1'), 'withdraw', 'in_check: the current reviewer may not check');
select tests.act_as(:'r2');
select is(pg_temp.flags(:'a1'), 'approve,disagree,withdraw', 'in_check: r2 did not review in this round');

select public.approve_addendum_check(:'a1');
select is(pg_temp.flags(:'a1'), 'reopen,publish,withdraw', 'approved: the checker may reopen, publish or withdraw');
select is((select row(state, checker_id, reviewer_id)::text from public.addendum_review_info(:'a1')),
          row('approved'::public.addendum_state, :'r2'::uuid, :'r3'::uuid)::text,
  'approved: r2 is the checker, r3 the reviewer');
select tests.act_as(:'r3');
select is(pg_temp.flags(:'a1'), 'reopen,publish,withdraw', 'approved: the reviewer may reopen, publish or withdraw');
select tests.act_as(:'r1');
select is(pg_temp.flags(:'a1'), 'withdraw', 'approved: neither reviewer nor checker may only withdraw');
select throws_ok(format('select public.reopen_addendum_review(%L, %L)', :'a1', 'x'), 'P0001', 'not_authorized',
  'parity: reopen_addendum_review refuses neither reviewer nor checker');
select is((select after_answers_due from public.addendum_review_info(:'a1')), false,
  's1: the answers-due time has not passed');

-- Withdrawn: nothing.
select tests.act_as(:'r2');
select public.withdraw_addendum(:'a1', 'Superseded.');
select is(pg_temp.flags(:'a1'), '', 'withdrawn: no action');

-- ===========================================================================
-- s2: approved after the answers-due time (published snapshot, settings.timezone)
-- ===========================================================================
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, created_by, reviewer_id, single_reviewer)
values ('00000000-0000-0000-0000-0000000034b1', :'s2', 1, 'approved', '{}'::jsonb, :'author', :'r1', true);
select tests.act_as(:'r1');
select is(pg_temp.flags('00000000-0000-0000-0000-0000000034b1'), 'reopen,publish,withdraw',
  's2: approved alone, the reviewer may reopen, publish or withdraw');
select is((select after_answers_due from public.addendum_review_info('00000000-0000-0000-0000-0000000034b1')), true,
  's2: after_answers_due is true once the snapshot''s answers-due time has passed');

-- ===========================================================================
-- s3: closed. Every unpublished addendum counts as withdrawn; no flag is true.
-- ===========================================================================
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, created_by, reviewer_id, single_reviewer)
values ('00000000-0000-0000-0000-0000000034c1', :'s3', 1, 'approved', '{}'::jsonb, :'author', :'r1', true),
       ('00000000-0000-0000-0000-0000000034c2', :'s3', 2, 'submitted', '{}'::jsonb, :'author', null, false);
select tests.act_as(:'r1');
select is(pg_temp.flags('00000000-0000-0000-0000-0000000034c1'), '', 'closed, approved: no action, not even publish');
select is(pg_temp.flags('00000000-0000-0000-0000-0000000034c2'), '', 'closed, submitted: no action');
select is((select row(state, effective_state)::text
             from public.addendum_review_info('00000000-0000-0000-0000-0000000034c1')),
          row('approved'::public.addendum_state, 'withdrawn'::public.addendum_state)::text,
  'closed: the stored state is approved, the effective state withdrawn');

-- ===========================================================================
-- s4: not yet released. The review functions need app.bidding_open; publish and withdraw do not.
-- ===========================================================================
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, created_by, reviewer_id, single_reviewer)
values ('00000000-0000-0000-0000-0000000034d1', :'s4', 1, 'submitted', '{}'::jsonb, :'author', null, false);
select tests.act_as(:'r1');
select is(pg_temp.flags('00000000-0000-0000-0000-0000000034d1'), 'withdraw', 'unreleased, submitted: only withdraw');
select throws_ok(format('select public.start_addendum_review(%L)', '00000000-0000-0000-0000-0000000034d1'),
  'P0001', 'not_open', 'parity: start_addendum_review refuses before release');
reset role;
update public.addenda set state = 'approved', reviewer_id = :'r1', single_reviewer = true
 where id = '00000000-0000-0000-0000-0000000034d1';
select tests.act_as(:'r1');
select is(pg_temp.flags('00000000-0000-0000-0000-0000000034d1'), 'publish,withdraw',
  'unreleased, approved: publish and withdraw, but not reopen');

select * from finish();
rollback;
