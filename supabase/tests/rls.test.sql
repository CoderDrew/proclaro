-- Row-level security, column privileges, append-only tables and storage access.
begin;

select plan(59);

-- ---------------------------------------------------------------------------
-- Fixtures (as postgres). Fixed ids for orgs/solicitations; users via helper.
-- ---------------------------------------------------------------------------
insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000000f1', 'Test Office',   'office'),
  ('00000000-0000-0000-0000-0000000000a1', 'Test Agency A', 'agency'),
  ('00000000-0000-0000-0000-0000000000b1', 'Test Agency B', 'agency');

select tests.make_user('a@test.test', '00000000-0000-0000-0000-0000000000a1', false) as author_a \gset
select tests.make_user('b@test.test', '00000000-0000-0000-0000-0000000000b1', false) as author_b \gset
select tests.make_user('o@test.test', '00000000-0000-0000-0000-0000000000f1', false) as office_u \gset

-- 5a1 draft A, 5b1 draft B, 5a2 submitted A,
-- 5a3 published A released yesterday, 5a4 published A released today,
-- 5a5 published A releasing tomorrow, 5a6 approved A.
insert into public.solicitations (id, agency_id, created_by, state, data, release_date, published_at) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a1', :'author_a', 'draft',     '{"title":"A draft"}', null, null),
  ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000000b1', :'author_b', 'draft',     '{"title":"B draft"}', null, null),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a1', :'author_a', 'submitted', '{"title":"A sub"}',   null, null),
  ('00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000000a1', :'author_a', 'published', '{"title":"A past"}',  app.today() - 1, now()),
  ('00000000-0000-0000-0000-0000000005a4', '00000000-0000-0000-0000-0000000000a1', :'author_a', 'published', '{"title":"A today"}', app.today(),     now()),
  ('00000000-0000-0000-0000-0000000005a5', '00000000-0000-0000-0000-0000000000a1', :'author_a', 'published', '{"title":"A next"}',  app.today() + 1, now()),
  ('00000000-0000-0000-0000-0000000005a6', '00000000-0000-0000-0000-0000000000a1', :'author_a', 'approved',  '{"title":"A appr"}',  null,            null);

insert into public.comments (solicitation_id, field, body, kind, author_id) values
  ('00000000-0000-0000-0000-0000000005a1', 'title', 'fix A', 'note', :'office_u'),
  ('00000000-0000-0000-0000-0000000005b1', 'title', 'fix B', 'note', :'office_u');

insert into public.warning_acks (solicitation_id, code, field, acked_by) values
  ('00000000-0000-0000-0000-0000000005a1', 'W1', 'title', :'author_a'),
  ('00000000-0000-0000-0000-0000000005b1', 'W1', 'title', :'author_b');

insert into public.audit_log (solicitation_id, actor_id, action, detail) values
  ('00000000-0000-0000-0000-0000000005a1', :'author_a', 'create', '{}'),
  ('00000000-0000-0000-0000-0000000005b1', :'author_b', 'create', '{}');

insert into public.clauses (key, version, body, created_by) values
  ('test-clause', 1, 'Plain text.', :'office_u');

insert into storage.objects (bucket_id, name) values
  ('attachments', 'solicitations/00000000-0000-0000-0000-0000000005a1/a.pdf'),
  ('attachments', 'solicitations/00000000-0000-0000-0000-0000000005b1/b.pdf'),
  ('published',   'solicitations/00000000-0000-0000-0000-0000000005a3/v1/rfb.pdf'),
  ('published',   'solicitations/00000000-0000-0000-0000-0000000005a5/v1/rfb.pdf');

-- ---------------------------------------------------------------------------
-- Agency A author
-- ---------------------------------------------------------------------------
select tests.act_as(:'author_a');

select is((select count(*)::int from public.solicitations where id = '00000000-0000-0000-0000-0000000005a1'), 1,
  'agency A sees its own draft');
select is((select count(*)::int from public.solicitations where id = '00000000-0000-0000-0000-0000000005b1'), 0,
  'agency A sees 0 rows of agency B''s draft');
select is((select count(*)::int from public.comments where solicitation_id = '00000000-0000-0000-0000-0000000005a1'), 1,
  'agency A sees comments on its own solicitation');
select is((select count(*)::int from public.comments where solicitation_id = '00000000-0000-0000-0000-0000000005b1'), 0,
  'agency A sees no comments on agency B''s solicitation');
select is((select count(*)::int from public.warning_acks where solicitation_id = '00000000-0000-0000-0000-0000000005a1'), 1,
  'agency A sees warning acks on its own solicitation');
select is((select count(*)::int from public.warning_acks where solicitation_id = '00000000-0000-0000-0000-0000000005b1'), 0,
  'agency A sees no warning acks on agency B''s solicitation');
select is((select count(*)::int from public.audit_log where solicitation_id = '00000000-0000-0000-0000-0000000005a1'), 1,
  'agency A sees audit entries on its own solicitation');
