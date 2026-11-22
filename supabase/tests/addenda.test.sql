-- 0027: addenda drafting. public.addenda / public.addendum_comments (read through RLS by staff only, no API write
-- grants), app.lock_addendum, app.addendum_effective_state, app.locked_fields, and the agency functions
-- start_addendum, save_addendum, submit_addendum, plus withdraw_addendum (agency from draft, office from any
-- unpublished state).
begin;

select plan(75);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000271', 'AD Office',   'office'),
  ('00000000-0000-0000-0000-000000000272', 'AD Agency A', 'agency'),
  ('00000000-0000-0000-0000-000000000273', 'AD Agency B', 'agency');

select tests.make_user('ad.author@test.test', '00000000-0000-0000-0000-000000000272') as author \gset
select tests.make_user('ad.other@test.test',  '00000000-0000-0000-0000-000000000273') as other_agency \gset
select tests.make_user('ad.r1@test.test',     '00000000-0000-0000-0000-000000000271') as r1 \gset
select tests.make_user('ad.r2@test.test',     '00000000-0000-0000-0000-000000000271') as r2 \gset
select tests.make_bidder('ad.bidder@test.test', 'AD Bidder') as bidder \gset

-- s1: open for bids (funding frozen at 15,000,000). s2: open, used for the close scenario. s3: already closed.
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000272', :'author',
  now() + interval '20 days') as s1 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000272', :'author',
  now() + interval '20 days') as s2 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000272', :'author',
  now() - interval '1 hour') as s3 \gset

-- ===========================================================================
-- Schema objects
-- ===========================================================================
select has_type('public', 'addendum_state', 'addendum_state exists');
select enum_has_labels('public', 'addendum_state',
  array['draft', 'submitted', 'in_review', 'in_check', 'approved', 'published', 'withdrawn'],
  'addendum_state has the seven states in order');
select has_table('public', 'addenda', 'addenda exists');
select has_table('public', 'addendum_comments', 'addendum_comments exists');
select has_function('app', 'lock_addendum', array['uuid'], 'app.lock_addendum(uuid) exists');
select has_function('app', 'addendum_effective_state', array['addenda'], 'app.addendum_effective_state exists');
select has_function('app', 'locked_fields', 'app.locked_fields() exists');
select has_function('app', 'require_owning_agency', array['uuid'], 'app.require_owning_agency(uuid) exists');
select has_function('app', 'require_addendum_window', array['uuid'], 'app.require_addendum_window(uuid) exists');
select has_function('public', 'start_addendum', array['uuid'], 'start_addendum(uuid) exists');
select has_function('public', 'save_addendum', array['uuid', 'jsonb', 'text'], 'save_addendum exists');
select has_function('public', 'submit_addendum', array['uuid'], 'submit_addendum(uuid) exists');
select has_function('public', 'withdraw_addendum', array['uuid', 'text'], 'withdraw_addendum exists');

-- Parity with src/domain/addendum/lockedFields.ts (lockedFields.test.ts parses the marker block in 0027).
select is(app.locked_fields(), array['releaseDate', 'adStart', 'adEnd', 'newspapers', 'category']::text[],
  'app.locked_fields() is the TS LOCKED_FIELDS list');

-- No API writes; anon has no read grant.
select ok(not has_table_privilege('authenticated', 'public.addenda', 'insert,update,delete'),
  'authenticated cannot write addenda directly');
select ok(not has_table_privilege('authenticated', 'public.addendum_comments', 'insert,update,delete'),
  'authenticated cannot write addendum_comments directly');
select ok(not has_table_privilege('anon', 'public.addenda', 'select'), 'anon cannot read addenda');
select ok(not has_table_privilege('anon', 'public.addendum_comments', 'select'), 'anon cannot read addendum_comments');
select ok(not has_function_privilege('authenticated', 'app.lock_addendum(uuid)', 'execute'),
  'app.lock_addendum is not callable through the API');

-- ===========================================================================
-- start_addendum: who may call it
-- ===========================================================================
select tests.act_as(:'bidder');
select throws_ok(format('select public.start_addendum(%L)', :'s1'), 'P0001', 'not_authorized',
  'a bidder cannot start an addendum');
select tests.act_as(:'other_agency');
select throws_ok(format('select public.start_addendum(%L)', :'s1'), 'P0001', 'not_authorized',
  'another agency cannot start an addendum');
