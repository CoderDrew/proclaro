-- Sealed bid tables, their privileges, and the sealed `bid-files` bucket (slice 2a, Task 3).
-- Bids and submitted versions are inserted directly as the test superuser; the lifecycle functions come in Task 4.
begin;

select plan(185);

select set_config('storage.allow_delete_query', 'true', true);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000009f1', 'BS Office', 'office'),
  ('00000000-0000-0000-0000-0000000009a1', 'BS Agency', 'agency');

select tests.make_user('bs.author@test.test', '00000000-0000-0000-0000-0000000009a1') as author \gset
select tests.make_user('bs.office@test.test', '00000000-0000-0000-0000-0000000009f1') as office_u \gset
select tests.make_user('bs.admin@test.test', '00000000-0000-0000-0000-0000000009f1', true) as admin_u \gset
select tests.make_bidder('bs.bidder.a@test.test', 'BS Bidder A') as bidder_a \gset
select tests.make_bidder('bs.bidder.b@test.test', 'BS Bidder B') as bidder_b \gset
select p.org_id as org_a from public.profiles p where p.user_id = :'bidder_a' \gset
select p.org_id as org_b from public.profiles p where p.user_id = :'bidder_b' \gset

select tests.make_published_solicitation('00000000-0000-0000-0000-0000000009a1', :'author',
                                         now() + interval '1 day') as sol \gset

-- Fixed ids and object paths: bids/{bid_id}/{upload_uuid}/{file}
\set bid_a '00000000-0000-0000-0000-0000000009b1'
\set bid_b '00000000-0000-0000-0000-0000000009b2'
\set v1 '00000000-0000-0000-0000-0000000009e1'
\set v2 '00000000-0000-0000-0000-0000000009e2'
\set path_a 'bids/00000000-0000-0000-0000-0000000009b1/11111111-1111-4111-8111-111111111111/q.pdf'
\set path_old 'bids/00000000-0000-0000-0000-0000000009b1/22222222-2222-4222-8222-222222222222/old.pdf'
\set path_b 'bids/00000000-0000-0000-0000-0000000009b2/33333333-3333-4333-8333-333333333333/b.pdf'
\set path_ins 'bids/00000000-0000-0000-0000-0000000009b1/44444444-4444-4444-8444-444444444444/ins.pdf'
\set path_new 'bids/00000000-0000-0000-0000-0000000009b1/55555555-5555-4555-8555-555555555555/new.pdf'

insert into public.bids (id, solicitation_id, bidder_org_id, reference, created_by) values
  (:'bid_a', :'sol', :'org_a', 'K7QM-2XVD', :'bidder_a'),
  (:'bid_b', :'sol', :'org_b', 'K7QM-2XVE', :'bidder_b');
-- A has submitted v1 and is drafting v2; B is drafting v1.
insert into public.bid_drafts (bid_id, version, updated_at)
values (:'bid_a', 2, now() - interval '1 hour'), (:'bid_b', 1, now() - interval '1 hour');
insert into public.bid_versions (id, bid_id, version, submitted_by, item_cents, alternate_cents, bid_bond_choice,
                                 bidder_legal_name)
values (:'v1', :'bid_a', 1, :'bidder_a', '{100,200}', '{50}', 'paper', 'Bidder A');
insert into public.bid_version_files (version_id, slot, path, file_name)
values (:'v1', 'qualifications', :'path_old', 'old.pdf');
insert into public.bid_draft_files (bid_id, slot, path, file_name) values
  (:'bid_a', 'qualifications', :'path_a', 'q.pdf'),
  (:'bid_b', 'qualifications', :'path_b', 'b.pdf');
insert into storage.objects (bucket_id, name) values
  ('bid-files', :'path_a'), ('bid-files', :'path_old'), ('bid-files', :'path_b');
insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
values (:'sol', :'bid_a', :'bidder_a', 'submit_bid', '{"reference":"K7QM-2XVD","version":1}');

