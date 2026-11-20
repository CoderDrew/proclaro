-- 0016: the bid-bond cure (slice 2b, Task 3). Deadline (Review Focus 1, frozen at close by Ruling 3), derived
-- status, the bond-only cure upload and its storage rules, and the bidder's own status read.
begin;

select plan(76);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000cf1', 'CU Office', 'office'),
  ('00000000-0000-0000-0000-000000000ca1', 'CU Agency', 'agency');
\set agency '00000000-0000-0000-0000-000000000ca1'
select tests.make_user('cu.author@test.test', :'agency') as author \gset
select tests.make_user('cu.office@test.test', '00000000-0000-0000-0000-000000000cf1') as office_u \gset
select tests.make_bidder('cu.a@test.test', 'CU Bidder A') as bidder_a \gset
select tests.make_bidder('cu.b@test.test', 'CU Bidder B') as bidder_b \gset
select tests.make_bidder('cu.c@test.test', 'CU Bidder C') as bidder_c \gset
select tests.make_bidder('cu.d@test.test', 'CU Bidder D') as bidder_d \gset
select tests.make_bidder('cu.e@test.test', 'CU Bidder E') as bidder_e \gset
select tests.make_bidder('cu.f@test.test', 'CU Bidder F') as bidder_f \gset

-- The error a statement raises, as 'sqlstate|message|detail', or 'ok'.
create function tests.cu_error(p_sql text)
returns text
language plpgsql
as $$
declare
  v_state text; v_msg text; v_detail text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text, v_detail = pg_exception_detail;
  return v_state || '|' || v_msg || '|' || coalesce(v_detail, '');
end;
$$;
grant execute on function tests.cu_error(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_function('app', 'cure_due_at', array['timestamp with time zone'], 'app.cure_due_at exists');
select has_function('app', 'bond_cure', array['uuid', 'timestamp with time zone'], 'app.bond_cure exists');
select has_function('app', 'cure_deadline', array['uuid'], 'app.cure_deadline exists');
select has_function('app', 'freeze_cure_due', array['uuid'], 'app.freeze_cure_due exists');
select has_function('public', 'submit_cure_bond', array['uuid', 'text', 'text'], 'public.submit_cure_bond exists');
select has_function('public', 'my_bid_cure', array['uuid'], 'public.my_bid_cure exists');
select has_table('public', 'bid_cure_files', 'bid_cure_files exists');
select has_table('public', 'cure_deadlines', 'cure_deadlines exists');
select ok(not has_function_privilege('authenticated', 'app.bond_cure(uuid, timestamptz)', 'execute'),
  'authenticated cannot execute app.bond_cure');
select ok(has_function_privilege('authenticated', 'public.submit_cure_bond(uuid, text, text)', 'execute')
      and not has_function_privilege('anon', 'public.submit_cure_bond(uuid, text, text)', 'execute')
      and not has_function_privilege('service_role', 'public.my_bid_cure(uuid)', 'execute'),
  'submit_cure_bond and my_bid_cure: authenticated only');
select ok(not has_table_privilege('authenticated', 'public.bid_cure_files', 'select')
      and not has_table_privilege('service_role', 'public.bid_cure_files', 'select')
      and not has_table_privilege('anon', 'public.bid_cure_files', 'select')
      and not has_table_privilege('service_role', 'public.cure_deadlines', 'select'),
  'bid_cure_files and cure_deadlines: no API privileges');

-- ---------------------------------------------------------------------------
-- Review Focus 1: app.cure_due_at, 17:00 local on the next business day (America/Denver). Literal timestamptz.
-- ---------------------------------------------------------------------------
select is(app.cure_due_at('2026-12-02 13:00 America/Denver'), '2026-12-03 17:00 America/Denver'::timestamptz,
  'Wednesday close -> Thursday 17:00');
select is(app.cure_due_at('2026-12-04 13:00 America/Denver'), '2026-12-07 17:00 America/Denver'::timestamptz,
  'Friday close -> Monday 17:00');
select is(app.cure_due_at('2026-12-04 23:30 America/Denver'), '2026-12-07 17:00 America/Denver'::timestamptz,
  'Friday 23:30 close -> Monday 17:00 (local date, not UTC date)');
insert into public.holidays (day, name) values ('2026-12-25', 'CU Christmas') on conflict (day) do nothing;
select is(app.cure_due_at('2026-12-24 13:00 America/Denver'), '2026-12-28 17:00 America/Denver'::timestamptz,
  'Thursday before a Friday holiday -> Monday 17:00 (skips the holiday, Saturday, Sunday)');
insert into public.holidays (day, name) values ('2027-01-18', 'CU Monday holiday') on conflict (day) do nothing;
select is(app.cure_due_at('2027-01-15 13:00 America/Denver'), '2027-01-19 17:00 America/Denver'::timestamptz,
  'Friday before a Monday holiday -> Tuesday 17:00 (weekend, then the holiday)');
-- DST: 2026-11-01 (fall back) and 2026-03-08 (spring forward). Both sides pinned as UTC literals too.
select is(app.cure_due_at('2026-10-30 13:00 America/Denver'), '2026-11-03 00:00:00+00'::timestamptz,
  'DST end week: Friday MDT close -> Monday 17:00 MST (00:00 UTC)');
select is(app.cure_due_at('2026-03-06 13:00 America/Denver'), '2026-03-09 23:00:00+00'::timestamptz,
  'DST start week: Friday MST close -> Monday 17:00 MDT (23:00 UTC)');
select is(app.cure_due_at(null), null::timestamptz, 'null due -> null');

-- ---------------------------------------------------------------------------
-- Fixtures: closed solicitations (due an hour ago).
-- ---------------------------------------------------------------------------
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour') as sol \gset
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour',
  '{"estimateCents": 14999999}'::jsonb) as sol_small \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 hour') as sol_open \gset
