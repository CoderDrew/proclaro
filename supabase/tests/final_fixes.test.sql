-- 0025: final review fixes for slice 2b. Ruling 14 (originals log and bond cure only in bid_review after close),
-- Ruling 13 (recall_recap, recall_award), recap_draft canCheck/canRecall, and a post-close void counting as review.
begin;

select plan(56);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

-- The error a statement raises, as 'sqlstate|message', or 'ok'.
create function tests.ff_error(p_sql text)
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
grant execute on function tests.ff_error(text) to anon, authenticated, service_role;

-- A closed solicitation (due an hour ago) with two schedule items and no alternates (or open, due in an hour).
create function tests.ff_sol(p_agency uuid, p_author uuid, p_due timestamptz default now() - interval '1 hour')
returns uuid
language sql
security definer
set search_path = ''
as $$
  select tests.make_published_solicitation(p_agency, p_author, p_due,
    jsonb_build_object('fundingAmountCents', 15000000, 'schedule', jsonb_build_object(
      'items', jsonb_build_array(jsonb_build_object('name', 'Base bid', 'description', 'Site work'),
                                 jsonb_build_object('name', 'Item 2', 'description', 'Roofing')),
      'alternates', '[]'::jsonb)));
$$;

-- ---------------------------------------------------------------------------
-- Shape and privileges
-- ---------------------------------------------------------------------------
select has_function('public', 'recall_recap', array['uuid'], 'public.recall_recap exists');
select has_function('public', 'recall_award', array['uuid'], 'public.recall_award exists');
select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where (n.nspname = 'public' and p.proname in ('recall_recap', 'recall_award', 'recap_draft',
                                                          'void_bid_original', 'log_bid_original',
                                                          'submit_cure_bond', 'my_bid_outcome'))
               or (n.nspname = 'app' and p.proname in ('was_evaluation_reviewer', 'can_upload_bid_file'))),
  '0025 functions: security definer with an empty search_path');
select ok((select bool_and(has_function_privilege('authenticated', f, 'execute')
                           and not has_function_privilege('anon', f, 'execute')
                           and not has_function_privilege('service_role', f, 'execute')
                           and not has_function_privilege('public', f, 'execute'))
             from unnest(array['public.recall_recap(uuid)', 'public.recall_award(uuid)', 'public.recap_draft(uuid)',
                               'public.void_bid_original(uuid, text)',
                               'public.log_bid_original(uuid, text, int, public.original_item, timestamptz)',
                               'public.submit_cure_bond(uuid, text, text)', 'public.my_bid_outcome(uuid)']) f),
  '0025 public functions: authenticated only');
select ok(not has_function_privilege('authenticated', 'app.was_evaluation_reviewer(uuid, uuid)', 'execute')
      and not has_function_privilege('anon', 'app.was_evaluation_reviewer(uuid, uuid)', 'execute')
      and not has_function_privilege('service_role', 'app.was_evaluation_reviewer(uuid, uuid)', 'execute'),
  'app.was_evaluation_reviewer: no execute for API roles');

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000ef1', 'FF Office', 'office'),
  ('00000000-0000-0000-0000-000000000ea1', 'FF Agency', 'agency');
\set agency '00000000-0000-0000-0000-000000000ea1'
\set office '00000000-0000-0000-0000-000000000ef1'
select tests.make_user('ff.author@test.test', :'agency') as author \gset
select tests.make_user('ff.r1@test.test', :'office') as r1 \gset
select tests.make_user('ff.r2@test.test', :'office') as r2 \gset
select tests.make_user('ff.r3@test.test', :'office') as r3 \gset
select tests.make_bidder('ff.a@test.test', 'FF Bidder A') as bidder_a \gset
select tests.make_bidder('ff.b@test.test', 'FF Bidder B') as bidder_b \gset

-- sol_post: posted recap (I1). sol_void: bid review, voids (I6). sol_cure: a pending paper-bond cure (I1).
-- sol_rec: recall (I2). sol_open: bids still sealed.
select tests.ff_sol(:'agency', :'author') as sol_post \gset
select tests.ff_sol(:'agency', :'author') as sol_void \gset
select tests.ff_sol(:'agency', :'author') as sol_cure \gset
select tests.ff_sol(:'agency', :'author') as sol_rec \gset
select tests.ff_sol(:'agency', :'author', now() + interval '1 hour') as sol_open \gset

