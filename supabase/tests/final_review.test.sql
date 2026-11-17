-- 0006: reopen_review, same-person rule across reassignment, submit key check, publish path pinning and
-- bid_due_at recompute, and the narrowed `published` insert policy.
begin;

select plan(57);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000008f1', 'FR Office',   'office'),
  ('00000000-0000-0000-0000-0000000008a1', 'FR Agency A', 'agency');

select tests.make_user('fr.author@test.test', '00000000-0000-0000-0000-0000000008a1') as author \gset
select tests.make_user('fr.r1@test.test',     '00000000-0000-0000-0000-0000000008f1') as r1 \gset
select tests.make_user('fr.r2@test.test',     '00000000-0000-0000-0000-0000000008f1') as r2 \gset
select tests.make_user('fr.r3@test.test',     '00000000-0000-0000-0000-0000000008f1') as r3 \gset

insert into public.clauses (key, version, body) values
  ('fr-clause-a', 1, 'Plain clause A.'),
  ('fr-clause-b', 1, 'Plain clause B.');

-- 8c1 reopen walk, 8c2 approve-alone reopen, 8c3 reassign bypass, 8c4 earlier-round reviewer,
-- 8c5 submit key check, 8c6 publish paths/bid due, 8c7 publish without a bid due date.
insert into public.solicitations (id, agency_id, created_by, data)
select v.id::uuid, '00000000-0000-0000-0000-0000000008a1', :'author', tests.solicitation_data(jsonb_build_object('shortTitle', v.t))
from (values
  ('00000000-0000-0000-0000-0000000008c1', 'Reopen walk'),
  ('00000000-0000-0000-0000-0000000008c2', 'Reopen fallback'),
  ('00000000-0000-0000-0000-0000000008c3', 'Reassign bypass'),
  ('00000000-0000-0000-0000-0000000008c4', 'Earlier round'),
  ('00000000-0000-0000-0000-0000000008c6', 'Publish pins')
) as v(id, t);
insert into public.solicitations (id, agency_id, created_by, data) values
  ('00000000-0000-0000-0000-0000000008c5', '00000000-0000-0000-0000-0000000008a1', :'author', '{"shortTitle":"Keys"}'),
  ('00000000-0000-0000-0000-0000000008c7', '00000000-0000-0000-0000-0000000008a1', :'author',
   tests.solicitation_data('{"bidDueDate": null}'));

-- ===========================================================================
-- C1: approved -> reopen -> edit -> send_to_check -> approve -> publish
-- ===========================================================================
select tests.act_as(:'author');
select public.submit_solicitation('00000000-0000-0000-0000-0000000008c1');
select tests.act_as(:'r1');
select public.start_review('00000000-0000-0000-0000-0000000008c1');
select public.send_to_check('00000000-0000-0000-0000-0000000008c1');
select tests.act_as(:'r2');
select public.approve_check('00000000-0000-0000-0000-0000000008c1');

-- Guards
select tests.act_as(:'author');
select throws_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c1', 'dates')$$,
  'P0001', 'not_authorized', 'reopen: agency user refused');
select tests.act_as(:'r3');
select throws_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c1', 'dates')$$,
  'P0001', 'not_authorized', 'reopen: office staff who is neither reviewer nor checker refused');
select tests.act_as(:'r1');
select throws_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c1', '')$$,
  'P0001', 'reason_required', 'reopen: empty reason refused');
select throws_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c1', '   ')$$,
  'P0001', 'reason_required', 'reopen: whitespace reason refused');
select throws_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c1', null)$$,
  'P0001', 'reason_required', 'reopen: null reason refused');
select throws_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c4', 'dates')$$,
  'P0001', 'invalid_state', 'reopen: a draft is the wrong state');

reset role;
select is((select count(*)::int from public.audit_log
           where solicitation_id = '00000000-0000-0000-0000-0000000008c1' and action = 'reopen_review'),
  0, 'refused reopens write no audit rows');
select is((select count(*)::int from public.solicitation_clause_locks where solicitation_id = '00000000-0000-0000-0000-0000000008c1'),
  (select count(distinct key)::int from public.clauses), 'approved row holds its clause locks before reopen');

-- The checker reopens.
select tests.act_as(:'r2');
select lives_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c1', '  Release date needs correcting  ')$$,
  'the checker reopens with a reason');

reset role;
select ok((select state = 'in_review' and checker_id is null and not fallback_approved and reviewer_id = :'r1'::uuid
           from public.solicitations where id = '00000000-0000-0000-0000-0000000008c1'),
  'reopen: in_review, checker cleared, fallback false, reviewer kept');
