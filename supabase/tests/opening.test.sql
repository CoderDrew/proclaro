-- Close, the derived non-responsive rule and the office's internal tabulation (slice 2a, Task 9).
begin;

select plan(92);

select set_config('storage.allow_delete_query', 'true', true);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000bf1', 'OP Office', 'office'),
  ('00000000-0000-0000-0000-000000000ba1', 'OP Agency', 'agency');
\set agency '00000000-0000-0000-0000-000000000ba1'
select tests.make_user('op.author@test.test', :'agency') as author \gset
select tests.make_user('op.admin@test.test', :'agency', true) as admin_u \gset
select tests.make_user('op.office@test.test', '00000000-0000-0000-0000-000000000bf1') as office_u \gset
select tests.make_user('op.offadmin@test.test', '00000000-0000-0000-0000-000000000bf1', true) as office_admin \gset
select tests.make_bidder('op.a@test.test', 'OP Bidder A') as bidder_a \gset
select tests.make_bidder('op.b@test.test', 'OP Bidder B') as bidder_b \gset
select tests.make_bidder('op.c@test.test', 'OP Bidder C') as bidder_c \gset
select tests.make_bidder('op.d@test.test', 'OP Bidder D') as bidder_d \gset
select tests.make_bidder('op.e@test.test', 'OP Bidder E') as bidder_e \gset

-- Two schedule items, one deductive alternate, estimate $150,000 (bid bond required), optional section references.
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 hour') as sol \gset

-- Test-only helpers (rolled back with the transaction).
create function tests.t9_error(p_sql text)
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
-- Fill the caller's draft (RLS applies): prices, bond choice, insurance + references (+ bid_bond when electronic).
create function tests.t9_fill(p_bid uuid, p_tag text, p_items bigint[], p_alts bigint[], p_choice public.bid_bond_choice)
returns void
language plpgsql
as $$
declare
  v_ins  text := 'bids/' || p_bid || '/' || gen_random_uuid() || '/ins-' || p_tag || '.pdf';
  v_ref  text := 'bids/' || p_bid || '/' || gen_random_uuid() || '/ref-' || p_tag || '.pdf';
  v_bond text := 'bids/' || p_bid || '/' || gen_random_uuid() || '/bond-' || p_tag || '.pdf';
begin
  update public.bid_drafts set item_cents = p_items, alternate_cents = p_alts, bid_bond_choice = p_choice
   where bid_id = p_bid;
  insert into storage.objects (bucket_id, name, metadata) values
    ('bid-files', v_ins, jsonb_build_object('eTag', '"' || p_tag || '-ins"', 'size', 2048, 'mimetype', 'application/pdf')),
    ('bid-files', v_ref, jsonb_build_object('eTag', '"' || p_tag || '-ref"', 'size', 4096, 'mimetype', 'application/pdf'));
  insert into public.bid_draft_files (bid_id, slot, path, file_name) values
    (p_bid, 'insurance', v_ins, 'ins-' || p_tag || '.pdf'),
    (p_bid, 'references', v_ref, 'ref-' || p_tag || '.pdf');
  if p_choice = 'electronic' then
    insert into storage.objects (bucket_id, name, metadata) values
      ('bid-files', v_bond, jsonb_build_object('eTag', '"' || p_tag || '-bond"', 'size', 1024, 'mimetype', 'application/pdf'));
    insert into public.bid_draft_files (bid_id, slot, path, file_name) values (p_bid, 'bid_bond', v_bond, 'bond-' || p_tag || '.pdf');
  end if;
