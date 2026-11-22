-- Office log of mailed originals, with voids (slice 2a, Task 8).
begin;

select plan(108);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000cf1', 'OL Office', 'office'),
  ('00000000-0000-0000-0000-000000000ca1', 'OL Agency', 'agency');
select tests.make_user('ol.author@test.test', '00000000-0000-0000-0000-000000000ca1') as author \gset
select tests.make_user('ol.admin@test.test', '00000000-0000-0000-0000-000000000ca1', true) as admin_u \gset
select tests.make_user('ol.office@test.test', '00000000-0000-0000-0000-000000000cf1') as office_u \gset
select tests.make_bidder('ol.bidder@test.test', 'OL Bidder') as bidder \gset
select p.org_id as bidder_org from public.profiles p where p.user_id = :'bidder' \gset

\set agency '00000000-0000-0000-0000-000000000ca1'
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol2 \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol3 \gset

-- Bids and submitted versions inserted directly (the lifecycle functions are covered by bids.test.sql).
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by)
values (:'sol', :'bidder_org', 'K7QM-2XVD', :'bidder') returning id as bid \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by)
values (:'sol2', :'bidder_org', 'M3PX-8RTA', :'bidder') returning id as bid2 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by)
values (:'sol3', :'bidder_org', 'W9HC-4NKE', :'bidder') returning id as bid3 \gset
insert into public.bid_versions (bid_id, version, submitted_by, item_cents, alternate_cents, bidder_legal_name)
select b, v, :'bidder', '{100,200}', '{50}', 'OL Bidder'
  from (values (:'bid'::uuid, 1), (:'bid', 2), (:'bid2', 1)) x(b, v);
insert into public.bid_versions (bid_id, version, submitted_by, item_cents, alternate_cents, bidder_legal_name)
select :'bid3', v, :'bidder', '{100,200}', '{50}', 'OL Bidder' from generate_series(1, 9) v;

-- ---------------------------------------------------------------------------
-- Shape, grants and policy
-- ---------------------------------------------------------------------------
select has_type('public', 'original_item', 'type original_item exists');
select enum_has_labels('public', 'original_item', array['signed_form', 'bid_bond'], 'original_item labels');
select has_table('public', 'bid_original_log', 'table bid_original_log exists');
select columns_are('public', 'bid_original_log',
  array['id', 'solicitation_id', 'bid_id', 'reference', 'version', 'item', 'received_at', 'voids_entry_id',
        'reason', 'logged_by', 'logged_at'],
  'bid_original_log columns');
select col_is_unique('public', 'bid_original_log', 'voids_entry_id', 'an entry can be voided once');
select has_function('public', 'log_bid_original',
  array['uuid', 'text', 'integer', 'original_item', 'timestamp with time zone'], 'public.log_bid_original exists');
select has_function('public', 'void_bid_original', array['uuid', 'text'], 'public.void_bid_original exists');
select has_function('app', 'original_received', array['uuid', 'integer', 'timestamp with time zone'],
  'app.original_received exists');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname in ('log_bid_original', 'void_bid_original')
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')),
  2, 'both log functions are security definer, empty search_path, execute for authenticated only');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'app'::regnamespace and p.proname = 'original_received'
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')),
  1, 'app.original_received is security definer, empty search_path, executable by no API role');
select ok(has_any_column_privilege('authenticated', 'public.bid_original_log', 'select'),
  'authenticated may select (RLS decides the rows)');
select ok(not has_table_privilege('authenticated', 'public.bid_original_log', 'insert')
          and not has_table_privilege('authenticated', 'public.bid_original_log', 'update')
          and not has_table_privilege('authenticated', 'public.bid_original_log', 'delete')
          and not has_table_privilege('authenticated', 'public.bid_original_log', 'truncate'),
  'authenticated has no insert, update, delete or truncate');
select ok(not has_column_privilege('authenticated', 'public.bid_original_log', 'bid_id', 'select'),
  'authenticated cannot select bid_id (only what office_bid_index already shows)');