select is((select count(*)::int from public.solicitation_clause_locks where solicitation_id = '00000000-0000-0000-0000-0000000008c1'),
  0, 'reopen deletes the clause locks');
select is((select detail ->> 'reason' from public.audit_log
           where solicitation_id = '00000000-0000-0000-0000-0000000008c1' and action = 'reopen_review'),
  'Release date needs correcting', 'reopen audit records the trimmed reason');
select is((select actor_id from public.audit_log
           where solicitation_id = '00000000-0000-0000-0000-0000000008c1' and action = 'reopen_review'),
  :'r2'::uuid, 'reopen audit records the actor');

select tests.act_as(:'r2');
select throws_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c1', 'again')$$,
  'P0001', 'invalid_state', 'reopen: in_review is the wrong state');

-- The reviewer corrects the release date with a logged reason.
select tests.act_as(:'r1');
select lives_ok(
  $$select public.office_update_data('00000000-0000-0000-0000-0000000008c1',
      (select data from public.solicitations where id = '00000000-0000-0000-0000-0000000008c1')
        || jsonb_build_object('releaseDate', to_char(app.today() + 8, 'YYYY-MM-DD')),
      'Release date corrected after reopen')$$,
  'reviewer edits the release date after reopen');
select lives_ok($$select public.send_to_check('00000000-0000-0000-0000-0000000008c1')$$, 'send to check after reopen');

reset role;
select is((select count(*)::int from public.solicitation_clause_locks where solicitation_id = '00000000-0000-0000-0000-0000000008c1'),
  (select count(distinct key)::int from public.clauses), 'send_to_check re-locks the clauses after reopen');

select tests.act_as(:'r2');
select lives_ok($$select public.approve_check('00000000-0000-0000-0000-0000000008c1')$$,
  'a different person approves after reopen');
select tests.act_as(:'r1');
select lives_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000008c1',
    'solicitations/00000000-0000-0000-0000-0000000008c1/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-0000000008c1/v1/bid-form.pdf',
    '{"k":1}', tests.bid_due_at((select data from public.solicitations where id = '00000000-0000-0000-0000-0000000008c1')))$$,
  'publish after reopen succeeds');

reset role;
select ok((select state = 'published' and release_date = app.today() + 8
           from public.solicitations where id = '00000000-0000-0000-0000-0000000008c1'),
  'published with the corrected release date');
select is((select array_agg(action order by id) from public.audit_log where solicitation_id = '00000000-0000-0000-0000-0000000008c1'),
  array['submit_solicitation','start_review','send_to_check','approve_check','reopen_review',
        'office_update_data','send_to_check','approve_check','publish_solicitation'],
  'audit trail of the reopen walk');

-- approve_alone, then reopen by the reviewer clears the fallback flag.
select tests.act_as(:'author');
select public.submit_solicitation('00000000-0000-0000-0000-0000000008c2');
select tests.act_as(:'r1');
select public.start_review('00000000-0000-0000-0000-0000000008c2');
select public.approve_alone('00000000-0000-0000-0000-0000000008c2');
select lives_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c2', 'Dates')$$,
  'the reviewer reopens a fallback approval');
reset role;
select ok((select state = 'in_review' and not fallback_approved and checker_id is null
           from public.solicitations where id = '00000000-0000-0000-0000-0000000008c2'),
  'reopen clears fallback_approved');
select is((select (detail ->> 'previous_fallback_approved')::boolean from public.audit_log
           where solicitation_id = '00000000-0000-0000-0000-0000000008c2' and action = 'reopen_review'),
  true, 'reopen audit records the cleared fallback');

-- ===========================================================================
-- Same-person rule across reassignment
-- ===========================================================================
select tests.act_as(:'author');
select public.submit_solicitation('00000000-0000-0000-0000-0000000008c3');
select tests.act_as(:'r1');
select public.start_review('00000000-0000-0000-0000-0000000008c3');
select public.office_update_data('00000000-0000-0000-0000-0000000008c3',
  (select data from public.solicitations where id = '00000000-0000-0000-0000-0000000008c3') || '{"longTitle":"Edited by R1"}',
  'R1 edit');
select public.reassign_review('00000000-0000-0000-0000-0000000008c3', :'r2');
select tests.act_as(:'r2');
select lives_ok($$select public.send_to_check('00000000-0000-0000-0000-0000000008c3')$$, 'R2 sends to check after reassignment');