end;
$$;
grant execute on function tests.t9_error(text), tests.t9_fill(uuid, text, bigint[], bigint[], public.bid_bond_choice)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Bids A-E through the Task 4 functions
-- ---------------------------------------------------------------------------
-- A: v1 and v2 submitted (Review Focus 3). Paper bond.
select tests.act_as(:'bidder_a');
select public.start_bid(:'sol') as bid_a \gset
select tests.t9_fill(:'bid_a', 'a1', '{1,1}', '{1}', 'paper');
select version from public.submit_bid(:'bid_a') \gset
select public.replace_bid(:'bid_a');
select tests.t9_fill(:'bid_a', 'a2', '{9000000,0}', '{50000}', 'paper');
select version from public.submit_bid(:'bid_a') \gset
-- B: v1 submitted, then replace started and never submitted (Review Focus 4). Paper bond.
select tests.act_as(:'bidder_b');
select public.start_bid(:'sol') as bid_b \gset
select tests.t9_fill(:'bid_b', 'b1', '{10000000,100}', '{200000}', 'paper');
select version from public.submit_bid(:'bid_b') \gset
select public.replace_bid(:'bid_b');
-- C: v1 and v2 submitted, each with its own original (Review Focus 4). Electronic bond on v2.
select tests.act_as(:'bidder_c');
select public.start_bid(:'sol') as bid_c \gset
select tests.t9_fill(:'bid_c', 'c1', '{2,2}', '{2}', 'paper');
select version from public.submit_bid(:'bid_c') \gset
select public.replace_bid(:'bid_c');
select tests.t9_fill(:'bid_c', 'c2', '{12500000,234567}', '{1500000}', 'electronic');
select version from public.submit_bid(:'bid_c') \gset
-- D: submitted, then withdrawn.
select tests.act_as(:'bidder_d');
select public.start_bid(:'sol') as bid_d \gset
select tests.t9_fill(:'bid_d', 'd1', '{1000,1000}', '{0}', 'paper');
select version from public.submit_bid(:'bid_d') \gset
select public.withdraw_bid(:'bid_d');
-- E: submitted; its original is logged and then voided before close.
select tests.act_as(:'bidder_e');
select public.start_bid(:'sol') as bid_e \gset
select tests.t9_fill(:'bid_e', 'e1', '{20000000,0}', '{0}', 'paper');
select version from public.submit_bid(:'bid_e') \gset
reset role;

select reference as ref_a from public.bids where id = :'bid_a' \gset
select reference as ref_b from public.bids where id = :'bid_b' \gset
select reference as ref_c from public.bids where id = :'bid_c' \gset
select reference as ref_d from public.bids where id = :'bid_d' \gset
select reference as ref_e from public.bids where id = :'bid_e' \gset

-- Originals through the Task 8 functions.
select tests.act_as(:'office_u');
select public.log_bid_original(:'sol', :'ref_a', 1, 'signed_form');                  -- A: v1 only
select public.log_bid_original(:'sol', :'ref_b', 1, 'signed_form');                  -- B: v1
select public.log_bid_original(:'sol', :'ref_b', 1, 'bid_bond');                     -- B: paper bond for v1
select public.log_bid_original(:'sol', :'ref_c', 1, 'signed_form');                  -- C: v1
-- C: v2
select public.log_bid_original(:'sol', :'ref_c', 2, 'signed_form') as c2_entry \gset
select public.log_bid_original(:'sol', :'ref_d', 1, 'signed_form');                  -- D: withdrawn anyway
select public.log_bid_original(:'sol', :'ref_e', 1, 'signed_form') as e_entry \gset
select public.void_bid_original(:'e_entry', 'Logged against the wrong envelope');
reset role;

-- log_bid_original stamps logged_at (and the default received_at) with clock_timestamp() after its lock (0011), so
-- in this single transaction every entry above is later than now(), which set_bid_due(now()) below uses as the
-- due time. These entries stand for originals logged in earlier, committed transactions: move them to the
-- transaction start. Test-only (append-only trigger disabled and re-enabled inside this rolled-back transaction).
alter table public.bid_original_log disable trigger bid_original_log_append_only;
update public.bid_original_log set logged_at = now(), received_at = case when received_at is null then null else now() end
 where solicitation_id = :'sol';
alter table public.bid_original_log enable trigger bid_original_log_append_only;

-- ---------------------------------------------------------------------------
-- Shape and grants
-- ---------------------------------------------------------------------------
select has_function('public', 'opened_bids', array['uuid'], 'public.opened_bids exists');
select has_function('public', 'opened_bid_files', array['uuid'], 'public.opened_bid_files exists');
select has_function('app', 'bond_original_received', array['uuid', 'integer', 'timestamp with time zone'],
  'app.bond_original_received exists');
