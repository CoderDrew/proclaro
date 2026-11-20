-- 0015: the apprentice commitment on $1M+ bids (slice 2b, Task 2). Sealed with the prices: drafted by the bidder
-- while bidding is open, copied into bid_versions at submit, never readable by any API role (service_role included).
begin;

select plan(39);

select set_config('storage.allow_delete_query', 'true', true);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000ab1', 'AP Office', 'office'),
  ('00000000-0000-0000-0000-000000000aa7', 'AP Agency', 'agency');

select tests.make_user('ap.author@test.test', '00000000-0000-0000-0000-000000000aa7') as author \gset
select tests.make_user('ap.office@test.test', '00000000-0000-0000-0000-000000000ab1') as office_u \gset
select tests.make_bidder('ap.bidder@test.test', 'AP Bidder') as bidder \gset
select tests.make_bidder('ap.late@test.test', 'AP Late Bidder') as late \gset

\set agency '00000000-0000-0000-0000-000000000aa7'
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day',
  '{"estimateCents": 100000000, "optionalSections": []}'::jsonb) as sol \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day',
  '{"estimateCents": 99999999, "optionalSections": []}'::jsonb) as sol_small \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day',
  '{"estimateCents": 100000000, "optionalSections": []}'::jsonb) as sol_late \gset

-- Test-only helpers (rolled back with the transaction).
-- The error a statement raises, as 'sqlstate|message|detail', or 'ok'.
create function tests.ap_error(p_sql text)
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
-- The number of rows a statement changed.
create function tests.ap_rows(p_sql text)
returns int
language plpgsql
as $$
declare
  v_n int;
begin
  execute p_sql;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
-- Fill a draft as the calling bidder (RLS applies): prices, paper bond, insurance uploaded and attached.
create function tests.ap_fill(p_bid uuid)
returns void
language plpgsql
as $$
declare
  v_ins text := 'bids/' || p_bid || '/' || gen_random_uuid() || '/ins.pdf';
begin
  update public.bid_drafts
     set item_cents = '{12500000,234567}', alternate_cents = '{1500000}', bid_bond_choice = 'paper'
   where bid_id = p_bid;
  insert into storage.objects (bucket_id, name, metadata) values
    ('bid-files', v_ins, jsonb_build_object('eTag', '"ap-ins"', 'size', 2048, 'mimetype', 'application/pdf'));
  insert into public.bid_draft_files (bid_id, slot, path, file_name) values (p_bid, 'insurance', v_ins, 'ins.pdf');
end;
$$;
grant execute on function tests.ap_error(text), tests.ap_rows(text), tests.ap_fill(uuid)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Schema, privileges and the helper
-- ---------------------------------------------------------------------------
select has_column('public', 'bid_drafts', 'apprentice_commitment', 'bid_drafts.apprentice_commitment exists');
select col_type_is('public', 'bid_drafts', 'apprentice_commitment', 'boolean', 'bid_drafts.apprentice_commitment is boolean');
select col_is_null('public', 'bid_drafts', 'apprentice_commitment', 'bid_drafts.apprentice_commitment is nullable');
select has_column('public', 'bid_versions', 'apprentice_commitment', 'bid_versions.apprentice_commitment exists');
select col_type_is('public', 'bid_versions', 'apprentice_commitment', 'boolean', 'bid_versions.apprentice_commitment is boolean');
select column_privs_are('public', 'bid_drafts', 'apprentice_commitment', 'authenticated', array['SELECT', 'UPDATE'],
  'authenticated may read and update its draft''s apprentice_commitment (RLS limits rows)');
select column_privs_are('public', 'bid_drafts', 'apprentice_commitment', r, array[]::text[],
  r || ' has no privileges on bid_drafts.apprentice_commitment')
  from unnest(array['anon', 'service_role']) r;
select column_privs_are('public', 'bid_versions', 'apprentice_commitment', r, array[]::text[],
  r || ' has no privileges on bid_versions.apprentice_commitment')
  from unnest(array['anon', 'authenticated', 'service_role']) r;