select is((select count(*)::int from public.audit_log where solicitation_id = '00000000-0000-0000-0000-0000000005b1'), 0,
  'agency A sees no audit entries on agency B''s solicitation');

-- data edits: own draft yes, submitted no
select lives_ok(
  $$update public.solicitations set data = '{"title":"A draft v2"}' where id = '00000000-0000-0000-0000-0000000005a1'$$,
  'agency A can update data on its own draft');
select is((select data->>'title' from public.solicitations where id = '00000000-0000-0000-0000-0000000005a1'), 'A draft v2',
  'the draft data update took effect');
with u as (
  update public.solicitations set data = '{"title":"hack"}'
  where id = '00000000-0000-0000-0000-0000000005a2' returning 1
) select is((select count(*)::int from u), 0, 'data update on a submitted row affects 0 rows');
with u as (
  update public.solicitations set data = '{"title":"hack"}'
  where id = '00000000-0000-0000-0000-0000000005b1' returning 1
) select is((select count(*)::int from u), 0, 'data update on agency B''s draft affects 0 rows');

-- column privileges
select throws_ok(
  $$update public.solicitations set state = 'published' where id = '00000000-0000-0000-0000-0000000005a1'$$,
  '42501', null, 'agency author cannot update state directly');
select throws_ok(
  $$update public.solicitations set number = '27-0001' where id = '00000000-0000-0000-0000-0000000005a1'$$,
  '42501', null, 'agency author cannot update number directly');
select throws_ok(
  $$delete from public.solicitations where id = '00000000-0000-0000-0000-0000000005a1'$$,
  '42501', null, 'agency author cannot delete solicitations');

-- inserts
select lives_ok(
  format($$insert into public.solicitations (agency_id, created_by, data) values ('00000000-0000-0000-0000-0000000000a1', %L, '{}')$$, :'author_a'),
  'agency author can insert a draft for their own agency');
select throws_ok(
  format($$insert into public.solicitations (agency_id, created_by, data) values ('00000000-0000-0000-0000-0000000000b1', %L, '{}')$$, :'author_a'),
  '42501', null, 'agency author cannot insert for another agency');
select throws_ok(
  format($$insert into public.solicitations (agency_id, created_by, data) values ('00000000-0000-0000-0000-0000000000a1', %L, '{}')$$, :'author_b'),
  '42501', null, 'agency author cannot insert as another user');
select throws_ok(
  format($$insert into public.solicitations (agency_id, created_by, state, data) values ('00000000-0000-0000-0000-0000000000a1', %L, 'published', '{}')$$, :'author_a'),
  '42501', null, 'agency author cannot insert a non-draft state');

-- other direct writes
select throws_ok(
  format($$insert into public.audit_log (solicitation_id, actor_id, action) values ('00000000-0000-0000-0000-0000000005a1', %L, 'x')$$, :'author_a'),
  '42501', null, 'agency author cannot insert audit entries directly');
select throws_ok(
  format($$insert into public.comments (solicitation_id, body, kind, author_id) values ('00000000-0000-0000-0000-0000000005a1', 'x', 'note', %L)$$, :'author_a'),
  '42501', null, 'agency author cannot insert comments directly');

-- append-only
select throws_ok($$update public.audit_log set action = 'x'$$, '42501', null, 'authenticated cannot update audit_log');
select throws_ok($$delete from public.audit_log$$,             '42501', null, 'authenticated cannot delete audit_log');
select throws_ok($$update public.clauses set body = 'x'$$,     '42501', null, 'authenticated cannot update clauses');
select throws_ok($$delete from public.clauses$$,               '42501', null, 'authenticated cannot delete clauses');

-- storage
select is((select count(*)::int from storage.objects where bucket_id = 'attachments'
           and name like 'solicitations/00000000-0000-0000-0000-0000000005a1/%'), 1,
  'agency A reads its own attachments');
select is((select count(*)::int from storage.objects where bucket_id = 'attachments'
           and name like 'solicitations/00000000-0000-0000-0000-0000000005b1/%'), 0,
  'agency A cannot read agency B''s attachments');
select is((select count(*)::int from storage.objects where bucket_id = 'published'
           and name like 'solicitations/00000000-0000-0000-0000-0000000005%'), 1,
  'agency A reads only released files in the published bucket');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('attachments', 'solicitations/00000000-0000-0000-0000-0000000005b1/x.pdf')$$,
  '42501', null, 'agency A cannot upload into agency B''s attachments');
select lives_ok(
  $$insert into storage.objects (bucket_id, name) values ('attachments', 'solicitations/00000000-0000-0000-0000-0000000005a1/x.pdf')$$,
  'agency A can upload into its own draft''s attachments');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/00000000-0000-0000-0000-0000000005a1/v1/x.pdf')$$,
  '42501', null, 'agency A cannot write to the published bucket');