select tests.make_published_solicitation(:'agency', :'author', now() - interval '10 days') as sol_old \gset
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour') as sol_unread \gset

select tests.make_closed_bid(:'sol_small', :'bidder_a', '{1,1}', '{1}') as bid_small \gset
select tests.make_closed_bid(:'sol', :'bidder_a', '{1,1}', '{1}', 'paper', null, true, true) as bid_ok \gset
select tests.make_closed_bid(:'sol', :'bidder_b', '{1,1}', '{1}', 'paper') as bid_paper \gset
select tests.make_closed_bid(:'sol', :'bidder_c', '{1,1}', '{1}', 'electronic') as bid_elec_ok \gset
-- Electronic with no bond file: inserted bare (the helper always seals a file for electronic).
select tests.make_closed_bid(:'sol', :'bidder_d', '{1,1}', '{1}', 'paper') as bid_elec \gset
-- Bidder D's version becomes electronic with no file: the version row is append-only, so seal a new v2.
insert into public.bid_versions (bid_id, version, submitted_at, submitted_by, item_cents, alternate_cents,
                                 bid_bond_choice, bidder_legal_name)
select :'bid_elec', 2, s.bid_due_at - interval '90 minutes', :'bidder_d', '{1,1}', '{1}', 'electronic', 'CU Bidder D'
  from public.solicitations s where s.id = :'sol';
select tests.make_closed_bid(:'sol', :'bidder_e', '{1,1}', '{1}', 'paper') as bid_wd \gset
insert into public.bid_withdrawals (bid_id, version, withdrawn_by) values (:'bid_wd', 1, :'bidder_e');
select tests.make_closed_bid(:'sol_old', :'bidder_a', '{1,1}', '{1}', 'paper') as bid_old \gset
select tests.make_closed_bid(:'sol_open', :'bidder_a', '{1,1}', '{1}', 'paper') as bid_open \gset
select tests.make_closed_bid(:'sol_unread', :'bidder_f', '{1,1}', '{1}', 'paper') as bid_unread \gset

select bid_due_at as sol_due from public.solicitations where id = :'sol' \gset
select app.cure_due_at(:'sol_due') as cure_due \gset

-- ---------------------------------------------------------------------------
-- app.bond_cure
-- ---------------------------------------------------------------------------
select is((select row(status, due_at)::text from app.bond_cure(:'bid_small')), row('not_required', null::timestamptz)::text,
  'estimate 14,999,999: not_required');
select is((select row(status, due_at)::text from app.bond_cure(:'bid_ok')), row('ok', null::timestamptz)::text,
  'paper with a counted bond original: ok');
select is((select row(status, due_at)::text from app.bond_cure(:'bid_elec_ok')), row('ok', null::timestamptz)::text,
  'electronic with a sealed bond file: ok');
select is((select row(status, due_at)::text from app.bond_cure(:'bid_paper')), row('pending', :'cure_due'::timestamptz)::text,
  'paper without a bond original: pending, due = app.cure_due_at(bid_due_at)');
select is((select status from app.bond_cure(:'bid_elec')), 'pending',
  'electronic with no bond file in the sealed (latest) version: pending');