select ok(not has_table_privilege('anon', 'public.bid_original_log', 'select, insert, update, delete, truncate')
          and not has_any_column_privilege('anon', 'public.bid_original_log', 'select, insert, update'),
  'anon has no privilege');
select ok(not has_table_privilege('service_role', 'public.bid_original_log', 'select, insert, update, delete, truncate')
          and not has_any_column_privilege('service_role', 'public.bid_original_log', 'select, insert, update'),
  'service_role has no privilege');
select is((select relrowsecurity from pg_class where oid = 'public.bid_original_log'::regclass), true, 'RLS is enabled');
select policies_are('public', 'bid_original_log', array['bid_original_log_read_office'], 'one policy: office reads');

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select public.log_bid_original(:'sol', ' k7qm 2xvd ', 1, 'signed_form') as e1 \gset
select isnt(:'e1'::uuid, null::uuid, 'the office logs a signed form and gets an entry id');
reset role;
select results_eq(
  format('select reference, version, item::text, received_at = logged_at, logged_at > now(), logged_by, bid_id, '
         || 'solicitation_id, voids_entry_id, reason from public.bid_original_log where id = %L', :'e1'),
  format('values (%L::text, 1, %L::text, true, true, %L::uuid, %L::uuid, %L::uuid, null::uuid, null::text)',
         'K7QM-2XVD', 'signed_form', :'office_u', :'bid', :'sol'),
  'stored: normalized reference, version, item, logged_at is the clock after the lock (later than the transaction '
  || 'start), received_at defaults to that same instant, logged_by set');
select is((select count(*)::int from public.bid_audit_log where action = 'log_bid_original' and bid_id = :'bid'), 1,
  'one log_bid_original audit row');
select is(
  (select detail from public.bid_audit_log where action = 'log_bid_original' and bid_id = :'bid'),
  jsonb_build_object('entry_id', :'e1'::uuid, 'reference', 'K7QM-2XVD', 'version', 1, 'item', 'signed_form',
                     'received_at', (select received_at from public.bid_original_log where id = :'e1')),
  'log audit detail: entry_id, reference, version, item, received_at');
select is((select actor_id from public.bid_audit_log where action = 'log_bid_original' and bid_id = :'bid'),
  :'office_u'::uuid, 'the audit actor is the office user');

select tests.act_as(:'office_u');
-- A back-dated receipt and a paper bid bond.
select public.log_bid_original(:'sol', 'K7QM-2XVD', 2, 'bid_bond', now() - interval '2 hours') as e_bond \gset
select is((select received_at from public.bid_original_log where id = :'e_bond'), now() - interval '2 hours',
  'an explicit past received_at is stored');
select is((select item::text from public.bid_original_log where id = :'e_bond'), 'bid_bond', 'a paper bid bond is logged');
select lives_ok(format('select public.log_bid_original(%L, %L, 2, %L, now())', :'sol', 'K7QM-2XVD', 'signed_form'),
  'received_at exactly now() is accepted');
-- Review Focus 3/4: the older version's original is accepted into the log.
select public.log_bid_original(:'sol', 'K7QM-2XVD', 1, 'signed_form') as e_v1 \gset
select is((select version from public.bid_original_log where id = :'e_v1'), 1,
  'a signed form for the superseded version 1 is logged against version 1');

-- Uniform unknown_bid
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol', 'ZZZZ-ZZZZ', 'signed_form'),
  'P0001', 'unknown_bid', 'an unknown reference is unknown_bid');
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol', 'not a ref', 'signed_form'),
  'P0001', 'unknown_bid', 'a malformed reference is unknown_bid');
select throws_ok(format('select public.log_bid_original(%L, %L, 3, %L)', :'sol', 'K7QM-2XVD', 'signed_form'),
  'P0001', 'unknown_bid', 'version 3 when only 2 exist is unknown_bid');
select throws_ok(format('select public.log_bid_original(%L, %L, 0, %L)', :'sol', 'K7QM-2XVD', 'signed_form'),
  'P0001', 'unknown_bid', 'version 0 is unknown_bid');