select tests.act_as(:'r1');
select throws_ok(format('select public.start_addendum(%L)', :'s1'), 'P0001', 'not_authorized',
  'office staff cannot start an addendum');
select tests.act_as(:'author');
select throws_ok(format('select public.start_addendum(%L)', gen_random_uuid()), 'P0001', 'not_found',
  'start on a missing solicitation is not_found');
select throws_ok(format('select public.start_addendum(%L)', :'s3'), 'P0001', 'bids_closed',
  'start on a closed solicitation is bids_closed');

select public.start_addendum(:'s1') as a1 \gset

reset role;
select is((select row(number, state::text, narrative, created_by = :'author'::uuid, single_reviewer)::text
             from public.addenda where id = :'a1'),
          row(1, 'draft', '', true, false)::text,
  'Addendum 1 starts as an empty draft by the author');
select is((select data from public.addenda where id = :'a1'),
          (select s.data || jsonb_build_object('fundingAmountCents', 15000000)
             from public.solicitations s where s.id = :'s1'),
  'the draft copies the solicitation data plus the current funding amount');
select is((select detail from public.audit_log where solicitation_id = :'s1' and action = 'start_addendum'),
          jsonb_build_object('addendum_id', :'a1', 'number', 1, 'to', 'draft'),
  'start_addendum is audited with the addendum id and number');

select tests.act_as(:'author');
select throws_ok(format('select public.start_addendum(%L)', :'s1'), 'P0001', 'addendum_in_progress',
  'a second start while Addendum 1 is unpublished is addendum_in_progress');

-- ===========================================================================
-- save_addendum
-- ===========================================================================
reset role;
select data as d1 from public.addenda where id = :'a1' \gset

select tests.act_as(:'author');
select lives_ok(format('select public.save_addendum(%L, %L, %L)', :'a1',
    (:'d1'::jsonb) || '{"bidDueDate": "2030-01-15", "fundingAmountCents": 17000000}', 'Moved the bid date.'),
  'the author saves a change to unlocked fields');
reset role;
select is((select row(data ->> 'bidDueDate', data ->> 'fundingAmountCents', narrative)::text
             from public.addenda where id = :'a1'),
          row('2030-01-15', '17000000', 'Moved the bid date.')::text,
  'save stores the data and narrative');
select is((select count(*)::int from public.audit_log where solicitation_id = :'s1' and action = 'save_addendum'), 0,
  'save is not audited (autosave)');

select tests.act_as(:'author');
select throws_ok(format('select public.save_addendum(%L, %L, %L)', :'a1',
    (:'d1'::jsonb) || '{"releaseDate": "2030-01-01"}', ''),
  'P0001', 'locked_field', 'save changing releaseDate is locked_field');
select throws_ok(format('select public.save_addendum(%L, %L, %L)', :'a1',
    (:'d1'::jsonb) || '{"category": "services"}', ''),
  'P0001', 'locked_field', 'save changing category is locked_field');
select throws_ok(format('select public.save_addendum(%L, %L, %L)', :'a1', (:'d1'::jsonb) - 'shortTitle', ''),
  'P0001', 'invalid_data', 'save without a required key is invalid_data');
select throws_ok(format('select public.save_addendum(%L, %L, %L)', :'a1', '[]', ''),
  'P0001', 'invalid_data', 'save with non-object data is invalid_data');
select throws_ok(format('select public.save_addendum(%L, %L, %L)', gen_random_uuid(), :'d1', ''),
  'P0001', 'not_found', 'save of a missing addendum is not_found');

select tests.act_as(:'other_agency');
select throws_ok(format('select public.save_addendum(%L, %L, %L)', :'a1', :'d1', ''),
  'P0001', 'not_authorized', 'another agency cannot save the addendum');
select tests.act_as(:'r1');
select throws_ok(format('select public.save_addendum(%L, %L, %L)', :'a1', :'d1', ''),
  'P0001', 'not_authorized', 'office staff cannot save the addendum');

-- ===========================================================================
-- submit_addendum
-- ===========================================================================
select tests.act_as(:'author');
select public.save_addendum(:'a1', :'d1', '   ');
select throws_ok(format('select public.submit_addendum(%L)', :'a1'), 'P0001', 'narrative_required',
  'submit with a blank narrative is narrative_required');