select is((select status from app.bond_cure(:'bid_paper', :'cure_due'::timestamptz - interval '1 second')), 'pending',
  'one second before the deadline: pending');
select is((select status from app.bond_cure(:'bid_paper', :'cure_due'::timestamptz)), 'failed',
  'at the deadline instant: failed');
select is((select status from app.bond_cure(:'bid_wd')), 'not_required', 'withdrawn bid is ignored');

-- A paper bond logged exactly at the deadline counts (the 2a <= rule); voided, it does not.
select reference as ref_paper from public.bids where id = :'bid_paper' \gset
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
values (:'sol', :'bid_paper', :'ref_paper', 1, 'bid_bond', :'cure_due', :'office_u', :'cure_due')
returning id as bond_entry \gset
select is((select status from app.bond_cure(:'bid_paper', :'cure_due'::timestamptz + interval '1 day')), 'cured',
  'bond original received and logged at the deadline: cured');
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, voids_entry_id, reason, logged_by)
values (:'sol', :'bid_paper', :'ref_paper', 1, 'bid_bond', :'bond_entry', 'Wrong envelope', :'office_u');
select is((select status from app.bond_cure(:'bid_paper', :'cure_due'::timestamptz + interval '1 day')), 'failed',
  'the same entry voided: failed');
-- One logged a second after the deadline never counts.
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
values (:'sol', :'bid_paper', :'ref_paper', 1, 'bid_bond', :'cure_due', :'office_u', :'cure_due'::timestamptz + interval '1 second');
select is((select status from app.bond_cure(:'bid_paper', :'cure_due'::timestamptz + interval '1 day')), 'failed',
  'bond original logged one second after the deadline: still failed');

-- ---------------------------------------------------------------------------
-- Ruling 3: the deadline is frozen at close. Holiday edits after close do not move it.
-- ---------------------------------------------------------------------------
-- (a) Frozen by the first cure read/write after close (freeze_cure_due), then a holiday lands on the deadline day.
select app.freeze_cure_due(:'sol') as frozen \gset
select is(:'frozen'::timestamptz, :'cure_due'::timestamptz, 'freeze_cure_due stores the computed deadline');
select is((select count(*)::int from public.cure_deadlines where solicitation_id = :'sol_unread'), 0,
  'a closed solicitation nobody has read is not frozen yet');
insert into public.holidays (day, name)
values (((:'cure_due'::timestamptz) at time zone 'America/Denver')::date, 'CU late holiday');
select isnt(app.cure_due_at(:'sol_due'), :'cure_due'::timestamptz, 'the live computation would now move');
select is(app.cure_deadline(:'sol'), :'cure_due'::timestamptz, 'the frozen deadline does not move');
select is((select due_at from app.bond_cure(:'bid_elec')), :'cure_due'::timestamptz, 'bond_cure reads the frozen deadline');
select is((select count(*)::int from public.cure_deadlines where solicitation_id = :'sol'), 1, 'one frozen row');
-- (b) The unread closed solicitation (same due time): the holiday insert froze it first, from the table before it.
select is(app.cure_deadline(:'sol_unread'), :'cure_due'::timestamptz,
  'an unread closed solicitation keeps the deadline computed before the holiday edit');
select throws_ok(format('delete from public.cure_deadlines where solicitation_id = %L', :'sol_unread'), 'P0001', null,
  'cure_deadlines is append-only');
-- (c) Before close nothing is frozen: a holiday added now moves the open solicitation's deadline.
select is((select count(*)::int from public.cure_deadlines where solicitation_id = :'sol_open'), 0,
  'an open solicitation is never frozen');
select is(app.cure_deadline(:'sol_open'), app.cure_due_at((select bid_due_at from public.solicitations where id = :'sol_open')),
  'before close the deadline follows the holiday table');
-- (d) A settings time-zone change after close does not move it either.
update public.settings set timezone = 'America/New_York' where id = 1;
select is(app.cure_deadline(:'sol'), :'cure_due'::timestamptz, 'a time-zone change after close does not move it');
update public.settings set timezone = 'America/Denver' where id = 1;
delete from public.holidays where name = 'CU late holiday';

-- ---------------------------------------------------------------------------
-- Storage: the bond-only cure upload
-- ---------------------------------------------------------------------------
select gen_random_uuid() as up1 \gset
select tests.act_as(:'bidder_d');
select lives_ok(format($q$insert into storage.objects (bucket_id, name, metadata) values ('bid-files', 'bids/%s/%s/bond.pdf',
  '{"eTag":"\"cure\"","size":2048}')$q$, :'bid_elec', :'up1'), 'the pending owner can upload after close');