select throws_ok(format('select public.log_bid_original(%L, %L, null, %L)', :'sol', 'K7QM-2XVD', 'signed_form'),
  'P0001', 'unknown_bid', 'a null version is unknown_bid');
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol', 'M3PX-8RTA', 'signed_form'),
  'P0001', 'unknown_bid', 'another solicitation''s reference is unknown_bid');
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', '00000000-0000-0000-0000-00000000dead',
  'K7QM-2XVD', 'signed_form'), 'P0001', 'unknown_bid', 'an unknown solicitation is unknown_bid');
select throws_ok(format('select public.log_bid_original(%L, %L, 1, null)', :'sol', 'K7QM-2XVD'),
  'P0001', 'invalid_data', 'a null item is invalid_data');
select throws_ok(
  format('select public.log_bid_original(%L, %L, 1, %L, now() + interval %L)', :'sol', 'K7QM-2XVD', 'signed_form', '1 second'),
  'P0001', 'received_in_future', 'received_at one second in the future is received_in_future');
select throws_ok(
  format('select public.log_bid_original(%L, %L, 9, %L, now() + interval %L)', :'sol', 'ZZZZ-ZZZZ', 'signed_form', '1 day'),
  'P0001', 'received_in_future', 'a future time is refused before any bid lookup');
-- Before close, the office cannot read the audit rows its own logging wrote.
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid'), 0,
  'before close the office reads no bid audit rows');
reset role;

-- Roles refused
select tests.act_as(:'bidder');
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol', 'K7QM-2XVD', 'signed_form'),
  'P0001', 'not_authorized', 'a bidder logging gets not_authorized');
select throws_ok(format('select public.void_bid_original(%L, %L)', :'e1', 'mistake'),
  'P0001', 'not_authorized', 'a bidder voiding gets not_authorized');
select tests.act_as(:'author');
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol', 'K7QM-2XVD', 'signed_form'),
  'P0001', 'not_authorized', 'the agency author logging gets not_authorized');
select throws_ok(format('select public.void_bid_original(%L, %L)', :'e1', 'mistake'),
  'P0001', 'not_authorized', 'the agency author voiding gets not_authorized');
select tests.act_as(:'admin_u');
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol', 'K7QM-2XVD', 'signed_form'),
  'P0001', 'not_authorized', 'an admin outside the office logging gets not_authorized');
select throws_ok(format('select public.void_bid_original(%L, %L)', :'e1', 'mistake'),
  'P0001', 'not_authorized', 'an admin outside the office voiding gets not_authorized');
-- An unknown reference does not change the answer for a non-office caller.
select tests.act_as(:'bidder');
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol', 'ZZZZ-ZZZZ', 'signed_form'),
  'P0001', 'not_authorized', 'a bidder gets not_authorized before any lookup');
select tests.act_as_anon();
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol', 'K7QM-2XVD', 'signed_form'),
  '42501', null, 'anon cannot execute log_bid_original');
select throws_ok(format('select public.void_bid_original(%L, %L)', :'e1', 'mistake'),
  '42501', null, 'anon cannot execute void_bid_original');
select tests.act_as_service_role();
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol', 'K7QM-2XVD', 'signed_form'),
  '42501', null, 'service_role cannot execute log_bid_original');
select throws_ok(format('select public.void_bid_original(%L, %L)', :'e1', 'mistake'),
  '42501', null, 'service_role cannot execute void_bid_original');
reset role;

-- ---------------------------------------------------------------------------
-- Voids
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select throws_ok(format('select public.void_bid_original(%L, %L)', :'e1', ''),
  'P0001', 'reason_required', 'an empty reason is reason_required');
select throws_ok(format('select public.void_bid_original(%L, %L)', :'e1', '   '),
  'P0001', 'reason_required', 'a blank reason is reason_required');
select throws_ok(format('select public.void_bid_original(%L, null)', :'e1'),
  'P0001', 'reason_required', 'a null reason is reason_required');