select tests.make_closed_bid(:'sol_post', :'bidder_a', '{3000000,1000000}', '{}', 'paper', null, true, true) as p_a \gset
select tests.make_closed_bid(:'sol_post', :'bidder_b', '{3500000,1000000}', '{}', 'paper', null, true, true) as p_b \gset
select tests.make_closed_bid(:'sol_void', :'bidder_a', '{3000000,1000000}', '{}', 'paper', null, true, true) as v_a \gset
select tests.make_closed_bid(:'sol_cure', :'bidder_a', '{3000000,1000000}', '{}', 'paper', null, true, false) as c_a \gset
select tests.make_closed_bid(:'sol_rec', :'bidder_a', '{3000000,1000000}', '{}', 'paper', null, true, true) as r_a \gset
select tests.make_closed_bid(:'sol_rec', :'bidder_b', '{3500000,1000000}', '{}', 'paper', null, true, true) as r_b \gset
select reference as ref_p_a from public.bids where id = :'p_a' \gset
select reference as ref_v_a from public.bids where id = :'v_a' \gset
select id as p_a_signed from public.bid_original_log where bid_id = :'p_a' and item = 'signed_form' \gset
select id as v_a_signed from public.bid_original_log where bid_id = :'v_a' and item = 'signed_form' \gset

-- ---------------------------------------------------------------------------
-- I1 / Ruling 14: after the recap is posted, no void, log or cure can change a status.
-- ---------------------------------------------------------------------------
select tests.act_as(:'r1');
select public.set_bid_outcome(:'p_a', 'accepted', null, 'In order');
select public.set_bid_outcome(:'p_b', 'accepted', null, 'In order');
select public.post_recap_alone(:'sol_post');
select tests.act_as(:'bidder_a');
select is((select status from public.my_bid_outcome(:'p_a')), 'accepted', 'fixture: A sees accepted after posting');

select tests.act_as(:'r1');
select is(tests.ff_error(format('select public.void_bid_original(%L, %L)', :'p_a_signed', 'Typo')),
  'P0001|invalid_state', 'void_bid_original after recap_posted -> invalid_state');