select has_function('app', 'open_bids_gate', array['uuid'], 'app.open_bids_gate exists');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname in ('opened_bids', 'opened_bid_files')
      and p.prosecdef and p.proconfig @> array['search_path=""'] and p.provolatile = 'v'
      and has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')),
  2, 'opened_bids and opened_bid_files: definer, empty search_path, volatile, execute for authenticated only');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'app'::regnamespace and p.proname in ('bond_original_received', 'open_bids_gate')
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')),
  2, 'app helpers: definer, empty search_path, executable by no API role');
-- Concurrency (binding requirement 2): the gate takes FOR SHARE on the solicitation's bids rows, and both public
-- functions call the gate before any other read. A single pgTAP session cannot interleave two transactions, so
-- this pins the source; the behaviour is the documented Postgres row-lock semantics.
select ok(
  (select p.prosrc ~* 'from\s+public\.bids\s+b\s+where\s+b\.solicitation_id\s*=\s*p_solicitation_id\s+for\s+share'
     from pg_proc p where p.oid = 'app.open_bids_gate(uuid)'::regprocedure),
  'app.open_bids_gate locks the solicitation''s bids rows FOR SHARE');
select ok(
  (select bool_and(position('app.open_bids_gate' in p.prosrc) > 0
                   and position('app.open_bids_gate' in p.prosrc) < position('public.bid_versions' in p.prosrc))
     from pg_proc p where p.oid in ('public.opened_bids(uuid)'::regprocedure, 'public.opened_bid_files(uuid)'::regprocedure)),
  'both public functions pass the gate before reading bid_versions');

-- ---------------------------------------------------------------------------
-- Review Focus 2: before close, nobody opens bids
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), 'P0001', 'sealed',
  'before close: the office gets sealed from opened_bids');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), 'P0001', 'sealed',
  'before close: the office gets sealed from opened_bid_files');
select throws_ok(format('select * from public.opened_bids(%L)', '00000000-0000-0000-0000-00000000dead'), 'P0001',
  'not_found', 'an unknown solicitation is not_found');
select throws_ok(format('select * from public.opened_bid_files(%L)', '00000000-0000-0000-0000-00000000dead'), 'P0001',
  'not_found', 'an unknown solicitation is not_found (files)');
reset role;
select is((select count(*)::int from public.bid_audit_log where action = 'bid_close_determination'), 0,
  'a sealed call writes no determination row');

select tests.act_as(:'admin_u');
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), 'P0001', 'not_authorized',
  'before close: an admin in an agency org gets not_authorized');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), 'P0001', 'not_authorized',
  'before close: an admin in an agency org gets not_authorized (files)');
select tests.act_as(:'author');
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), 'P0001', 'not_authorized',
  'before close: the agency author gets not_authorized');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), 'P0001', 'not_authorized',
  'before close: the agency author gets not_authorized (files)');
select tests.act_as(:'bidder_a');
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), 'P0001', 'not_authorized',
  'before close: a bidder gets not_authorized');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), 'P0001', 'not_authorized',
  'before close: a bidder gets not_authorized (files)');
select tests.act_as_service_role();
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), '42501', null,
  'before close: service_role cannot execute opened_bids');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), '42501', null,
  'before close: service_role cannot execute opened_bid_files');
select tests.act_as_anon();
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), '42501', null,
  'before close: anon cannot execute opened_bids');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), '42501', null,
  'before close: anon cannot execute opened_bid_files');
reset role;

-- One second before the due time is still sealed.
select tests.set_bid_due(:'sol', now() + interval '1 second');
select tests.act_as(:'office_u');
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), 'P0001', 'sealed',
  'one second before the due time: still sealed');
reset role;

-- ---------------------------------------------------------------------------
-- Close: bid_due_at = now() exactly
-- ---------------------------------------------------------------------------
select tests.set_bid_due(:'sol', now());