select tests.act_as(:'bidder_a');
select throws_ok(format($q$insert into storage.objects (bucket_id, name, metadata) values ('bid-files', 'bids/%s/%s/bond.pdf',
  '{"eTag":"\"x\"","size":1}')$q$, :'bid_ok', gen_random_uuid()), '42501', null, 'the owner of an ok bid cannot');
select tests.act_as(:'bidder_c');
select throws_ok(format($q$insert into storage.objects (bucket_id, name, metadata) values ('bid-files', 'bids/%s/%s/bond.pdf',
  '{"eTag":"\"x\"","size":1}')$q$, :'bid_elec', gen_random_uuid()), '42501', null, 'another bidder cannot upload to the bid');
reset role;

-- ---------------------------------------------------------------------------
-- submit_cure_bond
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_c');
select is(tests.cu_error(format('select public.submit_cure_bond(%L, %L, %L)', :'bid_elec', 'bids/' || :'bid_elec' || '/' || :'up1' || '/bond.pdf', 'bond.pdf')),
  'P0001|not_found|', 'another bidder: not_found');
select tests.act_as(:'bidder_a');
select is(tests.cu_error(format('select public.submit_cure_bond(%L, %L, %L)', :'bid_ok', 'bids/' || :'bid_ok' || '/' || gen_random_uuid() || '/b.pdf', 'b.pdf')),
  'P0001|invalid_state|', 'status ok: invalid_state');
select is(tests.cu_error(format('select public.submit_cure_bond(%L, %L, %L)', :'bid_open', 'bids/' || :'bid_open' || '/' || gen_random_uuid() || '/b.pdf', 'b.pdf')),
  'P0001|invalid_state|', 'before close: invalid_state');
select is(tests.cu_error(format('select public.submit_cure_bond(%L, %L, %L)', :'bid_old', 'bids/' || :'bid_old' || '/' || gen_random_uuid() || '/b.pdf', 'b.pdf')),
  'P0001|cure_closed|', 'cure due long past: cure_closed');
select tests.act_as(:'bidder_d');
select is(tests.cu_error(format('select public.submit_cure_bond(%L, %L, %L)', :'bid_elec', 'bids/' || :'bid_paper' || '/' || :'up1' || '/bond.pdf', 'bond.pdf')),
  'P0001|invalid_data|', 'a path under another bid: invalid_data');
select is(tests.cu_error(format('select public.submit_cure_bond(%L, %L, %L)', :'bid_elec', 'bids/' || :'bid_elec' || '/' || gen_random_uuid() || '/none.pdf', 'none.pdf')),
  'P0001|invalid_bid|file_missing', 'a path with no object: invalid_bid / file_missing');
select is(tests.cu_error(format('select public.submit_cure_bond(%L, %L, %L)', :'bid_elec', 'bids/' || :'bid_elec' || '/' || :'up1' || '/bond.pdf', '  ')),
  'P0001|invalid_data|', 'a blank file name: invalid_data');
reset role;
-- An object that predates close (a leftover draft upload) is not new data: refused.
select gen_random_uuid() as up_old \gset
insert into storage.objects (bucket_id, name, metadata, created_at) values ('bid-files',
  'bids/' || :'bid_elec' || '/' || :'up_old' || '/old.pdf', '{"eTag":"\"old\"","size":10}', :'sol_due'::timestamptz - interval '1 minute');
select tests.act_as(:'bidder_d');
select is(tests.cu_error(format('select public.submit_cure_bond(%L, %L, %L)', :'bid_elec', 'bids/' || :'bid_elec' || '/' || :'up_old' || '/old.pdf', 'old.pdf')),
  'P0001|invalid_data|', 'an object uploaded before close: invalid_data');
select isnt(public.submit_cure_bond(:'bid_elec', 'bids/' || :'bid_elec' || '/' || :'up1' || '/bond.pdf', 'bond.pdf'), null,
  'the owner with an uploaded object: returns the upload time');
select is((select status from public.my_bid_cure(:'bid_elec')), 'cured', 'status is now cured');
select is(tests.cu_error(format('select public.submit_cure_bond(%L, %L, %L)', :'bid_elec', 'bids/' || :'bid_elec' || '/' || :'up1' || '/bond.pdf', 'bond.pdf')),
  'P0001|invalid_state|', 'a second call: invalid_state');