select tests.act_as(:'r1');
select throws_ok($$select public.approve_check('00000000-0000-0000-0000-0000000008c3')$$,
  'P0001', 'same_person', 'a former reviewer in this round cannot approve the check');
select throws_ok($$select public.disagree('00000000-0000-0000-0000-0000000008c3', 'no', null)$$,
  'P0001', 'same_person', 'a former reviewer in this round cannot disagree as checker');
select tests.act_as(:'r2');
select throws_ok($$select public.approve_check('00000000-0000-0000-0000-0000000008c3')$$,
  'P0001', 'same_person', 'the current reviewer cannot approve the check');
select tests.act_as(:'r3');
select lives_ok($$select public.approve_check('00000000-0000-0000-0000-0000000008c3')$$,
  'a different person (never a reviewer this round) approves');
reset role;
select is((select checker_id from public.solicitations where id = '00000000-0000-0000-0000-0000000008c3'),
  :'r3'::uuid, 'R3 recorded as checker');

-- A reviewer from an earlier round (before a return and resubmission) may check the new round.
select tests.act_as(:'author');
select public.submit_solicitation('00000000-0000-0000-0000-0000000008c4');
select tests.act_as(:'r1');
select public.start_review('00000000-0000-0000-0000-0000000008c4');
select public.return_to_agency('00000000-0000-0000-0000-0000000008c4', '[{"field":null,"body":"Fix it."}]');
select tests.act_as(:'author');
select public.submit_solicitation('00000000-0000-0000-0000-0000000008c4');
select tests.act_as(:'r2');
select public.start_review('00000000-0000-0000-0000-0000000008c4');
select public.send_to_check('00000000-0000-0000-0000-0000000008c4');
select tests.act_as(:'r1');
select lives_ok($$select public.approve_check('00000000-0000-0000-0000-0000000008c4')$$,
  'a reviewer from an earlier round may check after resubmission');

-- After a reopen, a former checker reassigned in as reviewer cannot then check.
select tests.act_as(:'r1');
select lives_ok($$select public.reopen_review('00000000-0000-0000-0000-0000000008c4', 'Dates')$$, 'checker reopens 8c4');
select tests.act_as(:'r2');
select public.reassign_review('00000000-0000-0000-0000-0000000008c4', :'r1');
select tests.act_as(:'r1');
select public.send_to_check('00000000-0000-0000-0000-0000000008c4');
select tests.act_as(:'r2');
select throws_ok($$select public.approve_check('00000000-0000-0000-0000-0000000008c4')$$,
  'P0001', 'same_person', 'the reviewer at reopen time cannot check after reassigning away');
select tests.act_as(:'r3');
select lives_ok($$select public.approve_check('00000000-0000-0000-0000-0000000008c4')$$,
  'a third person checks the reopened round');

-- ===========================================================================
-- submit_solicitation: required top-level keys
-- ===========================================================================
reset role;
select is(cardinality(app.required_data_keys()), 32, 'required key list has every schema key');

select tests.act_as(:'author');
select throws_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000008c5')$$,
  'P0001', 'invalid_data', 'submit refuses data missing required keys');
update public.solicitations set data = '[]'::jsonb where id = '00000000-0000-0000-0000-0000000008c5';
select throws_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000008c5')$$,
  'P0001', 'invalid_data', 'submit refuses data that is not an object');
update public.solicitations set data = tests.solicitation_data() - 'attachments'
 where id = '00000000-0000-0000-0000-0000000008c5';
select throws_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000008c5')$$,
  'P0001', 'invalid_data', 'submit refuses data missing one required key');
reset role;
select ok((select state = 'draft' and number is null from public.solicitations where id = '00000000-0000-0000-0000-0000000008c5'),
  'refused submissions leave the draft unnumbered');
select tests.act_as(:'author');
update public.solicitations set data = tests.solicitation_data() where id = '00000000-0000-0000-0000-0000000008c5';
select lives_ok($$select public.submit_solicitation('00000000-0000-0000-0000-0000000008c5')$$,
  'submit accepts data with every required key');

-- ===========================================================================
-- publish_solicitation pins paths and recomputes bid_due_at; published insert policy
-- ===========================================================================
select tests.act_as(:'author');
select public.submit_solicitation('00000000-0000-0000-0000-0000000008c6');
select public.submit_solicitation('00000000-0000-0000-0000-0000000008c7');
select tests.act_as(:'r1');
select public.start_review('00000000-0000-0000-0000-0000000008c6');
select public.send_to_check('00000000-0000-0000-0000-0000000008c6');
select public.start_review('00000000-0000-0000-0000-0000000008c7');
select public.send_to_check('00000000-0000-0000-0000-0000000008c7');
select tests.act_as(:'r2');
select public.approve_check('00000000-0000-0000-0000-0000000008c6');
select public.approve_check('00000000-0000-0000-0000-0000000008c7');