select tests.act_as(:'office_u');
select lives_ok(format('select * from public.opened_bids(%L)', :'sol'), 'at exactly the due time the office opens bids');
reset role;
select is((select count(*)::int from public.bid_audit_log where action = 'bid_close_determination'), 4,
  'the first read writes exactly 4 determination rows (A, B, C, E; not withdrawn D)');
select is((select count(distinct bid_id)::int from public.bid_audit_log where action = 'bid_close_determination'), 4,
  'one determination row per opened bid');
select is((select actor_id from public.bid_audit_log where action = 'bid_close_determination' and bid_id = :'bid_a'),
  :'office_u'::uuid, 'the determination row names the office user');
select is((select detail from public.bid_audit_log where action = 'bid_close_determination' and bid_id = :'bid_a'),
  jsonb_build_object('version', 2, 'original_received', false, 'reason', 'signed original not received by the bid due time'),
  'A''s determination detail: version 2, not received, the verbatim reason');
select is((select detail from public.bid_audit_log where action = 'bid_close_determination' and bid_id = :'bid_b'),
  jsonb_build_object('version', 1, 'original_received', true, 'reason', null),
  'B''s determination detail: version 1, received, no reason');
select is((select solicitation_id from public.bid_audit_log where action = 'bid_close_determination' and bid_id = :'bid_c'),
  :'sol'::uuid, 'the determination row carries the solicitation');

select tests.act_as(:'office_u');
select lives_ok(format('select * from public.opened_bids(%L)', :'sol'), 'a second read');
reset role;
select is((select count(*)::int from public.bid_audit_log where action = 'bid_close_determination'), 4,
  'a second read with no change writes 0 determination rows');

select tests.act_as(:'office_u');
-- Rows, order and withdrawn exclusion
select results_eq(format('select bid_id from public.opened_bids(%L)', :'sol'),
  format('values (%L::uuid), (%L::uuid), (%L::uuid), (%L::uuid)', :'bid_a', :'bid_b', :'bid_c', :'bid_e'),
  'one row per non-withdrawn bid, ordered by base total then reference');
select is((select count(*)::int from public.opened_bids(:'sol') where bid_id = :'bid_d'), 0, 'withdrawn bid D is absent');

-- Review Focus 3
select results_eq(
  format('select version, original_received, non_responsive_reason from public.opened_bids(%L) where bid_id = %L', :'sol', :'bid_a'),
  $$values (2, false, 'signed original not received by the bid due time'::text)$$,
  'Review Focus 3: A opens at v2; v1''s original does not count; verbatim reason');
-- Review Focus 4
select results_eq(
  format('select version, original_received, non_responsive_reason from public.opened_bids(%L) where bid_id = %L', :'sol', :'bid_b'),
  $$values (1, true, null::text)$$,
  'Review Focus 4: B''s unsubmitted replace leaves v1 current, and v1''s original counts');
select results_eq(
  format('select version, original_received, non_responsive_reason from public.opened_bids(%L) where bid_id = %L', :'sol', :'bid_c'),
  $$values (2, true, null::text)$$,
  'Review Focus 4: C opens at v2 and v2''s own original counts');
select results_eq(
  format('select version, original_received, non_responsive_reason from public.opened_bids(%L) where bid_id = %L', :'sol', :'bid_e'),
  $$values (1, false, 'signed original not received by the bid due time'::text)$$,
  'E''s voided original does not count: non-responsive');

-- Prices and totals
select results_eq(
  format('select item_cents, base_total_cents, alternate_cents from public.opened_bids(%L) where bid_id = %L', :'sol', :'bid_c'),
  $$values ('{12500000,234567}'::bigint[], 12734567::bigint, '{1500000}'::bigint[])$$,
  'C: stored item cents, base total = sum of items, alternates separate');
select results_eq(
  format('select reference, bidder_org_id, bidder_name, submitted_at from public.opened_bids(%L) where bid_id = %L', :'sol', :'bid_b'),
  format('select %L::text, p.org_id, %L::text, now() from public.profiles p where p.user_id = %L', :'ref_b', 'OP Bidder B', :'bidder_b'),
  'B: reference, bidder org and name, submitted_at');