-- ---------------------------------------------------------------------------
-- Grants: exactly what the brief says.
-- ---------------------------------------------------------------------------
select table_privs_are('public', t, 'anon', array[]::text[], 'anon has no privileges on ' || t)
  from unnest(array['bids','bid_drafts','bid_draft_files','bid_versions','bid_version_files',
                    'bid_withdrawals','bid_audit_log']) t;
select table_privs_are('public', t, 'service_role', array[]::text[], 'service_role has no privileges on ' || t)
  from unnest(array['bids','bid_drafts','bid_draft_files','bid_versions','bid_version_files',
                    'bid_withdrawals','bid_audit_log']) t;
select table_privs_are('public', 'bids', 'authenticated', array['SELECT'], 'authenticated: select on bids');
select table_privs_are('public', 'bid_drafts', 'authenticated', array['SELECT'], 'authenticated: select on bid_drafts');
select table_privs_are('public', 'bid_draft_files', 'authenticated', array['DELETE', 'SELECT'],
  'authenticated: select, delete on bid_draft_files');
select table_privs_are('public', 'bid_audit_log', 'authenticated', array['SELECT'], 'authenticated: select on bid_audit_log');
select table_privs_are('public', t, 'authenticated', array[]::text[], 'authenticated has no privileges on ' || t)
  from unnest(array['bid_versions','bid_version_files','bid_withdrawals']) t;
select column_privs_are('public', 'bid_drafts', c, 'authenticated', array['SELECT', 'UPDATE'],
  'authenticated may update bid_drafts.' || c)
  from unnest(array['item_cents','alternate_cents','bid_bond_choice']) c;
select column_privs_are('public', 'bid_drafts', c, 'authenticated', array['SELECT'],
  'authenticated may not update bid_drafts.' || c)
  from unnest(array['bid_id','version','updated_at']) c;
select column_privs_are('public', 'bid_draft_files', c, 'authenticated', array['INSERT', 'SELECT'],
  'authenticated may insert bid_draft_files.' || c)
  from unnest(array['bid_id','slot','path','file_name']) c;
select sequence_privs_are('public', 'bid_audit_log_id_seq', r, array[]::text[], r || ' has no privileges on the audit sequence')
  from unnest(array['anon','authenticated','service_role']) r;

select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'app'::regnamespace
      and p.proname in ('bidding_open','bids_closed','latest_version','is_withdrawn','path_bid_id',
                        'can_upload_bid_file','can_read_bid_file','can_delete_bid_file','bid_draft_file_path_unused')
      and p.prosecdef and p.proconfig @> array['search_path=""']),
  array['bid_draft_file_path_unused','bidding_open','bids_closed','can_delete_bid_file','can_read_bid_file',
        'can_upload_bid_file','is_withdrawn','latest_version','path_bid_id'],
  'bid helpers are security definer with an empty search_path');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'app'::regnamespace
      and p.proname in ('bidding_open','bids_closed','path_bid_id',
                        'can_upload_bid_file','can_read_bid_file','can_delete_bid_file')
      and (has_function_privilege('anon', p.oid, 'execute')
           or has_function_privilege('service_role', p.oid, 'execute')
           or not has_function_privilege('authenticated', p.oid, 'execute'))),
  0, 'policy helpers execute for authenticated only');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'app'::regnamespace
      and p.proname in ('latest_version','is_withdrawn','bid_draft_file_path_unused','touch_bid_draft')
      and (has_function_privilege('anon', p.oid, 'execute')
           or has_function_privilege('authenticated', p.oid, 'execute')
           or has_function_privilege('service_role', p.oid, 'execute'))),
  0, 'latest_version, is_withdrawn and the trigger functions execute for no API role');

select is((select row(public, file_size_limit)::text from storage.buckets where id = 'bid-files'),
  '(f,104857600)', 'bid-files is a private 100 MB bucket');

-- ---------------------------------------------------------------------------
-- Helpers (as the superuser; auth-independent ones).
-- ---------------------------------------------------------------------------
select is(app.path_bid_id(:'path_a'), :'bid_a'::uuid, 'path_bid_id parses bids/{bid}/{upload}/{file}');
select is(app.path_bid_id('bids/00000000-0000-0000-0000-0000000009b1/11111111-1111-4111-8111-111111111111/..'), null,
  'path_bid_id rejects ..');