-- ---------------------------------------------------------------------------
-- Office user
-- ---------------------------------------------------------------------------
reset role;
select tests.act_as(:'office_u');

select is((select count(*)::int from public.solicitations
           where id in ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000005b1')), 2,
  'office sees both agencies'' drafts');
select is((select count(*)::int from public.comments where solicitation_id in ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000005b1')), 2, 'office sees all comments');
select is((select count(*)::int from public.warning_acks where solicitation_id in ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000005b1')), 2, 'office sees all warning acks');
select is((select count(*)::int from public.audit_log where solicitation_id in ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000005b1')), 2, 'office sees all audit entries');
select is((select count(*)::int from storage.objects where bucket_id = 'attachments'
           and name like 'solicitations/00000000-0000-0000-0000-0000000005%'), 3,
  'office reads all attachments');
select is((select count(*)::int from storage.objects where bucket_id = 'published'
           and name like 'solicitations/00000000-0000-0000-0000-0000000005%'), 2,
  'office reads released and unreleased published files');
select lives_ok(
  $$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/00000000-0000-0000-0000-0000000005a6/v1/rfb.pdf')$$,
  'office can write to the published bucket');
select throws_ok(
  format($$insert into public.solicitations (agency_id, created_by, data) values ('00000000-0000-0000-0000-0000000000f1', %L, '{}')$$, :'office_u'),
  '42501', null, 'office user cannot insert a solicitation');
with u as (
  update public.solicitations set data = '{"title":"office"}'
  where id = '00000000-0000-0000-0000-0000000005a1' returning 1
) select is((select count(*)::int from u), 0, 'office cannot update draft data directly');

-- ---------------------------------------------------------------------------
-- Anon
-- ---------------------------------------------------------------------------
reset role;
select tests.act_as_anon();

select is((select count(*)::int from public.solicitations where state <> 'published'), 0, 'anon sees 0 non-published rows');
select results_eq(
  $$select id from public.solicitations where id::text like '00000000-0000-0000-0000-0000000005%' order by id$$,
  $$values ('00000000-0000-0000-0000-0000000005a3'::uuid), ('00000000-0000-0000-0000-0000000005a4'::uuid)$$,
  'anon sees published rows only once release_date <= app.today()');
select throws_ok($$select count(*) from public.comments$$,     '42501', null, 'anon cannot read comments');
select throws_ok($$select count(*) from public.audit_log$$,    '42501', null, 'anon cannot read audit_log');
select throws_ok($$select count(*) from public.warning_acks$$, '42501', null, 'anon cannot read warning acks');
select is((select count(*)::int from storage.objects where bucket_id = 'attachments'), 0, 'anon reads no attachments');
select is((select count(*)::int from storage.objects where bucket_id = 'published'
           and name like 'solicitations/00000000-0000-0000-0000-0000000005a3/%'), 1,
  'anon reads files of a released published solicitation');
select is((select count(*)::int from storage.objects where bucket_id = 'published'
           and name like 'solicitations/00000000-0000-0000-0000-0000000005a5/%'), 0,
  'anon sees 0 files of a published solicitation releasing tomorrow');
select is((select count(*)::int from storage.objects where bucket_id = 'published'
           and name like 'solicitations/00000000-0000-0000-0000-0000000005a6/%'), 0,
  'anon sees 0 files of a not-yet-published solicitation');
select throws_ok($$delete from public.audit_log$$, '42501', null, 'anon cannot delete audit_log');

-- ---------------------------------------------------------------------------
-- service_role and the owner
-- ---------------------------------------------------------------------------
reset role;
set local role service_role;
select throws_ok($$update public.audit_log set action = 'x'$$, '42501', null, 'service_role cannot update audit_log');
select throws_ok($$delete from public.audit_log$$,             '42501', null, 'service_role cannot delete audit_log');
select throws_ok($$update public.clauses set body = 'x'$$,     '42501', null, 'service_role cannot update clauses');

reset role;
select throws_ok($$update public.audit_log set action = 'x'$$, 'P0001', null, 'even the table owner cannot update audit_log');
select throws_ok($$delete from public.audit_log$$,             'P0001', null, 'even the table owner cannot delete audit_log');
select throws_ok(
  $$update public.solicitations set data = '{}' where id = '00000000-0000-0000-0000-0000000005a3'$$,
  'P0001', null, 'a published solicitation cannot be updated by any role');
select lives_ok(
  $$update public.solicitations set state = 'published', release_date = app.today(), published_at = now()
    where id = '00000000-0000-0000-0000-0000000005a6'$$,
  'the owner can move an approved row to published');
select throws_ok(
  $$update public.solicitations set data = '{}' where id = '00000000-0000-0000-0000-0000000005a6'$$,
  'P0001', null, 'a row is frozen once it has been published');

select is((select public from storage.buckets where id = 'published'), false,
  'the published bucket is private (downloads go through signed URLs or a server route)');

select * from finish();
rollback;