-- As-submitted legal name (final review C1): submit_bid records it on the version; an office admin cannot rename
-- the bidder's org; and even a rename made directly in the database leaves the tabulation on the recorded name.
reset role;
select p.org_id as org_b from public.profiles p where p.user_id = :'bidder_b' \gset
select is((select bidder_legal_name from public.bid_versions where bid_id = :'bid_b' and version = 1), 'OP Bidder B',
  'submit_bid records the bidder''s legal name on the version');
select tests.act_as(:'office_admin');
select results_eq(
  format('with u as (update public.organizations set name = %L where id = %L returning 1) select count(*)::int from u',
         'OP Bidder B Renamed', :'org_b'),
  'values (0)', 'an office admin''s rename of a bidder org updates no row');
reset role;
select is((select name from public.organizations where id = :'org_b'), 'OP Bidder B',
  'the bidder org name is unchanged after the refused rename');
update public.organizations set name = 'OP Bidder B Renamed' where id = :'org_b';  -- database owner, test only
select tests.act_as(:'office_u');
select is((select bidder_name from public.opened_bids(:'sol') where bid_id = :'bid_b'), 'OP Bidder B',
  'after a rename attempt the tabulation still shows the as-submitted name');
reset role;
select ok(not exists (select 1 from pg_proc p where p.oid = 'public.opened_bids(uuid)'::regprocedure
                       and p.prosrc ~ 'public\.organizations'),
  'opened_bids never reads the live organization name');
select is((select count(*)::int from public.bid_audit_log where action = 'bid_close_determination'), 4,
  'the extra reads wrote no determination row');
select tests.act_as(:'office_u');
select is((select base_total_cents from public.opened_bids(:'sol') where bid_id = :'bid_a'), 9000000::bigint,
  'A: base total is from its latest version');

-- Bid bond (binding requirement 5): judged by the choice; paper shows whether the paper original was logged.
select results_eq(
  format('select bid_id, bid_bond_choice::text, bond_original_received from public.opened_bids(%L)', :'sol'),
  format($$values (%L::uuid, 'paper'::text, false), (%L::uuid, 'paper', true), (%L::uuid, 'electronic', null::boolean), (%L::uuid, 'paper', false)$$,
         :'bid_a', :'bid_b', :'bid_c', :'bid_e'),
  'bond: paper shows the paper original status; electronic has none');

-- opened_bid_files
select results_eq(
  format('select slot::text, file_name, file_status from public.opened_bid_files(%L) where bid_id = %L order by slot', :'sol', :'bid_b'),
  $$values ('insurance'::text, 'ins-b1.pdf'::text, 'ok'::text), ('references', 'ref-b1.pdf', 'ok')$$,
  'opened_bid_files returns B''s v1 files, unaltered');
select is((select count(*)::int from public.opened_bid_files(:'sol') where bid_id = :'bid_d'), 0, 'no files for withdrawn D');
select is((select count(*)::int from public.opened_bid_files(:'sol') where file_name like '%-a1.pdf'), 0, 'no files for A''s v1');
select is((select count(*)::int from public.opened_bid_files(:'sol') where bid_id = :'bid_a'), 2, 'A''s v2 files are listed');
select is((select count(*)::int from public.opened_bid_files(:'sol') where bid_id = :'bid_c'), 3,
  'C''s v2 files include the electronic bond');
select is((select count(*)::int from public.opened_bid_files(:'sol') where file_status <> 'ok'), 0, 'all files are clean');
-- The office can read an opened file and the audit log through its own policies.
select is((select count(*)::int from storage.objects o
            where o.bucket_id = 'bid-files' and o.name in (select path from public.opened_bid_files(:'sol'))), 9,
  'the office reads every opened file''s storage object');
select ok((select count(*) from public.bid_audit_log where solicitation_id = :'sol') > 0, 'the office reads the audit log after close');
reset role;