select throws_ok(format('select public.void_bid_original(%L, %L)', '00000000-0000-0000-0000-00000000dead', 'mistake'),
  'P0001', 'not_found', 'voiding an unknown entry is not_found');
select throws_ok(format('select public.void_bid_original(null, %L)', 'mistake'),
  'P0001', 'not_found', 'voiding a null entry is not_found');
select public.void_bid_original(:'e1', '  Logged against the wrong version  ') as v1 \gset
select isnt(:'v1'::uuid, null::uuid, 'a valid void returns its entry id');
reset role;
select results_eq(
  format('select voids_entry_id, reason, received_at, bid_id, reference, version, item::text, solicitation_id, '
         || 'logged_by, logged_at = now() from public.bid_original_log where id = %L', :'v1'),
  format('values (%L::uuid, %L::text, null::timestamptz, %L::uuid, %L::text, 1, %L::text, %L::uuid, %L::uuid, true)',
         :'e1', 'Logged against the wrong version', :'bid', 'K7QM-2XVD', 'signed_form', :'sol', :'office_u'),
  'the void row references the entry, keeps the trimmed reason and copies bid, reference, version and item');
select is(
  (select detail from public.bid_audit_log where action = 'void_bid_original' and bid_id = :'bid'),
  jsonb_build_object('entry_id', :'v1'::uuid, 'voids_entry_id', :'e1'::uuid, 'reason', 'Logged against the wrong version'),
  'void audit detail: entry_id, voids_entry_id, reason');
select is((select count(*)::int from public.bid_original_log where id = :'e1'), 1, 'the voided entry is still there');
select tests.act_as(:'office_u');
select throws_ok(format('select public.void_bid_original(%L, %L)', :'e1', 'again'),
  'P0001', 'already_voided', 'voiding it again is already_voided');
select throws_ok(format('select public.void_bid_original(%L, %L)', :'v1', 'undo'),
  'P0001', 'invalid_state', 'voiding a void is invalid_state');
reset role;

-- ---------------------------------------------------------------------------
-- Visibility and append-only
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select is((select count(*)::int from public.bid_original_log where solicitation_id = :'sol'), 5,
  'the office sees every entry: 4 receipts and 1 void');
select throws_ok('select bid_id from public.bid_original_log', '42501', null, 'the office cannot select bid_id');
select throws_ok(format('insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, '
  || 'received_at, logged_by) values (%L, %L, %L, 1, %L, now(), %L)', :'sol', :'bid', 'K7QM-2XVD', 'signed_form', :'office_u'),
  '42501', null, 'the office cannot insert directly');
select throws_ok(format('update public.bid_original_log set reason = %L where id = %L', 'x', :'v1'),
  '42501', null, 'the office cannot update');
select throws_ok(format('delete from public.bid_original_log where id = %L', :'e1'),
  '42501', null, 'the office cannot delete');
select tests.act_as(:'bidder');
select is((select count(*)::int from public.bid_original_log), 0, 'a bidder sees no log rows');
select throws_ok(format('update public.bid_original_log set reason = %L where id = %L', 'x', :'v1'),
  '42501', null, 'a bidder cannot update');
select throws_ok(format('delete from public.bid_original_log where id = %L', :'e1'),
  '42501', null, 'a bidder cannot delete');
select tests.act_as(:'author');
select is((select count(*)::int from public.bid_original_log), 0, 'the agency author sees no log rows');
select throws_ok(format('delete from public.bid_original_log where id = %L', :'e1'),
  '42501', null, 'the agency author cannot delete');
select tests.act_as(:'admin_u');
select is((select count(*)::int from public.bid_original_log), 0, 'an admin outside the office sees no log rows');
select tests.act_as_anon();
select throws_ok('select count(*) from public.bid_original_log', '42501', null, 'anon cannot select');
select throws_ok(format('delete from public.bid_original_log where id = %L', :'e1'), '42501', null, 'anon cannot delete');
select tests.act_as_service_role();
select throws_ok('select count(*) from public.bid_original_log', '42501', null, 'service_role cannot select');
select throws_ok(format('update public.bid_original_log set reason = %L where id = %L', 'x', :'v1'),
  '42501', null, 'service_role cannot update');