select is(app.path_bid_id('bids/00000000-0000-0000-0000-0000000009b1/x..y.pdf'), null,
  'path_bid_id rejects a missing upload segment and ..');
select is(app.path_bid_id('bids/00000000-0000-0000-0000-0000000009b1/11111111-1111-4111-8111-111111111111/a/b.pdf'), null,
  'path_bid_id rejects nested paths');
select is(app.path_bid_id('solicitations/00000000-0000-0000-0000-0000000009b1/x.pdf'), null,
  'path_bid_id rejects other prefixes');
select is(app.latest_version(:'bid_a'), 1, 'latest_version is 1 for A');
select is(app.latest_version(:'bid_b'), null, 'latest_version is null with no versions');
select is(app.is_withdrawn(:'bid_a', 1), false, 'is_withdrawn is false without a withdrawal');
select is(app.bidding_open(:'sol'), true, 'bidding_open before the due time');
select is(app.bids_closed(:'sol'), false, 'bids_closed is false before the due time');
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000009a1', :'author', now() + interval '1 day',
  '{}'::jsonb) as sol_unreleased \gset
select tests.set_bid_due(:'sol_unreleased', now() + interval '2 days');
alter table public.solicitations disable trigger solicitations_published_frozen;
update public.solicitations set release_date = app.today() + 1 where id = :'sol_unreleased';
alter table public.solicitations enable trigger solicitations_published_frozen;
select is(app.bidding_open(:'sol_unreleased'), false, 'bidding_open is false before release');
select is(app.bids_closed(gen_random_uuid()), false, 'bids_closed is false for an unknown solicitation');
select throws_ok($$insert into public.bids (solicitation_id, bidder_org_id, reference, created_by)
  values ('$$ || :'sol_unreleased' || $$', '$$ || :'org_b' || $$', 'K7QO-2XVD', '$$ || :'bidder_b' || $$')$$,
  '23514', null, 'a reference with O is rejected by the check');
select throws_ok($$insert into public.bids (solicitation_id, bidder_org_id, reference, created_by)
  values ('$$ || :'sol' || $$', '$$ || :'org_a' || $$', 'ABCD-EFGH', '$$ || :'bidder_a' || $$')$$,
  '23505', null, 'one bid per bidder and solicitation');
select throws_ok($$insert into public.bid_versions (bid_id, version, submitted_by, item_cents, alternate_cents, bidder_legal_name)
  values ('00000000-0000-0000-0000-0000000009b2', 1, '$$ || :'bidder_b' || $$', '{100,null}', '{}', 'Bidder B')$$,
  '23514', null, 'a submitted version cannot hold a null price');

-- ---------------------------------------------------------------------------
-- Bidder A: own rows only; never submitted versions.
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_a');
select is((select array_agg(id) from public.bids), array[:'bid_a'::uuid], 'bidder A sees only its own bid');
select is((select array_agg(bid_id) from public.bid_drafts), array[:'bid_a'::uuid], 'bidder A sees only its own draft');
select is((select array_agg(path) from public.bid_draft_files), array[:'path_a'], 'bidder A sees only its own draft files');
select is((select count(*)::int from public.bid_audit_log), 0, 'bidder A reads no bid audit rows');
select throws_ok('select 1 from public.bid_versions', '42501', null, 'bidder A cannot select bid_versions');
select throws_ok('select 1 from public.bid_version_files', '42501', null, 'bidder A cannot select bid_version_files');
select throws_ok('select 1 from public.bid_withdrawals', '42501', null, 'bidder A cannot select bid_withdrawals');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_a'), 1,
  'bidder A reads its draft-referenced file');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_old'), 0,
  'bidder A cannot read its own submitted file');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_b'), 0,
  'bidder A cannot read bidder B''s file');

-- Draft updates while open
with u as (update public.bid_drafts set item_cents = '{12500000,234567}' where bid_id = :'bid_a' returning 1)
select is((select count(*)::int from u), 1, 'bidder A updates its draft prices while open');
select is((select updated_at from public.bid_drafts where bid_id = :'bid_a'), now(),
  'touch_bid_draft moves updated_at to the update time');