-- Ruling 5: tamper evidence. A's v2 insurance changes size and eTag; its references object is deleted.
update storage.objects set metadata = metadata || '{"size": 9999, "eTag": "\"swapped\""}'::jsonb
 where bucket_id = 'bid-files' and name = (select path from public.bid_version_files vf join public.bid_versions v on v.id = vf.version_id
                                            where v.bid_id = :'bid_a' and v.version = 2 and vf.slot = 'insurance');
delete from storage.objects
 where bucket_id = 'bid-files' and name = (select path from public.bid_version_files vf join public.bid_versions v on v.id = vf.version_id
                                            where v.bid_id = :'bid_a' and v.version = 2 and vf.slot = 'references');
-- B's insurance: only the eTag changes (same size).
update storage.objects set metadata = metadata || '{"eTag": "\"other\""}'::jsonb
 where bucket_id = 'bid-files' and name = (select path from public.bid_version_files vf join public.bid_versions v on v.id = vf.version_id
                                            where v.bid_id = :'bid_b' and v.version = 1 and vf.slot = 'insurance');
-- C's references: the object is replaced by a new object (new id) with the same name, size and eTag.
select o.metadata as c_ref_meta, o.name as c_ref_name from storage.objects o
 where o.bucket_id = 'bid-files' and o.name = (select path from public.bid_version_files vf join public.bid_versions v on v.id = vf.version_id
                                                where v.bid_id = :'bid_c' and v.version = 2 and vf.slot = 'references') \gset
delete from storage.objects where bucket_id = 'bid-files' and name = :'c_ref_name';
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'c_ref_name', :'c_ref_meta'::jsonb);

select tests.act_as(:'office_u');
select results_eq(
  format('select slot::text, file_status from public.opened_bid_files(%L) where bid_id = %L order by slot', :'sol', :'bid_a'),
  $$values ('insurance'::text, 'changed'::text), ('references', 'missing')$$,
  'Ruling 5: a changed size/eTag is "changed"; a deleted object is "missing"');
select results_eq(
  format('select slot::text, file_status from public.opened_bid_files(%L) where bid_id = %L order by slot', :'sol', :'bid_b'),
  $$values ('insurance'::text, 'changed'::text), ('references', 'ok')$$,
  'Ruling 5: an eTag-only change is "changed"');
select results_eq(
  format('select slot::text, file_status from public.opened_bid_files(%L) where bid_id = %L and slot = %L', :'sol', :'bid_c', 'references'),
  $$values ('references'::text, 'changed'::text)$$,
  'Ruling 5: a replaced object (new object id) is "changed"');
select is((select count(*)::int from public.opened_bid_files(:'sol') where bid_id = :'bid_e' and file_status = 'ok'), 2,
  'untouched files stay "ok"');
-- Tamper flags do not alter the determination.
select is((select count(*)::int from public.opened_bids(:'sol')), 4, 'tampering does not change the rows');
reset role;
select is((select count(*)::int from public.bid_audit_log where action = 'bid_close_determination'), 4,
  'tampering writes no determination row');

-- ---------------------------------------------------------------------------
-- After close: voiding C's v2 original changes C's determination
-- ---------------------------------------------------------------------------
select tests.act_as(:'office_u');
select public.void_bid_original(:'c2_entry', 'Not actually signed');
select results_eq(
  format('select original_received, non_responsive_reason from public.opened_bids(%L) where bid_id = %L', :'sol', :'bid_c'),
  $$values (false, 'signed original not received by the bid due time'::text)$$,
  'after voiding C''s v2 original, C is non-responsive');
reset role;
select is((select count(*)::int from public.bid_audit_log where action = 'bid_close_determination'), 5,
  'exactly one new determination row');
select is((select count(*)::int from public.bid_audit_log where action = 'bid_close_determination' and bid_id = :'bid_c'), 2,
  'the new row is C''s');
select is((select detail from public.bid_audit_log where action = 'bid_close_determination' and bid_id = :'bid_c'
            order by id desc limit 1),
  jsonb_build_object('version', 2, 'original_received', false, 'reason', 'signed original not received by the bid due time'),
  'C''s new determination detail');