select public.save_addendum(:'a1', :'d1', 'Changes in this addendum.');

select tests.act_as(:'other_agency');
select throws_ok(format('select public.submit_addendum(%L)', :'a1'), 'P0001', 'not_authorized',
  'another agency cannot submit the addendum');

select tests.act_as(:'author');
select lives_ok(format('select public.submit_addendum(%L)', :'a1'), 'the author submits Addendum 1');
reset role;
select is((select row(state::text, latest_submitted_at = now())::text from public.addenda where id = :'a1'),
          row('submitted', true)::text, 'submit moves to submitted and stamps latest_submitted_at');
select is((select detail from public.audit_log where solicitation_id = :'s1' and action = 'submit_addendum'),
          jsonb_build_object('addendum_id', :'a1', 'number', 1, 'from', 'draft', 'to', 'submitted'),
  'submit_addendum is audited with the addendum id and number');

select tests.act_as(:'author');
select throws_ok(format('select public.save_addendum(%L, %L, %L)', :'a1', :'d1', 'x'),
  'P0001', 'invalid_state', 'save in submitted is invalid_state');
select throws_ok(format('select public.submit_addendum(%L)', :'a1'), 'P0001', 'invalid_state',
  'submit twice is invalid_state');

-- ===========================================================================
-- withdraw_addendum
-- ===========================================================================
select throws_ok(format('select public.withdraw_addendum(%L, %L)', :'a1', 'No longer needed.'),
  'P0001', 'invalid_state', 'the agency cannot withdraw from submitted');
select tests.act_as(:'bidder');
select throws_ok(format('select public.withdraw_addendum(%L, %L)', :'a1', 'x'),
  'P0001', 'not_authorized', 'a bidder cannot withdraw');
select tests.act_as(:'other_agency');
select throws_ok(format('select public.withdraw_addendum(%L, %L)', :'a1', 'x'),
  'P0001', 'not_authorized', 'another agency cannot withdraw');
select tests.act_as(:'r1');
select throws_ok(format('select public.withdraw_addendum(%L, %L)', :'a1', '  '),
  'P0001', 'reason_required', 'withdraw with a blank reason is reason_required');
select throws_ok(format('select public.withdraw_addendum(%L, %L)', gen_random_uuid(), 'x'),
  'P0001', 'not_found', 'withdraw of a missing addendum is not_found');
select lives_ok(format('select public.withdraw_addendum(%L, %L)', :'a1', 'Superseded.'),
  'the office withdraws from submitted');
reset role;
select is((select row(state::text, withdrawn_reason)::text from public.addenda where id = :'a1'),
          row('withdrawn', 'Superseded.')::text, 'withdraw stores the state and reason');
select is((select detail from public.audit_log where solicitation_id = :'s1' and action = 'withdraw_addendum'),
          jsonb_build_object('addendum_id', :'a1', 'number', 1, 'from', 'submitted', 'to', 'withdrawn',
                             'reason', 'Superseded.'),
  'withdraw_addendum is audited with the addendum id, number and reason');

select tests.act_as(:'r1');
select throws_ok(format('select public.withdraw_addendum(%L, %L)', :'a1', 'Again.'),
  'P0001', 'invalid_state', 'a withdrawn addendum cannot be withdrawn again');

-- A withdrawn number is reused.
select tests.act_as(:'author');
select public.start_addendum(:'s1') as a1b \gset
reset role;
select is((select number from public.addenda where id = :'a1b'), 1,
  'start after withdrawing Addendum 1 is number 1 again');

-- The agency may withdraw its own draft.
select tests.act_as(:'author');
select lives_ok(format('select public.withdraw_addendum(%L, %L)', :'a1b', 'Started by mistake.'),
  'the agency withdraws its draft');

-- Numbers count published addenda only, and a live number is unique.
reset role;
insert into public.addenda (solicitation_id, number, state, data, created_by)
values (:'s1', 1, 'published', '{}', :'author');
select tests.act_as(:'author');
select public.start_addendum(:'s1') as a2 \gset
reset role;
select is((select number from public.addenda where id = :'a2'), 2, 'after a published Addendum 1 the next is 2');
select throws_ok(format($$insert into public.addenda (solicitation_id, number, state, data, created_by)
                          values (%L, 2, 'draft', '{}', %L)$$, :'s1', :'author'),
  '23505', null, 'two live addenda cannot share a number');