select throws_ok($$update public.bid_drafts set version = 9$$, '42501', null, 'bidder A cannot change the draft version');
select throws_ok($$update public.bid_drafts set item_cents = '{-1}'$$, '23514', null, 'negative cents are rejected');
select throws_ok($$update public.bid_drafts set alternate_cents = '{1000000000000}'$$, '23514', null,
  'cents above the cap are rejected');
with u as (update public.bid_drafts set item_cents = '{1}' where bid_id = :'bid_b' returning 1)
select is((select count(*)::int from u), 0, 'bidder A cannot update bidder B''s draft');

-- Draft file rows
select throws_ok(format($$insert into public.bid_draft_files (bid_id, slot, path, file_name) values (%L, 'references', %L, 'x.pdf')$$,
  :'bid_a', 'bids/00000000-0000-0000-0000-0000000009b2/66666666-6666-4666-8666-666666666666/x.pdf'),
  '42501', null, 'a draft file path outside bids/{bid_id}/ fails RLS');
select throws_ok(format($$insert into public.bid_draft_files (bid_id, slot, path, file_name) values (%L, 'references', %L, 'x.pdf')$$,
  :'bid_b', :'path_b' || '.2'),
  '42501', null, 'bidder A cannot attach files to bidder B''s draft');
select throws_ok(format($$insert into public.bid_draft_files (bid_id, slot, path, file_name) values (%L, 'insurance', %L, 'old.pdf')$$,
  :'bid_a', :'path_old'),
  '23505', null, 'a path already in bid_version_files cannot join a draft');
select lives_ok(format($$insert into public.bid_draft_files (bid_id, slot, path, file_name) values (%L, 'insurance', %L, 'ins.pdf')$$,
  :'bid_a', :'path_ins'), 'bidder A attaches a file row to its draft');

-- Storage while open
select lives_ok(format($$insert into storage.objects (bucket_id, name) values ('bid-files', %L)$$, :'path_ins'),
  'bidder A uploads under its own bid while open');
select lives_ok(format($$insert into storage.objects (bucket_id, name) values ('bid-files', %L)$$, :'path_new'),
  'bidder A uploads a second file');
select lives_ok(format($$insert into public.bid_draft_files (bid_id, slot, path, file_name) values (%L, 'references', %L, 'new.pdf')$$,
  :'bid_a', :'path_new'), 'bidder A attaches the second file');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('bid-files', %L)$$,
  'bids/00000000-0000-0000-0000-0000000009b2/77777777-7777-4777-8777-777777777777/x.pdf'),
  '42501', null, 'bidder A cannot upload under bidder B''s bid');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('bid-files', %L)$$,
  'bids/00000000-0000-0000-0000-0000000009b1/q.pdf'),
  '42501', null, 'bidder A cannot upload a malformed path');
delete from storage.objects where bucket_id = 'bid-files' and name in (:'path_ins', :'path_old');
with d as (delete from public.bid_draft_files where bid_id = :'bid_a' and slot = 'insurance' returning 1)
select is((select count(*)::int from d), 1, 'bidder A deletes its draft file row while open');
reset role;
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_ins'), 0,
  'bidder A deleted its draft object');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_old'), 1,
  'bidder A cannot delete a submitted object');

-- ---------------------------------------------------------------------------
-- Bidder B, agency author, office, admin, anon: nothing of A's before close.
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_b');
select is((select count(*)::int from public.bids where id = :'bid_a'), 0, 'bidder B cannot see A''s bid');
select is((select count(*)::int from public.bid_drafts where bid_id = :'bid_a'), 0, 'bidder B cannot see A''s draft');
select is((select count(*)::int from public.bid_draft_files where bid_id = :'bid_a'), 0, 'bidder B cannot see A''s draft files');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name like 'bids/' || :'bid_a' || '/%'), 0,
  'bidder B reads none of A''s files');