-- (An original logged after close is pinned in 0011's tests: log_bid_original stamps logged_at with
-- clock_timestamp() after its lock, so an entry whose transaction began before the due time does not count.)
select tests.act_as(:'office_u');
select lives_ok(format('select * from public.opened_bids(%L)', :'sol'), 'a further read');
reset role;
select is((select count(*)::int from public.bid_audit_log where action = 'bid_close_determination'), 5,
  'a further read with no change writes no determination row');

-- ---------------------------------------------------------------------------
-- After close: everyone but the office still sees nothing
-- ---------------------------------------------------------------------------
select tests.act_as(:'admin_u');
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), 'P0001', 'not_authorized',
  'after close: an admin in an agency org gets not_authorized');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), 'P0001', 'not_authorized',
  'after close: an admin in an agency org gets not_authorized (files)');
select tests.act_as(:'author');
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), 'P0001', 'not_authorized',
  'after close: the agency author gets not_authorized');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), 'P0001', 'not_authorized',
  'after close: the agency author gets not_authorized (files)');
select is((select count(*)::int from public.bid_audit_log), 0, 'after close: the agency author reads 0 bid_audit_log rows');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files'), 0,
  'after close: the agency author reads no bid files');
select tests.act_as(:'bidder_b');
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), 'P0001', 'not_authorized',
  'after close: a bidder gets not_authorized');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), 'P0001', 'not_authorized',
  'after close: a bidder gets not_authorized (files)');
select is((select count(*)::int from public.bid_audit_log), 0, 'after close: a bidder reads 0 bid_audit_log rows');
select tests.act_as_service_role();
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), '42501', null,
  'after close: service_role cannot execute opened_bids');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), '42501', null,
  'after close: service_role cannot execute opened_bid_files');
select throws_ok('select count(*) from public.bid_audit_log', '42501', null,
  'after close: service_role cannot read bid_audit_log');
select tests.act_as_anon();
select throws_ok(format('select * from public.opened_bids(%L)', :'sol'), '42501', null,
  'after close: anon cannot execute opened_bids');
select throws_ok(format('select * from public.opened_bid_files(%L)', :'sol'), '42501', null,
  'after close: anon cannot execute opened_bid_files');
reset role;

-- ---------------------------------------------------------------------------
-- app.bond_original_received and app.open_bids_gate, directly
-- ---------------------------------------------------------------------------
select is(app.bond_original_received(:'bid_b', 1, now()), true, 'bond helper: B v1 paper bond received by due');
select is(app.bond_original_received(:'bid_b', 1, now() - interval '1 second'), false,
  'bond helper: not received when the due time is before the receipt');
select is(app.bond_original_received(:'bid_b', 2, now()), false, 'bond helper: another version never counts');
select is(app.bond_original_received(:'bid_a', 2, now()), false, 'bond helper: no bond logged');
select is(app.original_received(:'bid_b', 1, now()), true, 'signed-form helper is separate from the bond helper');

-- A second solicitation: a bid with only a draft (never submitted) opens to nothing.
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 hour') as sol2 \gset
select tests.act_as(:'bidder_a');
select public.start_bid(:'sol2') as bid_a2 \gset
reset role;
select tests.set_bid_due(:'sol2', now());
select tests.act_as(:'office_u');
select is((select count(*)::int from public.opened_bids(:'sol2')), 0, 'a draft-only bid is not opened');
select is((select count(*)::int from public.opened_bid_files(:'sol2')), 0, 'and has no opened files');
reset role;
select is((select count(*)::int from public.bid_audit_log where action = 'bid_close_determination' and solicitation_id = :'sol2'), 0,
  'and gets no determination row');

-- An unpublished solicitation is sealed, never opened.
insert into public.solicitations (agency_id, created_by, data)
values (:'agency', :'author', tests.solicitation_data()) returning id as sol_draft \gset
select tests.act_as(:'office_u');
select throws_ok(format('select * from public.opened_bids(%L)', :'sol_draft'), 'P0001', 'sealed',
  'an unpublished solicitation is sealed');
reset role;

select * from finish();
rollback;