select throws_ok(format($q$insert into storage.objects (bucket_id, name, metadata) values ('bid-files', 'bids/%s/%s/x.pdf',
  '{"eTag":"\"x\"","size":1}')$q$, :'bid_elec', gen_random_uuid()), '42501', null, 'once cured, no more uploads');
select is((select count(*)::int from storage.objects where name = 'bids/' || :'bid_elec' || '/' || :'up1' || '/bond.pdf'), 1,
  'the owning bidder can read its own cure file');
reset role;
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_elec' and action = 'submit_cure_bond'), 1,
  'one submit_cure_bond audit row');
select is((select detail from public.bid_audit_log where bid_id = :'bid_elec' and action = 'submit_cure_bond'),
  jsonb_build_object('version', 2, 'path', 'bids/' || :'bid_elec' || '/' || :'up1' || '/bond.pdf'), 'audit detail {version, path}');
select is((select version from public.bid_cure_files where bid_id = :'bid_elec'), 2, 'the cure file is recorded against the latest version');

select tests.act_as(:'office_u');
select is((select count(*)::int from storage.objects where name = 'bids/' || :'bid_elec' || '/' || :'up1' || '/bond.pdf'), 1,
  'the office reads the cure file after close');
select tests.act_as(:'author');
select is((select count(*)::int from storage.objects where name = 'bids/' || :'bid_elec' || '/' || :'up1' || '/bond.pdf'), 0,
  'an agency author reads nothing');
select tests.act_as(:'bidder_c');
select is((select count(*)::int from storage.objects where name = 'bids/' || :'bid_elec' || '/' || :'up1' || '/bond.pdf'), 0,
  'another bidder reads nothing');
reset role;

-- ---------------------------------------------------------------------------
-- my_bid_cure and the derived disqualification audit
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_b');
select is(tests.cu_error(format('select * from public.my_bid_cure(%L)', :'bid_elec')), 'P0001|not_found|', 'another bidder: not_found');
select is((select row(status, due_at)::text from public.my_bid_cure(:'bid_paper')), row('pending', :'cure_due'::timestamptz)::text,
  'own pending bid: pending with the due time');
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_paper' and action = 'bid_cure_determination'), 0,
  'no determination is audited before the deadline');
reset role;
select app.cure_due_at((select bid_due_at from public.solicitations where id = :'sol_old')) as old_cure \gset
select tests.act_as(:'bidder_a');
select is((select row(status, due_at)::text from public.my_bid_cure(:'bid_open')), row('not_required', null::timestamptz)::text,
  'before close: not_required with no due time (nothing leaks)');
select is((select row(status, due_at)::text from public.my_bid_cure(:'bid_old')),
  row('failed', :'old_cure'::timestamptz)::text,
  'past the deadline: failed');
select * from public.my_bid_cure(:'bid_old');
reset role;
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_old' and action = 'bid_cure_determination'), 1,
  'the failure is audited once on first read after the deadline (two reads, one row)');
select is((select detail->>'reason' from public.bid_audit_log where bid_id = :'bid_old' and action = 'bid_cure_determination'),
  'bid bond not received by the cure deadline', 'the audit carries the verbatim reason');
select tests.act_as(:'office_u');
select is(tests.cu_error('select * from public.my_bid_cure(''' || :'bid_old' || ''')'), 'P0001|not_authorized|',
  'an office caller: not_authorized');
reset role;

-- ---------------------------------------------------------------------------
-- Append-only
-- ---------------------------------------------------------------------------
select throws_ok(format('update public.bid_cure_files set file_name = %L where bid_id = %L', 'x', :'bid_elec'),
  'P0001', null, 'update on bid_cure_files raises (owner)');
select throws_ok(format('delete from public.bid_cure_files where bid_id = %L', :'bid_elec'),
  'P0001', null, 'delete on bid_cure_files raises (owner)');
select tests.act_as(:'bidder_d');
select throws_ok(format('delete from public.bid_cure_files where bid_id = %L', :'bid_elec'), '42501', null,
  'delete on bid_cure_files: authenticated has no privilege');
select tests.act_as_service_role();
select throws_ok(format('update public.bid_cure_files set file_name = %L where bid_id = %L', 'x', :'bid_elec'), '42501', null,
  'update on bid_cure_files: service_role has no privilege');
select tests.act_as_anon();
select throws_ok(format('delete from public.bid_cure_files where bid_id = %L', :'bid_elec'), '42501', null,
  'delete on bid_cure_files: anon has no privilege');
reset role;

select * from finish();
rollback;