select throws_ok('select 1 from public.bid_versions', '42501', null, 'bidder B cannot select bid_versions');
-- The path-uniqueness trigger is not an oracle: B probing A's submitted path gets RLS (42501), never 23505.
select throws_ok(format($$insert into public.bid_draft_files (bid_id, slot, path, file_name) values (%L, 'insurance', %L, 'x.pdf')$$,
  :'bid_b', :'path_old'), '42501', null, 'bidder B attaching A''s submitted path to its own draft gets 42501');
select throws_ok(format($$insert into public.bid_draft_files (bid_id, slot, path, file_name) values (%L, 'insurance', %L, 'x.pdf')$$,
  :'bid_a', :'path_old'), '42501', null, 'bidder B attaching A''s submitted path to A''s draft gets 42501');

select tests.act_as(:'author');
select is((select count(*)::int from public.bids), 0, 'agency author sees no bids');
select is((select count(*)::int from public.bid_drafts), 0, 'agency author sees no drafts');
select is((select count(*)::int from public.bid_draft_files), 0, 'agency author sees no draft files');
select is((select count(*)::int from public.bid_audit_log), 0, 'agency author sees no bid audit rows');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files'), 0, 'agency author reads no bid files');
select throws_ok('select 1 from public.bid_versions', '42501', null, 'agency author cannot select bid_versions');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('bid-files', %L)$$,
  'bids/00000000-0000-0000-0000-0000000009b1/88888888-8888-4888-8888-888888888888/x.pdf'),
  '42501', null, 'agency author cannot upload bid files');

select tests.act_as(:'office_u');
select is((select count(*)::int from public.bids), 0, 'office sees no bids directly');
select is((select count(*)::int from public.bid_drafts), 0, 'office sees no drafts');
select is((select count(*)::int from public.bid_draft_files), 0, 'office sees no draft files');
select is((select count(*)::int from public.bid_audit_log where solicitation_id = :'sol'), 0, 'office reads no bid audit rows before close');
select throws_ok('select 1 from public.bid_versions', '42501', null, 'office cannot select bid_versions');
select throws_ok('select 1 from public.bid_version_files', '42501', null, 'office cannot select bid_version_files');
select throws_ok('select 1 from public.bid_withdrawals', '42501', null, 'office cannot select bid_withdrawals');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files'
           and name like 'bids/00000000-0000-0000-0000-0000000009b%'), 0, 'office reads no bid files before close');

select tests.act_as(:'admin_u');
select is((select count(*)::int from public.bids), 0, 'admin sees no bids directly');
select is((select count(*)::int from public.bid_drafts), 0, 'admin sees no drafts');
select is((select count(*)::int from public.bid_audit_log where solicitation_id = :'sol'), 0, 'admin reads no bid audit rows before close');
select throws_ok('select 1 from public.bid_versions', '42501', null, 'admin cannot select bid_versions');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files'
           and name like 'bids/00000000-0000-0000-0000-0000000009b%'), 0, 'admin reads no bid files before close');

select tests.act_as_anon();
select throws_ok('select 1 from public.bids', '42501', null, 'anon cannot select bids');
select throws_ok('select 1 from public.bid_drafts', '42501', null, 'anon cannot select bid_drafts');
select throws_ok('select 1 from public.bid_versions', '42501', null, 'anon cannot select bid_versions');
select throws_ok('select 1 from public.bid_audit_log', '42501', null, 'anon cannot select bid_audit_log');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files'), 0, 'anon reads no bid files');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('bid-files', %L)$$,
  'bids/00000000-0000-0000-0000-0000000009b1/99999999-9999-4999-8999-999999999999/x.pdf'),
  '42501', null, 'anon cannot upload bid files');

-- ---------------------------------------------------------------------------
-- service_role: every sealed table is revoked, so BYPASSRLS does not help.
-- ---------------------------------------------------------------------------
select tests.act_as_service_role();
select throws_ok('select 1 from public.' || t, '42501', null, 'service_role cannot select ' || t)
  from unnest(array['bids','bid_drafts','bid_draft_files','bid_versions','bid_version_files',
                    'bid_withdrawals','bid_audit_log']) t;