select is(tests.ff_error(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol_post', :'ref_p_a', 'signed_form')),
  'P0001|invalid_state', 'log_bid_original after recap_posted -> invalid_state');
select is(tests.ff_error(format('select public.void_bid_original(%L, %L)', :'p_a_signed', '')),
  'P0001|reason_required', 'void_bid_original: reason_required still comes before the stage');
reset role;
select is((select count(*)::int from public.bid_original_log where solicitation_id = :'sol_post'), 4,
  'refused void and log wrote no log row (2 bids x signed form and bond)');
select is((select count(*)::int from public.bid_audit_log
            where solicitation_id = :'sol_post' and action in ('void_bid_original', 'log_bid_original')), 0,
  'refused void and log wrote no audit row');
select tests.act_as(:'bidder_a');
select is((select status from public.my_bid_outcome(:'p_a')), 'accepted', 'after the refused void: A still sees accepted');
reset role;

-- In bid review a post-close void and log still work (and lock the evaluation; I6 below).
select is((select stage::text from public.evaluations where solicitation_id = :'sol_void'), null,
  'fixture: sol_void has no evaluation row yet');
select tests.act_as(:'r2');
select isnt(public.void_bid_original(:'v_a_signed', 'Logged against the wrong bid'), null,
  'void_bid_original in bid_review after close -> ok');
select isnt(public.log_bid_original(:'sol_void', :'ref_v_a', 1, 'signed_form'), null,
  'log_bid_original in bid_review after close -> ok');
reset role;
select is((select stage::text from public.evaluations where solicitation_id = :'sol_void'), 'bid_review',
  'a post-close void creates the evaluation row (lock_evaluation) at bid_review');

-- Before close nothing changes: an open solicitation's log needs no evaluation row and creates none.
select tests.make_closed_bid(:'sol_open', :'bidder_b', '{3000000,1000000}', '{}', 'paper', null, false, false) as o_b \gset
select reference as ref_o_b from public.bids where id = :'o_b' \gset
select tests.act_as(:'r1');
select public.log_bid_original(:'sol_open', :'ref_o_b', 1, 'signed_form') as o_entry \gset
select isnt(:'o_entry'::uuid, null, 'log_bid_original before close -> ok');
select isnt(public.void_bid_original(:'o_entry', 'Wrong envelope'), null, 'void_bid_original before close -> ok');
reset role;
select is((select count(*)::int from public.evaluations where solicitation_id = :'sol_open'), 0,
  'before close: no evaluation row is created');

-- The cure: uploads and submit_cure_bond only in bid_review.
select tests.act_as(:'bidder_a');
select is((select status from public.my_bid_cure(:'c_a')), 'pending', 'fixture: c_a has a pending cure');
select gen_random_uuid() as up1 \gset
select lives_ok(format($q$insert into storage.objects (bucket_id, name, metadata) values ('bid-files', 'bids/%s/%s/bond.pdf',
  '{"eTag":"\"ff\"","size":2048}')$q$, :'c_a', :'up1'), 'bid_review: the pending owner can upload a cure bond');
reset role;
-- Stand-in for a stage the API cannot reach with a pending cure (cure_pending blocks send and post).
insert into public.evaluations (solicitation_id, stage) values (:'sol_cure', 'recap_posted')
on conflict (solicitation_id) do update set stage = excluded.stage;
select tests.act_as(:'bidder_a');
select throws_ok(format($q$insert into storage.objects (bucket_id, name, metadata) values ('bid-files', 'bids/%s/%s/bond.pdf',
  '{"eTag":"\"ff\"","size":1}')$q$, :'c_a', gen_random_uuid()), '42501', null,
  'past bid_review: a pending owner cannot upload (can_upload_bid_file)');
select is(tests.ff_error(format('select public.submit_cure_bond(%L, %L, %L)', :'c_a',
                                'bids/' || :'c_a' || '/' || :'up1' || '/bond.pdf', 'bond.pdf')),
  'P0001|invalid_state', 'past bid_review: submit_cure_bond -> invalid_state');
reset role;
select is((select count(*)::int from public.bid_cure_files where bid_id = :'c_a'), 0, 'no cure file was recorded');
update public.evaluations set stage = 'bid_review' where solicitation_id = :'sol_cure';
select tests.act_as(:'bidder_a');
select public.submit_cure_bond(:'c_a', 'bids/' || :'c_a' || '/' || :'up1' || '/bond.pdf', 'bond.pdf') as cured_at \gset
reset role;
select is((select uploaded_at from public.bid_cure_files where bid_id = :'c_a'), :'cured_at'::timestamptz,
  'bid_review: submit_cure_bond records the upload, stamped with the time it returns');
select ok(:'cured_at'::timestamptz < (select app.cure_deadline(:'sol_cure')), 'the recorded upload is before the deadline');

-- Lock mode (re-review fix): the bid-row locks are FOR NO KEY UPDATE, not FOR UPDATE, so writers that hold the
-- evaluation lock can still take the FK KEY SHARE on the bid row. pgrowlocks reads this transaction's own row locks.
create extension if not exists pgrowlocks;
select ok((select 'For No Key Update' = any(modes) and not 'For Update' = any(modes) from pgrowlocks('public.bids') l
            where l.locked_row = (select ctid from public.bids where id = :'v_a')),
  'void/log after close lock the bid row FOR NO KEY UPDATE (not FOR UPDATE)');
select ok((select 'For No Key Update' = any(modes) and not 'For Update' = any(modes) from pgrowlocks('public.bids') l
            where l.locked_row = (select ctid from public.bids where id = :'c_a')),
  'submit_cure_bond locks the bid row FOR NO KEY UPDATE (not FOR UPDATE)');

-- ---------------------------------------------------------------------------
-- I6: a post-close void counts as reviewing these bids; a pre-close one does not.
-- ---------------------------------------------------------------------------
select is(app.was_evaluation_reviewer(:'sol_void', :'r2'), true, 'was_evaluation_reviewer: r2 voided after close -> true');
select is(app.was_evaluation_reviewer(:'sol_void', :'r3'), false, 'was_evaluation_reviewer: r3 did nothing -> false');
insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail, created_at)
select :'sol_void', :'v_a', :'r3', 'void_bid_original', '{}'::jsonb, s.bid_due_at - interval '2 hours'
  from public.solicitations s where s.id = :'sol_void';
select is(app.was_evaluation_reviewer(:'sol_void', :'r3'), false,
  'was_evaluation_reviewer: a void before the bid due time -> false');

-- ---------------------------------------------------------------------------
-- I2 / Ruling 13: recall_recap and recap_draft's canCheck / canRecall.
-- ---------------------------------------------------------------------------
select tests.act_as(:'r1');
select public.set_bid_outcome(:'r_a', 'accepted', null, 'In order');
select tests.act_as(:'r3');
select public.set_bid_outcome(:'r_b', 'accepted', null, 'In order');
select tests.act_as(:'r1');
select is(tests.ff_error(format('select public.recall_recap(%L)', :'sol_rec')), 'P0001|invalid_state',
  'recall_recap in bid_review -> invalid_state');
select is(tests.ff_error(format('select public.recall_recap(%L)', :'sol_open')), 'P0001|sealed',
  'recall_recap before close -> sealed');
select public.send_recap_to_check(:'sol_rec');
select is(public.recap_draft(:'sol_rec') - 'recap' - 'preparedBy', '{"canCheck": false, "canRecall": true}'::jsonb,
  'recap_draft for the sender: canCheck false, canRecall true');
select tests.act_as(:'r2');
select is(public.recap_draft(:'sol_rec') - 'recap' - 'preparedBy', '{"canCheck": true, "canRecall": false}'::jsonb,
  'recap_draft for an office user who did not review: canCheck true, canRecall false');
select is(tests.ff_error(format('select public.recall_recap(%L)', :'sol_rec')), 'P0001|not_authorized',
  'recall_recap by another office user -> not_authorized');
