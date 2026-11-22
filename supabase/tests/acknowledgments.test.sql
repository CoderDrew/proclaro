-- 0031: addendum acknowledgments. bid_acknowledgments (append-only, no API grants), acknowledge_addendum,
-- my_bid_acknowledgments, app.missing_acknowledgments, app.ack_note, and the missing-acknowledgment rule in
-- set_bid_outcome and review_bids. Pins Review Focus 5 (missing acknowledgment at review).
begin;

select plan(61);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000003c1', 'AK Office', 'office'),
  ('00000000-0000-0000-0000-0000000003c2', 'AK Agency', 'agency');

select tests.make_user('ak.author@test.test', '00000000-0000-0000-0000-0000000003c2') as author \gset
select tests.make_user('ak.r1@test.test',     '00000000-0000-0000-0000-0000000003c1') as r1 \gset
select tests.make_bidder('ak.a@test.test', 'AK Bidder A') as bidder_a \gset
select tests.make_bidder('ak.b@test.test', 'AK Bidder B') as bidder_b \gset

-- Test-only helper (rolled back with the transaction): fill a draft as the calling bidder (RLS applies), two item
-- prices, one alternate, paper bond, insurance and references uploaded and attached.
create function tests.t6_fill(p_bid uuid, p_tag text)
returns void
language plpgsql
as $$
declare
  v_ins text := 'bids/' || p_bid || '/' || gen_random_uuid() || '/ins-' || p_tag || '.pdf';
  v_ref text := 'bids/' || p_bid || '/' || gen_random_uuid() || '/ref-' || p_tag || '.pdf';
begin
  update public.bid_drafts
     set item_cents = '{12500000,234567}', alternate_cents = '{1500000}', bid_bond_choice = 'paper'
   where bid_id = p_bid;
  insert into storage.objects (bucket_id, name, metadata) values
    ('bid-files', v_ins, jsonb_build_object('eTag', '"' || p_tag || '-ins"', 'size', 2048, 'mimetype', 'application/pdf')),
    ('bid-files', v_ref, jsonb_build_object('eTag', '"' || p_tag || '-ref"', 'size', 4096, 'mimetype', 'application/pdf'));
  insert into public.bid_draft_files (bid_id, slot, path, file_name) values
    (p_bid, 'insurance', v_ins, 'ins-' || p_tag || '.pdf'),
    (p_bid, 'references', v_ref, 'ref-' || p_tag || '.pdf');
end;
$$;
grant execute on function tests.t6_fill(uuid, text) to authenticated;

-- ===========================================================================
-- Schema objects and grants
-- ===========================================================================
select has_table('public', 'bid_acknowledgments', 'bid_acknowledgments exists');
select col_is_pk('public', 'bid_acknowledgments', array['bid_id', 'addendum_number'],
  'bid_acknowledgments primary key is (bid_id, addendum_number)');
select col_not_null('public', 'bid_acknowledgments', 'acknowledged_at', 'acknowledged_at is not null');
select col_not_null('public', 'bid_acknowledgments', 'acknowledged_by', 'acknowledged_by is not null');
select fk_ok('public', 'bid_acknowledgments', 'bid_id', 'public', 'bids', 'id', 'bid_id references bids');
select ok(not has_table_privilege('authenticated', 'public.bid_acknowledgments', 'select')
      and not has_table_privilege('authenticated', 'public.bid_acknowledgments', 'insert')
      and not has_table_privilege('authenticated', 'public.bid_acknowledgments', 'update')
      and not has_table_privilege('authenticated', 'public.bid_acknowledgments', 'delete')
      and not has_table_privilege('anon', 'public.bid_acknowledgments', 'select')
      and not has_table_privilege('service_role', 'public.bid_acknowledgments', 'select'),
  'bid_acknowledgments: no direct grants to any API role');
select has_function('public', 'acknowledge_addendum', array['uuid', 'integer'], 'public.acknowledge_addendum exists');
select has_function('public', 'my_bid_acknowledgments', array['uuid'], 'public.my_bid_acknowledgments exists');
select has_function('app', 'missing_acknowledgments', array['uuid'], 'app.missing_acknowledgments exists');
select has_function('app', 'ack_note', array['integer[]'], 'app.ack_note exists');
select is(
  (select count(*)::int from pg_proc p
    where p.oid in ('public.acknowledge_addendum(uuid, int)'::regprocedure,
                    'public.my_bid_acknowledgments(uuid)'::regprocedure,
                    'app.missing_acknowledgments(uuid)'::regprocedure,
                    'app.ack_note(int[])'::regprocedure,
                    'public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text)'::regprocedure,
                    'public.review_bids(uuid)'::regprocedure)
      and p.prosecdef and p.proconfig @> array['search_path=""']),
  6, 'every 0031 function is security definer with an empty search_path');