select throws_ok($$insert into public.bid_audit_log (solicitation_id, action) values ('$$ || :'sol' || $$', 'x')$$,
  '42501', null, 'service_role cannot insert into bid_audit_log');
-- ACCEPTED LIMIT (Ruling 3, Drew 2026-11-17): Supabase's storage admin grants service_role full access (arwdDxtm)
-- to storage.objects and storage.buckets, and migrations (run as `postgres`) cannot revoke it. So the service-role
-- key can read, replace or delete sealed bid files in Storage before close, and can update the bid-files bucket row
-- (e.g. make it public), like the database superuser. Bid prices in tables stay sealed (above), and app code never
-- touches bid files with the admin client. If Supabase changes these grants, these assertions fail: revisit the seal.
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files'
           and name like 'bids/00000000-0000-0000-0000-0000000009b%'), 4,
  'ACCEPTED LIMIT (Ruling 3): service_role can read bid-files objects');
select ok(has_table_privilege('service_role', 'storage.objects', 'select'),
  'ACCEPTED LIMIT (Ruling 3): service_role holds select on storage.objects');
select ok(has_table_privilege('service_role', 'storage.objects', 'insert'),
  'ACCEPTED LIMIT (Ruling 3): service_role holds insert on storage.objects');
select ok(has_table_privilege('service_role', 'storage.objects', 'update'),
  'ACCEPTED LIMIT (Ruling 3): service_role holds update on storage.objects');
select ok(has_table_privilege('service_role', 'storage.objects', 'delete'),
  'ACCEPTED LIMIT (Ruling 3): service_role holds delete on storage.objects');
select ok(has_table_privilege('service_role', 'storage.buckets', 'update'),
  'ACCEPTED LIMIT (Ruling 3): service_role holds update on storage.buckets');
with u as (update storage.buckets set public = true where id = 'bid-files' returning 1)
select is((select count(*)::int from u), 1, 'ACCEPTED LIMIT (Ruling 3): service_role can make bid-files public');
reset role;
update storage.buckets set public = false where id = 'bid-files';

-- ---------------------------------------------------------------------------
-- A path that is also in a submitted version is no longer readable by the bidder.
-- ---------------------------------------------------------------------------
insert into public.bid_versions (id, bid_id, version, submitted_by, item_cents, alternate_cents, bidder_legal_name)
values (:'v2', :'bid_a', 2, :'bidder_a', '{300,400}', '{60}', 'Bidder A');
insert into public.bid_version_files (version_id, slot, path, file_name) values (:'v2', 'qualifications', :'path_a', 'q.pdf');
select is(app.latest_version(:'bid_a'), 2, 'latest_version is 2 after v2');

select tests.act_as(:'bidder_a');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_a'), 0,
  'bidder A cannot read a draft file once it is in a submitted version');
select tests.act_as(:'office_u');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_a'), 0,
  'office cannot read the latest version''s file before close');
reset role;

-- ---------------------------------------------------------------------------
-- At the due time (closed = now() >= bid_due_at).
-- ---------------------------------------------------------------------------
select tests.set_bid_due(:'sol', now());
select is(app.bids_closed(:'sol'), true, 'bids_closed at exactly the due time');
select is(app.bidding_open(:'sol'), false, 'bidding_open is false at exactly the due time');

select tests.act_as(:'bidder_a');
with u as (update public.bid_drafts set item_cents = '{12500000,234567}' where bid_id = :'bid_a' returning 1)
select is((select count(*)::int from u), 0, 'bidder A cannot update its draft after close');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('bid-files', %L)$$,
  'bids/00000000-0000-0000-0000-0000000009b1/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/late.pdf'),
  '42501', null, 'bidder A cannot upload after close');
select throws_ok(format($$insert into public.bid_draft_files (bid_id, slot, path, file_name) values (%L, 'insurance', %L, 'late.pdf')$$,
  :'bid_a', 'bids/00000000-0000-0000-0000-0000000009b1/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/late.pdf'),
  '42501', null, 'bidder A cannot attach a draft file after close');