reset role;
select tests.bid_due_at(data) as due_c6 from public.solicitations where id = '00000000-0000-0000-0000-0000000008c6' \gset

-- Storage: office uploads into an approved solicitation's versioned folder only.
select tests.act_as(:'r1');
select lives_ok(
  $$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/00000000-0000-0000-0000-0000000008c6/v1/rfb.pdf')$$,
  'office uploads into an approved solicitation''s v1 folder');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/00000000-0000-0000-0000-0000000008c6/rfb.pdf')$$,
  '42501', null, 'published insert refuses a name without a version folder');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('published', 'elsewhere/rfb.pdf')$$,
  '42501', null, 'published insert refuses a name outside solicitations/');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/00000000-0000-0000-0000-0000000008c5/v1/rfb.pdf')$$,
  '42501', null, 'published insert refuses a solicitation that is not approved (submitted)');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/00000000-0000-0000-0000-0000000008c1/v1/extra.pdf')$$,
  '42501', null, 'published insert refuses a published solicitation''s folder');
select tests.act_as(:'author');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/00000000-0000-0000-0000-0000000008c6/v1/x.pdf')$$,
  '42501', null, 'agency cannot write to the published bucket');

select tests.act_as(:'r1');
select throws_ok(format($$select public.publish_solicitation('00000000-0000-0000-0000-0000000008c6',
    'solicitations/00000000-0000-0000-0000-0000000008c1/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/bid-form.pdf', '{"k":1}', %L)$$, :'due_c6'),
  'P0001', 'invalid_paths', 'publish refuses another solicitation''s rfb path');
select throws_ok(format($$select public.publish_solicitation('00000000-0000-0000-0000-0000000008c6',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v2/bid-form.pdf', '{"k":1}', %L)$$, :'due_c6'),
  'P0001', 'invalid_paths', 'publish refuses a different bid form path');
select throws_ok(format($$select public.publish_solicitation('00000000-0000-0000-0000-0000000008c6',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/../v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/bid-form.pdf', '{"k":1}', %L)$$, :'due_c6'),
  'P0001', 'invalid_paths', 'publish refuses a non-canonical rfb path');
select throws_ok(format($$select public.publish_solicitation('00000000-0000-0000-0000-0000000008c6',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/bid-form.pdf', '{"k":1}', %L)$$,
    (:'due_c6'::timestamptz + interval '1 hour')::text),
  'P0001', 'bid_due_mismatch', 'publish refuses a bid_due_at that differs from the data');
select throws_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000008c6',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/bid-form.pdf', '{"k":1}', null)$$,
  'P0001', 'invalid_data', 'the 0004 null guard still applies');
select throws_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000008c7',
    'solicitations/00000000-0000-0000-0000-0000000008c7/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-0000000008c7/v1/bid-form.pdf', '{"k":1}', now())$$,
  'P0001', 'invalid_data', 'publish refuses data without a bid due date');

reset role;
select is((select state::text from public.solicitations where id = '00000000-0000-0000-0000-0000000008c6'),
  'approved', 'refused publishes leave the row approved');
select is(:'due_c6'::timestamptz,
  ((select (data ->> 'bidDueDate')::date from public.solicitations where id = '00000000-0000-0000-0000-0000000008c6')
     + time '13:00') at time zone 'America/Denver',
  'bid due is 13:00 wall-clock in the settings zone');

select tests.act_as(:'r1');
select lives_ok(format($$select public.publish_solicitation('00000000-0000-0000-0000-0000000008c6',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-0000000008c6/v1/bid-form.pdf', '{"k":1}', %L)$$, :'due_c6'),
  'publish with pinned paths and the matching bid due succeeds');
reset role;
select is((select bid_due_at from public.solicitations where id = '00000000-0000-0000-0000-0000000008c6'),
  :'due_c6'::timestamptz, 'stored bid_due_at is the recomputed value');
select tests.act_as(:'r1');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/00000000-0000-0000-0000-0000000008c6/v1/late.pdf')$$,
  '42501', null, 'no uploads into a solicitation once it is published');

select * from finish();
rollback;