select tests.act_as(:'r3');
select is(public.recap_draft(:'sol_rec') - 'recap' - 'preparedBy', '{"canCheck": false, "canRecall": false}'::jsonb,
  'recap_draft for a past reviewer who did not send it: canCheck false, canRecall false');
select tests.act_as(:'author');
select is(tests.ff_error(format('select public.recall_recap(%L)', :'sol_rec')), 'P0001|not_authorized',
  'recall_recap by the agency -> not_authorized');
select tests.act_as(:'bidder_a');
select is(tests.ff_error(format('select public.recall_recap(%L)', :'sol_rec')), 'P0001|not_authorized',
  'recall_recap by a bidder -> not_authorized');
select tests.act_as_anon();
select is(tests.ff_error(format('select public.recall_recap(%L)', :'sol_rec')),
  '42501|permission denied for function recall_recap', 'anon cannot execute recall_recap');

select tests.act_as(:'r1');
select public.recall_recap(:'sol_rec');
reset role;
select is((select row(stage::text, recap_draft)::text from public.evaluations where solicitation_id = :'sol_rec'),
  row('bid_review', null::jsonb)::text, 'recall_recap -> bid_review with the draft cleared');
select is((select array_agg(detail) from public.bid_audit_log
            where solicitation_id = :'sol_rec' and action = 'recall_recap' and actor_id = :'r1'),
  array['{"kind": "recap"}'::jsonb], 'recall_recap audited once with {kind}');
select tests.act_as(:'r1');
select is(public.recap_draft(:'sol_rec'), null::jsonb, 'after the recall: recap_draft -> null');
select is(tests.ff_error(format('select public.recall_recap(%L)', :'sol_rec')), 'P0001|invalid_state',
  'recall_recap again -> invalid_state');
-- The sender is no longer stuck: the recorded fallback applies.
select public.post_recap_alone(:'sol_rec');
reset role;
select is((select stage::text from public.evaluations where solicitation_id = :'sol_rec'), 'recap_posted',
  'after the recall the sender can post alone -> recap_posted');
select tests.act_as(:'r1');
select is(tests.ff_error(format('select public.recall_recap(%L)', :'sol_rec')), 'P0001|invalid_state',
  'recall_recap after posting -> invalid_state');

-- ---------------------------------------------------------------------------
-- I2 / Ruling 13: recall_award.
-- ---------------------------------------------------------------------------
select is(tests.ff_error(format('select public.recall_award(%L)', :'sol_rec')), 'P0001|invalid_state',
  'recall_award in recap_posted -> invalid_state');
select is(tests.ff_error(format('select public.recall_award(%L)', :'sol_open')), 'P0001|sealed',
  'recall_award before close -> sealed');
select tests.act_as(:'author');
select public.pick_award(:'sol_rec', :'r_a', null);
select tests.act_as(:'r1');
select public.send_award_to_check(:'sol_rec');
select tests.act_as(:'r2');
select is(tests.ff_error(format('select public.recall_award(%L)', :'sol_rec')), 'P0001|not_authorized',
  'recall_award by another office user -> not_authorized');
select tests.act_as(:'author');
select is(tests.ff_error(format('select public.recall_award(%L)', :'sol_rec')), 'P0001|not_authorized',
  'recall_award by the agency -> not_authorized');
select tests.act_as_anon();
select is(tests.ff_error(format('select public.recall_award(%L)', :'sol_rec')),
  '42501|permission denied for function recall_award', 'anon cannot execute recall_award');

select tests.act_as(:'r1');
select public.recall_award(:'sol_rec');
reset role;
select is((select row(stage::text, award_disagreed_at)::text from public.evaluations where solicitation_id = :'sol_rec'),
  row('recap_posted', null::timestamptz)::text, 'recall_award -> recap_posted, award_disagreed_at not stamped');
select is((select array_agg(bid_id) from public.bid_audit_log
            where solicitation_id = :'sol_rec' and action = 'recall_award' and actor_id = :'r1'),
  array[:'r_a'::uuid], 'recall_award audited once, on the picked bid');
select tests.act_as(:'r1');
select is(tests.ff_error(format('select public.recall_award(%L)', :'sol_rec')), 'P0001|invalid_state',
  'recall_award again -> invalid_state');
-- The same pick can be posted alone (no fresh pick needed after a recall).
select public.post_award_alone(:'sol_rec');
reset role;
select is((select stage::text from public.evaluations where solicitation_id = :'sol_rec'), 'awarded',
  'after the recall the sender can post the same pick alone -> awarded');
select tests.act_as(:'r1');
select is(tests.ff_error(format('select public.recall_award(%L)', :'sol_rec')), 'P0001|invalid_state',
  'recall_award after the award is posted -> invalid_state');
reset role;

select * from finish();
rollback;