select has_function('app', 'apprentice_required', array['jsonb'], 'app.apprentice_required(jsonb) exists');
select ok(app.apprentice_required('{"data": {"estimateCents": 100000000}}'), 'required at $1,000,000.00');
select ok(not app.apprentice_required('{"data": {"estimateCents": 99999999}}'), 'not required at $999,999.99');
select ok(not app.apprentice_required('{"data": {"estimateCents": null}}'), 'not required for an unknown estimate');
select is(
  (select count(*)::int from pg_proc p
    where p.oid = 'app.apprentice_required(jsonb)'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')),
  1, 'apprentice_required is security definer, empty search_path, no API role may execute it');

-- ---------------------------------------------------------------------------
-- Clause v2 (insert-only versioning; v1 stays for the locks that hold it)
-- ---------------------------------------------------------------------------
select is((select body from public.clauses where key = 'apprentice_credit' and version = 2),
  E'# Apprenticeship Program Credit\n\nBecause of the size of this project, the bid form asks whether the bidder commits apprentices to at least ten percent of the labor hours on this project. A bid that makes this commitment is evaluated as if its price were one percent lower. The credit is used only to compare bids; the contract amount is the price bid.\n\nA bidder that commits must be able to show, on request, that apprentices from an approved program will work those hours. Answering no does not make a bid ineligible.',
  'apprentice_credit version 2 has the 1% credit wording');
select ok((select body like '%otherwise equal%' from public.clauses where key = 'apprentice_credit' and version = 1),
  'apprentice_credit version 1 is unchanged');
select is((select max(version) from public.clauses where key = 'apprentice_credit'), 2,
  'version 2 is the latest, so new locks take it');
-- A lock taken now picks version 2; a lock row already holding version 1 is untouched by the migration.
insert into public.solicitations (agency_id, created_by, data)
values (:'agency', :'author', tests.solicitation_data()) returning id as sol_new \gset
select app.lock_clauses(:'sol_new');
select is((select clause_version from public.solicitation_clause_locks
            where solicitation_id = :'sol_new' and clause_key = 'apprentice_credit'), 2,
  'a newly locked solicitation gets apprentice_credit version 2');
insert into public.solicitations (agency_id, created_by, data)
values (:'agency', :'author', tests.solicitation_data()) returning id as sol_old \gset
insert into public.solicitation_clause_locks (solicitation_id, clause_key, clause_version)
values (:'sol_old', 'apprentice_credit', 1);
select is((select clause_version from public.solicitation_clause_locks
            where solicitation_id = :'sol_old' and clause_key = 'apprentice_credit'), 1,
  'an existing version 1 lock stays valid');

-- ---------------------------------------------------------------------------
-- Draft problems
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder');
select public.start_bid(:'sol') as bid \gset
select public.start_bid(:'sol_small') as bid_small \gset
select tests.ap_fill(:'bid');
select tests.ap_fill(:'bid_small');
select is((select apprentice_commitment from public.bid_drafts where bid_id = :'bid'), null::boolean,
  'a new draft has no apprentice answer');

reset role;
select is(app.bid_draft_problems(:'bid'), array['apprentice_missing'], '$1M draft without an answer: apprentice_missing');
select is(app.bid_draft_problems(:'bid_small'), array[]::text[], '$999,999.99 draft without an answer: no problem');

select tests.act_as(:'bidder');
select is(tests.ap_error(format('select * from public.submit_bid(%L)', :'bid')),
  'P0001|invalid_bid|apprentice_missing', 'submit_bid refuses a $1M bid without an answer');

select is(tests.ap_rows(format('update public.bid_drafts set apprentice_commitment = true where bid_id = %L', :'bid_small')),
  1, 'the bidder can set an answer on a small draft');
reset role;
select is(app.bid_draft_problems(:'bid_small'), array['apprentice_not_required'],
  '$999,999.99 draft with an answer: apprentice_not_required');
select tests.act_as(:'bidder');
select is(tests.ap_error(format('select * from public.submit_bid(%L)', :'bid_small')),
  'P0001|invalid_bid|apprentice_not_required', 'submit_bid refuses an answer the solicitation does not ask for');

select is(tests.ap_rows(format('update public.bid_drafts set apprentice_commitment = true where bid_id = %L', :'bid')),
  1, 'the bidder sets its commitment while bidding is open');
select is((select apprentice_commitment from public.bid_drafts where bid_id = :'bid'), true,
  'the bidder reads its own draft answer before submit');
select is(tests.ap_error(format('select * from public.submit_bid(%L)', :'bid')), 'ok',
  'submit_bid accepts the $1M bid with an answer');

-- ---------------------------------------------------------------------------
-- The seal: emptied draft, nothing readable back, by any API role
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public.bid_drafts where bid_id = :'bid'), 0, 'the draft is gone after submit');
select throws_ok('select apprentice_commitment from public.bid_versions', '42501', null,
  'the bidder cannot read the sealed commitment');
select tests.act_as(:'office_u');
select throws_ok('select apprentice_commitment from public.bid_versions', '42501', null,
  'office staff cannot read the sealed commitment before close');
select tests.act_as(:'author');
select throws_ok('select apprentice_commitment from public.bid_versions', '42501', null,
  'the agency cannot read the sealed commitment');
reset role;
select tests.act_as_service_role();
select throws_ok('select apprentice_commitment from public.bid_versions', '42501', null,
  'service_role cannot read the sealed commitment');
reset role;
select is((select apprentice_commitment from public.bid_versions where bid_id = :'bid' and version = 1), true,
  'the version row stores the commitment');

-- ---------------------------------------------------------------------------
-- Closed: the answer cannot change
-- ---------------------------------------------------------------------------
select tests.act_as(:'late');
select public.start_bid(:'sol_late') as bid_late \gset
reset role;
select tests.set_bid_due(:'sol_late', now());
select tests.act_as(:'late');
select is(tests.ap_rows(format('update public.bid_drafts set apprentice_commitment = true where bid_id = %L', :'bid_late')),
  0, 'after the due time the bidder''s update changes 0 rows');
reset role;
select is((select apprentice_commitment from public.bid_drafts where bid_id = :'bid_late'), null::boolean,
  'the closed draft still has no answer');

select * from finish();
rollback;
