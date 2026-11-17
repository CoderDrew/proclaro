-- 0005: admin-only writes to settings, holidays, organizations and clauses.
begin;

select plan(16);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000008f1', 'AD Office',   'office'),
  ('00000000-0000-0000-0000-0000000008a1', 'AD Agency A', 'agency');

select tests.make_user('ad.admin@test.test',  '00000000-0000-0000-0000-0000000008f1', true)  as adm \gset
select tests.make_user('ad.office@test.test', '00000000-0000-0000-0000-0000000008f1')        as off \gset
select tests.make_user('ad.author@test.test', '00000000-0000-0000-0000-0000000008a1')        as aut \gset

insert into public.holidays (day, name) values ('2031-03-01', 'AD One'), ('2031-03-02', 'AD Two') on conflict do nothing;
insert into public.settings (id, state_name, office_name) values (1, 'S', 'O')
  on conflict (id) do nothing;

-- Admin can do everything the screens need.
select tests.act_as(:'adm');
select lives_ok($$update public.settings set state_name = 'State of Calder', timezone = 'America/Chicago',
                   fiscal_year_start_month = 10 where id = 1$$, 'admin updates settings');
select lives_ok($$insert into public.holidays (day, name) values ('2031-01-01', 'Test Day')$$, 'admin adds a holiday');
select lives_ok($$delete from public.holidays where day = '2031-01-01'$$, 'admin removes a holiday');
select lives_ok($$insert into public.organizations (name, kind) values ('AD New Agency', 'agency')$$, 'admin creates an org');
select lives_ok($$update public.organizations set name = 'AD New Agency 2' where name = 'AD New Agency'$$, 'admin renames an org');
select lives_ok(format($$insert into public.clauses (key, version, body, created_by) values ('notice', 2, 'x', %L)$$, :'adm'),
  'admin inserts a clause version');
select throws_ok(format($$insert into public.clauses (key, version, body, created_by) values ('notice', 2, 'y', %L)$$, :'adm'),
  '23505', null, 'a second insert of the same (key, version) conflicts');
select throws_ok(format($$insert into public.clauses (key, version, body, created_by) values ('notice', 3, 'y', %L)$$, :'off'),
  '42501', null, 'created_by must be the caller');
select throws_ok($$update public.clauses set body = 'z' where key = 'notice'$$, '42501', null, 'clauses cannot be updated');
select throws_ok($$update public.organizations set kind = 'office' where name = 'AD New Agency 2'$$, '42501', null,
  'org kind cannot be changed');

-- Non-admin office staff: every write is refused (privilege passes, policy hides or rejects the row).
select tests.act_as(:'off');
update public.settings set state_name = 'Hacked' where id = 1;
select throws_ok($$insert into public.holidays (day, name) values ('2031-02-02', 'No')$$, '42501', null,
  'office staff cannot add a holiday');
select throws_ok($$insert into public.organizations (name, kind) values ('AD Rogue', 'agency')$$, '42501', null,
  'office staff cannot create an org');
select throws_ok(format($$insert into public.clauses (key, version, body, created_by) values ('notice', 9, 'x', %L)$$, :'off'),
  '42501', null, 'office staff cannot insert a clause');
update public.organizations set name = 'Hacked' where id = '00000000-0000-0000-0000-0000000008a1';

select tests.act_as(:'aut');
delete from public.holidays;

reset role;
select is((select state_name from public.settings where id = 1), 'State of Calder', 'non-admin settings update changed nothing');
select is((select name from public.organizations where id = '00000000-0000-0000-0000-0000000008a1'), 'AD Agency A',
  'non-admin org rename changed nothing');
select ok((select count(*) from public.holidays where day in ('2031-03-01','2031-03-02')) = 2, 'non-admin delete removed no holidays');

select * from finish();
rollback;