select throws_ok(format('delete from public.bid_original_log where id = %L', :'e1'),
  '42501', null, 'service_role cannot delete');
reset role;
-- Even the table owner is stopped by the triggers.
select throws_ok(format('update public.bid_original_log set reason = %L where id = %L', 'x', :'v1'),
  'P0001', null, 'update is rejected by trigger for the owner');
select throws_ok(format('delete from public.bid_original_log where id = %L', :'e1'),
  'P0001', null, 'delete is rejected by trigger for the owner');
select throws_ok('truncate public.bid_original_log cascade', 'P0001', null, 'truncate is rejected by trigger for the owner');

-- Row checks (owner inserts)
select throws_ok(format('insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, '
  || 'received_at, reason, logged_by) values (%L, %L, %L, 1, %L, now(), %L, %L)',
  :'sol', :'bid', 'K7QM-2XVD', 'signed_form', 'why', :'office_u'),
  '23514', null, 'a receipt cannot carry a reason');
select throws_ok(format('insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, '
  || 'voids_entry_id, reason, logged_by) values (%L, %L, %L, 1, %L, %L, %L, %L)',
  :'sol', :'bid', 'K7QM-2XVD', 'signed_form', :'e_bond', ' ', :'office_u'),
  '23514', null, 'a void needs a non-blank reason');
select throws_ok(format('insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, '
  || 'received_at, logged_by, logged_at) values (%L, %L, %L, 1, %L, now(), %L, now() - interval %L)',
  :'sol', :'bid', 'K7QM-2XVD', 'signed_form', :'office_u', '1 second'),
  '23514', null, 'received_at cannot be after logged_at');
select throws_ok(format('insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, '
  || 'received_at, logged_by) values (%L, %L, %L, 3, %L, now(), %L)',
  :'sol', :'bid', 'K7QM-2XVD', 'signed_form', :'office_u'),
  '23503', null, 'an entry must name a submitted version');

-- ---------------------------------------------------------------------------
-- After close: logging and voiding still work (recorded, not counted by Task 9)
-- ---------------------------------------------------------------------------
select tests.set_bid_due(:'sol', now() - interval '1 second');
select tests.act_as(:'office_u');
select public.log_bid_original(:'sol', 'K7QM-2XVD', 2, 'signed_form') as e_late \gset
select isnt(:'e_late'::uuid, null::uuid, 'logging after close succeeds');
select lives_ok(format('select public.void_bid_original(%L, %L)', :'e_bond', 'Bond belongs to another bid'),
  'voiding after close succeeds');
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid' and action = 'log_bid_original'), 5,
  'after close the office reads the five log audit rows');
reset role;