delete from storage.objects where bucket_id = 'bid-files' and name = :'path_new';
select is((select count(*)::int from public.bid_audit_log), 0, 'bidder A reads no bid audit rows after close');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_a'), 0,
  'bidder A still cannot read its submitted file after close');
reset role;
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_new'), 1,
  'bidder A cannot delete an attached draft object after close');

select tests.act_as(:'office_u');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_a'), 1,
  'office reads the latest version''s file at close');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_old'), 0,
  'office cannot read a superseded version''s file');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_b'), 0,
  'office cannot read draft-only files');
select is((select count(*)::int from public.bid_audit_log where solicitation_id = :'sol'), 1,
  'office reads the bid audit rows after close');
select throws_ok('select 1 from public.bid_versions', '42501', null, 'office still cannot select bid_versions directly');

select tests.act_as(:'author');
select is((select count(*)::int from public.bid_audit_log), 0, 'agency author reads no bid audit rows after close');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files'), 0, 'agency author reads no bid files after close');
select tests.act_as_anon();
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files'), 0, 'anon reads no bid files after close');
select tests.act_as_service_role();
select throws_ok('select 1 from public.bid_versions', '42501', null, 'service_role cannot select bid_versions after close');
reset role;

insert into public.bid_withdrawals (bid_id, version, withdrawn_by) values (:'bid_a', 2, :'bidder_a');
select is(app.is_withdrawn(:'bid_a', 2), true, 'is_withdrawn is true after a withdrawal');
select throws_ok(format($$insert into public.bid_withdrawals (bid_id, version, withdrawn_by) values (%L, 7, %L)$$,
  :'bid_a', :'bidder_a'), '23503', null, 'a withdrawal must name an existing version');
select tests.act_as(:'office_u');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name = :'path_a'), 0,
  'office cannot read a withdrawn latest version''s file');
reset role;

-- ---------------------------------------------------------------------------
-- Append-only for every role, the superuser included.
-- ---------------------------------------------------------------------------
select throws_ok(format('update public.%I set bid_id = bid_id', t), 'P0001', null, 'superuser cannot update ' || t)
  from unnest(array['bid_versions','bid_withdrawals','bid_audit_log']) t;
select throws_ok('update public.bid_version_files set file_name = file_name', 'P0001', null,
  'superuser cannot update bid_version_files');
select throws_ok(format('delete from public.%I', t), 'P0001', null, 'superuser cannot delete from ' || t)
  from unnest(array['bid_versions','bid_version_files','bid_withdrawals','bid_audit_log']) t;
select throws_ok(format('truncate public.%I cascade', t), 'P0001', null, 'superuser cannot truncate ' || t)
  from unnest(array['bid_versions','bid_version_files','bid_withdrawals','bid_audit_log']) t;

select tests.act_as(:'office_u');
select throws_ok(format('delete from public.%I', t), '42501', null, 'office cannot delete from ' || t)
  from unnest(array['bid_versions','bid_version_files','bid_withdrawals','bid_audit_log']) t;
select throws_ok('update public.bid_audit_log set action = action', '42501', null, 'office cannot update bid_audit_log');
select tests.act_as(:'bidder_a');
select throws_ok(format('delete from public.%I', t), '42501', null, 'bidder cannot delete from ' || t)
  from unnest(array['bid_versions','bid_version_files','bid_withdrawals','bid_audit_log']) t;
select tests.act_as_anon();
select throws_ok(format('delete from public.%I', t), '42501', null, 'anon cannot delete from ' || t)
  from unnest(array['bid_versions','bid_version_files','bid_withdrawals','bid_audit_log']) t;
select tests.act_as_service_role();
select throws_ok(format('delete from public.%I', t), '42501', null, 'service_role cannot delete from ' || t)
  from unnest(array['bid_versions','bid_version_files','bid_withdrawals','bid_audit_log']) t;
select throws_ok(format('update public.%I set bid_id = bid_id', t), '42501', null, 'service_role cannot update ' || t)
  from unnest(array['bid_versions','bid_withdrawals','bid_audit_log']) t;
select throws_ok('truncate public.bid_audit_log', '42501', null, 'service_role cannot truncate bid_audit_log');
reset role;

select * from finish();
rollback;