select ok(has_function_privilege('authenticated', 'public.acknowledge_addendum(uuid, int)', 'execute')
      and has_function_privilege('authenticated', 'public.my_bid_acknowledgments(uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.review_bids(uuid)', 'execute')
      and has_function_privilege('authenticated',
            'public.set_bid_outcome(uuid, public.bid_outcome, public.non_responsive_ground, text)', 'execute'),
  'authenticated executes acknowledge_addendum, my_bid_acknowledgments, review_bids and set_bid_outcome');
select ok(not has_function_privilege('anon', 'public.acknowledge_addendum(uuid, int)', 'execute')
      and not has_function_privilege('anon', 'public.my_bid_acknowledgments(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.review_bids(uuid)', 'execute')
      and not has_function_privilege('service_role', 'public.acknowledge_addendum(uuid, int)', 'execute'),
  'anon and service_role cannot execute the public 0031 functions');
select ok(not has_function_privilege('authenticated', 'app.missing_acknowledgments(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'app.ack_note(int[])', 'execute')
      and not has_function_privilege('anon', 'app.missing_acknowledgments(uuid)', 'execute')
      and not has_function_privilege('service_role', 'app.ack_note(int[])', 'execute'),
  'app.missing_acknowledgments and app.ack_note are not callable through the API');
select ok(
  (select p.prosrc ~ 'app\.lock_bid\([^)]*\);\s*perform app\.require_before_due_clock\(v_bid\.solicitation_id\);'
     from pg_proc p where p.oid = 'public.acknowledge_addendum(uuid, int)'::regprocedure),
  'acknowledge_addendum re-checks the clock directly after app.lock_bid (Ruling 8)');
select ok(
  (select 'missing_addenda' = any(p.proargnames) from pg_proc p where p.oid = 'public.review_bids(uuid)'::regprocedure),
  'review_bids returns a missing_addenda column');

-- app.ack_note
select is(app.ack_note('{2}'), 'Did not acknowledge Addendum 2.', 'ack_note: one addendum');
select is(app.ack_note('{1,3}'), 'Did not acknowledge Addendum 1, 3.', 'ack_note: several, comma-space separated');

-- ===========================================================================
-- Fixtures. s1 has Addendum 1 and Addendum 2 published (versions 2 and 3) and Addendum 3 still a draft.
-- ===========================================================================
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000003c2', :'author',
  now() + interval '20 days') as s1 \gset
insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path, addendum_path,
                                          bid_due_at, published_at)
select s.id, v.n, s.published_snapshot, format('solicitations/%s/v%s/rfb.pdf', s.id, v.n),
       format('solicitations/%s/v%s/bid-form.pdf', s.id, v.n),
       case when v.n > 1 then format('solicitations/%s/v%s/addendum.pdf', s.id, v.n) end,
       s.bid_due_at, now() - make_interval(days => 10 - v.n)
  from public.solicitations s, (values (1), (2), (3)) v(n) where s.id = :'s1';
insert into public.addenda (solicitation_id, number, state, data, narrative, created_by, published_version)
select s.id, x.n, x.st::public.addendum_state, s.data, 'Addendum ' || x.n, :'author', x.pv
  from public.solicitations s,
       (values (1, 'published', 2), (2, 'published', 3), (3, 'draft', null)) x(n, st, pv)
 where s.id = :'s1';
select published_at as pub1 from public.solicitation_versions where solicitation_id = :'s1' and version = 2 \gset
select published_at as pub2 from public.solicitation_versions where solicitation_id = :'s1' and version = 3 \gset

-- A and B start bids and submit them.
select tests.act_as(:'bidder_a');
select public.start_bid(:'s1') as bid_a \gset
select tests.t6_fill(:'bid_a', 'a');
select lives_ok(format('select * from public.submit_bid(%L)', :'bid_a'), 'A submits');
select tests.act_as(:'bidder_b');
select public.start_bid(:'s1') as bid_b \gset
select tests.t6_fill(:'bid_b', 'b');
select lives_ok(format('select * from public.submit_bid(%L)', :'bid_b'), 'B submits');

-- ===========================================================================
-- acknowledge_addendum before close
-- ===========================================================================
select tests.act_as(:'bidder_a');
select lives_ok(format('select public.acknowledge_addendum(%L, 1)', :'bid_a'), 'A acknowledges Addendum 1');
select lives_ok(format('select public.acknowledge_addendum(%L, 1)', :'bid_a'), 'acknowledging again is a no-op');
reset role;
select is((select count(*)::int from public.bid_acknowledgments where bid_id = :'bid_a'), 1,
  'the second call wrote no second row');