-- ---------------------------------------------------------------------------
-- app.original_received (Task 9 computes the outcome from it). Direct inserts with explicit timestamps.
-- ---------------------------------------------------------------------------
\set due '''2026-08-31 19:00:00+00'''
insert into public.bid_original_log (id, solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
values
  ('00000000-0000-0000-0000-0000000c0001', :'sol3', :'bid3', 'W9HC-4NKE', 1, 'signed_form', :due, :'office_u', :due),
  ('00000000-0000-0000-0000-0000000c0002', :'sol3', :'bid3', 'W9HC-4NKE', 2, 'signed_form',
   :due::timestamptz + interval '1 second', :'office_u', :due::timestamptz + interval '1 second'),
  ('00000000-0000-0000-0000-0000000c0003', :'sol3', :'bid3', 'W9HC-4NKE', 3, 'signed_form',
   :due::timestamptz - interval '1 hour', :'office_u', :due::timestamptz + interval '1 minute'),
  ('00000000-0000-0000-0000-0000000c0004', :'sol3', :'bid3', 'W9HC-4NKE', 4, 'signed_form',
   :due::timestamptz - interval '1 hour', :'office_u', :due::timestamptz - interval '1 hour'),
  ('00000000-0000-0000-0000-0000000c0005', :'sol3', :'bid3', 'W9HC-4NKE', 5, 'signed_form',
   :due::timestamptz - interval '1 hour', :'office_u', :due::timestamptz - interval '1 hour'),
  ('00000000-0000-0000-0000-0000000c0006', :'sol3', :'bid3', 'W9HC-4NKE', 6, 'bid_bond',
   :due::timestamptz - interval '1 hour', :'office_u', :due::timestamptz - interval '1 hour'),
  ('00000000-0000-0000-0000-0000000c0008', :'sol3', :'bid3', 'W9HC-4NKE', 8, 'signed_form',
   :due::timestamptz - interval '2 hours', :'office_u', :due::timestamptz - interval '2 hours'),
  ('00000000-0000-0000-0000-0000000c0009', :'sol3', :'bid3', 'W9HC-4NKE', 8, 'signed_form',
   :due::timestamptz - interval '1 hour', :'office_u', :due::timestamptz - interval '1 hour');
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, voids_entry_id, reason, logged_by, logged_at)
values
  (:'sol3', :'bid3', 'W9HC-4NKE', 4, 'signed_form', '00000000-0000-0000-0000-0000000c0004', 'Wrong bid',
   :'office_u', :due::timestamptz - interval '30 minutes'),
  (:'sol3', :'bid3', 'W9HC-4NKE', 5, 'signed_form', '00000000-0000-0000-0000-0000000c0005', 'Wrong bid',
   :'office_u', :due::timestamptz + interval '1 day'),
  (:'sol3', :'bid3', 'W9HC-4NKE', 8, 'signed_form', '00000000-0000-0000-0000-0000000c0008', 'Duplicate',
   :'office_u', :due::timestamptz - interval '90 minutes');

select is(app.original_received(:'bid3', 1, :due), true, 'received and logged exactly at the due time counts');
select is(app.original_received(:'bid3', 2, :due), false, 'received one second after the due time does not count');
select is(app.original_received(:'bid3', 3, :due), false,
  'received before the due time but logged after it (backdated after close) does not count');
select is(app.original_received(:'bid3', 4, :due), false, 'a receipt voided before the due time does not count');
select is(app.original_received(:'bid3', 5, :due), false, 'a receipt voided after the due time does not count');
select is(app.original_received(:'bid3', 6, :due), false, 'a paper bid bond alone does not count');
select is(app.original_received(:'bid3', 7, :due), false, 'no entry at all does not count');
select is(app.original_received(:'bid3', 8, :due), true, 'one voided receipt and one valid receipt: the valid one counts');
-- Review Focus 3/4: an original logged for v1 counts for v1 only, never for v2.
select is(app.original_received(:'bid3', 9, :due), false, 'nothing logged for version 9');
select is(app.original_received(:'bid3', 1, :due::timestamptz - interval '1 second'), false,
  'the same receipt does not count against an earlier due time');

-- Through the functions: v1 and v2 of the first bid, signed form for v1 only, all before due.
select tests.set_bid_due(:'sol2', now() + interval '1 day');
insert into public.bid_versions (bid_id, version, submitted_by, item_cents, alternate_cents, bidder_legal_name)
values (:'bid2', 2, :'bidder', '{100,200}', '{50}', 'OL Bidder');
select tests.act_as(:'office_u');
select lives_ok(format('select public.log_bid_original(%L, %L, 1, %L)', :'sol2', 'm3px 8rta', 'signed_form'),
  'a signed form is logged for v1 of a bid whose latest version is 2');
reset role;
select is(app.original_received(:'bid2', 1, now() + interval '1 day'), true, 'it counts for version 1');
select is(app.original_received(:'bid2', 2, now() + interval '1 day'), false, 'it does not count for version 2');