select throws_ok(format('update public.addenda set reviewer_id = %L, checker_id = %L where id = %L',
                        :'r1', :'r1', :'a2'),
  '23514', null, 'the reviewer cannot also be the checker');

-- ===========================================================================
-- app.lock_addendum and app.addendum_effective_state
-- ===========================================================================
select is((app.lock_addendum(:'a2')).id, :'a2'::uuid, 'lock_addendum returns the row');
select throws_ok(format('select app.lock_addendum(%L)', gen_random_uuid()), 'P0001', 'not_found',
  'lock_addendum of a missing addendum is not_found');

-- s2: an addendum left in_review when bidding closes.
select tests.act_as(:'author');
select public.start_addendum(:'s2') as c1 \gset
reset role;
update public.addenda set state = 'in_review', reviewer_id = :'r1' where id = :'c1';
select is((select app.addendum_effective_state(a) from public.addenda a where a.id = :'c1'), 'in_review',
  'before close the effective state is the stored state');
select tests.set_bid_due(:'s2', now() - interval '1 second');
select is((select app.addendum_effective_state(a) from public.addenda a where a.id = :'c1'), 'withdrawn',
  'after close an unpublished addendum is effectively withdrawn');
select is((select app.addendum_effective_state(a) from public.addenda a
            where a.solicitation_id = :'s1' and a.state = 'published'), 'published',
  'a published addendum stays published');
select tests.act_as(:'author');
select throws_ok(format('select public.start_addendum(%L)', :'s2'), 'P0001', 'bids_closed',
  'after close, start raises bids_closed, not addendum_in_progress');
-- A draft left on a closed solicitation can no longer be saved or submitted.
reset role;
insert into public.addenda (id, solicitation_id, number, state, data, narrative, created_by)
select '00000000-0000-0000-0000-000000000279', :'s2', 9, 'draft', s.data, 'x', :'author'
  from public.solicitations s where s.id = :'s2';
select data as d2 from public.addenda where id = '00000000-0000-0000-0000-000000000279' \gset
select tests.act_as(:'author');
select throws_ok(format('select public.save_addendum(%L, %L, %L)', '00000000-0000-0000-0000-000000000279', :'d2', 'x'),
  'P0001', 'bids_closed', 'save after close is bids_closed');
select throws_ok(format('select public.submit_addendum(%L)', '00000000-0000-0000-0000-000000000279'),
  'P0001', 'bids_closed', 'submit after close is bids_closed');

-- ===========================================================================
-- Visibility (RLS) and append-only comments
-- ===========================================================================
reset role;
insert into public.addendum_comments (addendum_id, field, body, kind, author_id)
values (:'a2', 'bidDueDate', 'Please confirm the date.', 'return', :'r1');

select tests.act_as(:'bidder');
select is((select count(*)::int from public.addenda where solicitation_id in (:'s1', :'s2')), 0,
  'a bidder selects 0 rows from addenda');
select is((select count(*)::int from public.addendum_comments where addendum_id = :'a2'), 0,
  'a bidder selects 0 addendum comments');
select tests.act_as(:'other_agency');
select is((select count(*)::int from public.addenda where solicitation_id in (:'s1', :'s2')), 0,
  'another agency selects 0 rows from addenda');
select tests.act_as(:'author');
select is((select count(*)::int from public.addenda where solicitation_id = :'s1'), 4,
  'the owning agency sees its solicitation''s addenda');
select is((select count(*)::int from public.addendum_comments where addendum_id = :'a2'), 1,
  'the owning agency sees the addendum comments');
select tests.act_as(:'r2');
select is((select count(*)::int from public.addenda where solicitation_id in (:'s1', :'s2')), 6,
  'office staff see every addendum');

reset role;
select throws_ok(format('update public.addendum_comments set body = %L where addendum_id = %L', 'x', :'a2'),
  'P0001', null, 'addendum_comments is append-only (update)');
select throws_ok(format('delete from public.addendum_comments where addendum_id = %L', :'a2'),
  'P0001', null, 'addendum_comments is append-only (delete)');

select * from finish();
rollback;