select is((select acknowledged_by from public.bid_acknowledgments where bid_id = :'bid_a' and addendum_number = 1),
  :'bidder_a'::uuid, 'acknowledged_by is the caller');
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_a' and action = 'acknowledge_addendum'), 1,
  'one acknowledge_addendum audit row (the no-op is not audited)');
select is((select detail from public.bid_audit_log where bid_id = :'bid_a' and action = 'acknowledge_addendum'),
  '{"addendum_number": 1}'::jsonb, 'the audit detail names the addendum');
select is((select count(*)::int from public.bid_versions where bid_id = :'bid_a'), 1,
  'acknowledging never creates a bid version');

-- Who may acknowledge.
select tests.act_as(:'bidder_b');
select throws_ok(format('select public.acknowledge_addendum(%L, 2)', :'bid_a'), 'P0001', 'not_found',
  'another bidder: A''s bid reads as not_found (app.lock_bid never reveals another org''s bid)');
select tests.act_as(:'r1');
select throws_ok(format('select public.acknowledge_addendum(%L, 2)', :'bid_a'), 'P0001', 'not_authorized',
  'office staff are not_authorized');
select tests.act_as(:'author');
select throws_ok(format('select public.acknowledge_addendum(%L, 2)', :'bid_a'), 'P0001', 'not_authorized',
  'the agency is not_authorized');

-- Only published addenda.
select tests.act_as(:'bidder_a');
select throws_ok(format('select public.acknowledge_addendum(%L, 3)', :'bid_a'), 'P0001', 'not_found',
  'an unpublished (draft) addendum is not_found');
select throws_ok(format('select public.acknowledge_addendum(%L, 9)', :'bid_a'), 'P0001', 'not_found',
  'an addendum number that does not exist is not_found');
select throws_ok(format('select public.acknowledge_addendum(%L, 1)', gen_random_uuid()), 'P0001', 'not_found',
  'an unknown bid is not_found');

-- B acknowledges both before close (Review Focus 5: these count at review).
select tests.act_as(:'bidder_b');
select lives_ok(format('select public.acknowledge_addendum(%L, 1)', :'bid_b'), 'B acknowledges Addendum 1');
select lives_ok(format('select public.acknowledge_addendum(%L, 2)', :'bid_b'), 'B acknowledges Addendum 2');

-- ===========================================================================
-- my_bid_acknowledgments
-- ===========================================================================
select tests.act_as(:'bidder_a');
select results_eq(
  format('select addendum_number, published_at, acknowledged_at is not null from public.my_bid_acknowledgments(%L)',
         :'bid_a'),
  format('values (1, %L::timestamptz, true), (2, %L::timestamptz, false)', :'pub1', :'pub2'),
  'my_bid_acknowledgments: every published addendum, Addendum 2 not acknowledged');
select throws_ok(format('select * from public.my_bid_acknowledgments(%L)', :'bid_b'), 'P0001', 'not_found',
  'my_bid_acknowledgments: another bidder''s bid is not_found');
select tests.act_as(:'r1');
select throws_ok(format('select * from public.my_bid_acknowledgments(%L)', :'bid_a'), 'P0001', 'not_authorized',
  'my_bid_acknowledgments: an office user before close is not_authorized');
select tests.act_as(:'author');
select throws_ok(format('select * from public.my_bid_acknowledgments(%L)', :'bid_a'), 'P0001', 'not_authorized',
  'my_bid_acknowledgments: the agency is not_authorized');

-- The table itself is unreadable through the API.
select throws_ok('select * from public.bid_acknowledgments', '42501', null,
  'the agency cannot select bid_acknowledgments');
select tests.act_as(:'bidder_a');
select throws_ok('select * from public.bid_acknowledgments', '42501', null,
  'a bidder cannot select bid_acknowledgments directly either');
select throws_ok(format($q$insert into public.bid_acknowledgments (bid_id, addendum_number, acknowledged_by)
                          values (%L, 2, %L)$q$, :'bid_a', :'bidder_a'), '42501', null,
  'a bidder cannot insert an acknowledgment directly');
reset role;

-- Append-only.
select throws_ok(format('update public.bid_acknowledgments set acknowledged_at = now() where bid_id = %L', :'bid_a'),
  'P0001', 'bid_acknowledgments is append-only: UPDATE is not allowed', 'acknowledgments cannot be updated');