-- ---------------------------------------------------------------------------
-- Straddling log (final review I1): the bid row lock and the clock_timestamp() stamp.
-- ---------------------------------------------------------------------------
select ok(
  (select p.prosrc ~ 'for no key update of b;.*v_logged\s*:= clock_timestamp\(\);.*logged_at\)'
     from pg_proc p where p.oid = 'public.log_bid_original(uuid, text, int, public.original_item, timestamptz)'::regprocedure),
  'log_bid_original locks the bid row (FOR NO KEY UPDATE since 0025), then stamps logged_at with clock_timestamp() and writes it');
select ok(
  (select p.prosrc ~ 'p_received_at > clock_timestamp\(\)'
     from pg_proc p where p.oid = 'public.log_bid_original(uuid, text, int, public.original_item, timestamptz)'::regprocedure),
  'the received-in-future check uses the same clock');

select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol_clk \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by)
values (:'sol_clk', :'bidder_org', 'C1KQ-7PTR', :'bidder') returning id as bid_clk \gset
insert into public.bid_versions (bid_id, version, submitted_by, item_cents, alternate_cents, bidder_legal_name)
select :'bid_clk', v, :'bidder', '{100,200}', '{50}', 'OL Bidder' from generate_series(1, 3) v;

-- Positive control: logged well before the due time, it counts.
select tests.act_as(:'office_u');
select public.log_bid_original(:'sol_clk', 'C1KQ-7PTR', 1, 'signed_form') as clk_e1 \gset
reset role;
select ok((select logged_at <= bid_due_at from public.bid_original_log, public.solicitations s
            where bid_original_log.id = :'clk_e1' and s.id = :'sol_clk'), 'clock control: logged before the due time');
select is(app.original_received(:'bid_clk', 1, (select bid_due_at from public.solicitations where id = :'sol_clk')), true,
  'clock control: an original logged before the due time counts');

-- The due time passes inside this transaction: now() (transaction start) is before it, clock_timestamp() after.
select tests.set_bid_due(:'sol_clk', clock_timestamp() + interval '50 milliseconds');
select pg_sleep(0.1);
select ok(now() < (select bid_due_at from public.solicitations where id = :'sol_clk')
          and clock_timestamp() >= (select bid_due_at from public.solicitations where id = :'sol_clk'),
  'clock fixture: now() is before the due time, clock_timestamp() is past it');

select tests.act_as(:'office_u');
select public.log_bid_original(:'sol_clk', 'C1KQ-7PTR', 2, 'signed_form') as clk_e2 \gset
select public.log_bid_original(:'sol_clk', 'C1KQ-7PTR', 3, 'signed_form',
  (select bid_due_at - interval '1 second' from public.solicitations where id = :'sol_clk')) as clk_e3 \gset
reset role;
select ok((select logged_at > s.bid_due_at and received_at = logged_at
             from public.bid_original_log e, public.solicitations s where e.id = :'clk_e2' and s.id = :'sol_clk'),
  'a log whose transaction started before the due time is stamped after it (received_at defaults to that stamp)');
select is(app.original_received(:'bid_clk', 2, (select bid_due_at from public.solicitations where id = :'sol_clk')), false,
  'a log whose transaction started before the due time but whose clock_timestamp() is past it does not count');
select ok((select received_at < s.bid_due_at and logged_at > s.bid_due_at and received_at <= logged_at
             from public.bid_original_log e, public.solicitations s where e.id = :'clk_e3' and s.id = :'sol_clk'),
  'an explicit on-time received_at is kept, but logged_at is past the due time');
select is(app.original_received(:'bid_clk', 3, (select bid_due_at from public.solicitations where id = :'sol_clk')), false,
  'received on time but logged after the due time (same transaction) does not count');
select tests.act_as(:'office_u');
select throws_ok(format('select public.log_bid_original(%L, %L, 1, %L, %L)', :'sol_clk', 'C1KQ-7PTR', 'signed_form',
  clock_timestamp() + interval '1 minute'), 'P0001', 'received_in_future',
  'received_at after the database clock is received_in_future');
reset role;

select * from finish();
rollback;