select throws_ok(format('delete from public.bid_acknowledgments where bid_id = %L', :'bid_a'),
  'P0001', 'bid_acknowledgments is append-only: DELETE is not allowed', 'acknowledgments cannot be deleted');
select throws_ok('truncate public.bid_acknowledgments',
  'P0001', 'bid_acknowledgments is append-only: TRUNCATE is not allowed', 'acknowledgments cannot be truncated');

-- app.missing_acknowledgments
select is(app.missing_acknowledgments(:'bid_a'), '{2}'::int[], 'missing_acknowledgments: A is missing Addendum 2');
select is(app.missing_acknowledgments(:'bid_b'), '{}'::int[], 'missing_acknowledgments: B is missing none');

-- review_bids is still sealed before close.
select tests.act_as(:'r1');
select throws_ok(format('select * from public.review_bids(%L)', :'s1'), 'P0001', 'sealed',
  'review_bids is sealed before close');
reset role;

-- ===========================================================================
-- Close s1. Signed originals for A and B, received before the due time.
-- ===========================================================================
select tests.set_bid_due(:'s1', now());
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
select :'s1', b.id, b.reference, 1, 'signed_form', now() - interval '1 hour', :'r1', now() - interval '1 hour'
  from public.bids b where b.id in (:'bid_a', :'bid_b');

-- Review Focus 5: acknowledging at close raises bids_closed (judged on clock_timestamp() after the lock).
select tests.act_as(:'bidder_a');
select throws_ok(format('select public.acknowledge_addendum(%L, 2)', :'bid_a'), 'P0001', 'bids_closed',
  'acknowledge_addendum at close raises bids_closed');
reset role;
select is(app.missing_acknowledgments(:'bid_a'), '{2}'::int[], 'A is still missing Addendum 2 after close');
select tests.act_as(:'r1');
select throws_ok(format('select * from public.my_bid_acknowledgments(%L)', :'bid_a'), 'P0001', 'not_authorized',
  'my_bid_acknowledgments stays bidder-only after close (office reads missing_addenda through review_bids)');

-- review_bids: missing_addenda.
select is((select r.missing_addenda from public.review_bids(:'s1') r where r.bid_id = :'bid_a'), '{2}'::int[],
  'review_bids shows {2} for the bid missing Addendum 2');
select is((select r.missing_addenda from public.review_bids(:'s1') r where r.bid_id = :'bid_b'), '{}'::int[],
  'review_bids shows {} for the bid that acknowledged everything before close');
select tests.act_as(:'bidder_a');
select throws_ok(format('select * from public.review_bids(%L)', :'s1'), 'P0001', 'not_authorized',
  'review_bids: a bidder is not_authorized');

-- Review Focus 5: set_bid_outcome.
select tests.act_as(:'r1');
select throws_ok(format('select public.set_bid_outcome(%L, %L, null, %L)', :'bid_a', 'accepted', 'All in order'),
  'P0001', 'ack_missing', 'a bid missing Addendum 2 cannot be accepted');
select public.set_bid_outcome(:'bid_a', 'accepted_flagged', null, 'Mailed form matches') as out_a1 \gset
select public.set_bid_outcome(:'bid_a', 'accepted_flagged', null,
  'Did not acknowledge Addendum 2. Called the bidder') as out_a2 \gset
select public.set_bid_outcome(:'bid_a', 'non_responsive', 'wrong_form', 'Wrong bid form') as out_a3 \gset
select lives_ok(format('select public.set_bid_outcome(%L, %L, null, %L)', :'bid_b', 'accepted', 'All in order'),
  'B (acknowledged everything before close) can be accepted');
reset role;
select is((select note from public.bid_outcomes where id = :'out_a1'),
  'Did not acknowledge Addendum 2. Mailed form matches',
  'flagging stores the fixed note, a space, then the reviewer''s note');
select is((select detail ->> 'note' from public.bid_audit_log
            where bid_id = :'bid_a' and action = 'set_bid_outcome' and detail ->> 'outcome_id' = :'out_a1'),
  'Did not acknowledge Addendum 2. Mailed form matches', 'the audit records the stored note');
select is((select note from public.bid_outcomes where id = :'out_a2'),
  'Did not acknowledge Addendum 2. Called the bidder', 'a note that already starts with the fixed note is kept as is');
select is((select row(outcome, ground, note)::text from public.bid_outcomes where id = :'out_a3'),
  '(non_responsive,wrong_form,"Wrong bid form")', 'non-responsive for a listed ground is unchanged');
select is((select row(outcome, note)::text from public.bid_outcomes where bid_id = :'bid_b'),
  '(accepted,"All in order")', 'B is accepted with its note untouched');

select * from finish();
rollback;
