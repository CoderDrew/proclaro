-- 0036: the advisory AI check. Runs, items, reviews, scans and caps; office only, after close; never an outcome.
begin;

select plan(62);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

create function tests.ac_error(p_sql text)
returns text
language plpgsql
as $$
declare
  v_msg text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_msg = message_text;
  return v_msg;
end;
$$;
grant execute on function tests.ac_error(text) to anon, authenticated, service_role;

-- One signed_form item set for a document, as JSON.
create function tests.ac_items(p_kind text, p_path text, p_code text default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_agg(jsonb_build_object('document_kind', p_kind, 'document_path', p_path, 'item_code', c,
                                      'method', 'ai', 'result', 'met', 'page', 1, 'excerpt', 'Signed', 'extracted', null))
    from unnest(case when p_code is null then app.ai_check_codes(p_kind) else array[p_code] end) c;
$$;
grant execute on function tests.ac_items(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Shape and privileges
-- ---------------------------------------------------------------------------
select has_table('public', 'ai_check_runs', 'ai_check_runs exists');
select has_table('public', 'ai_check_items', 'ai_check_items exists');
select has_table('public', 'ai_check_reviews', 'ai_check_reviews exists');
select has_table('public', 'bid_original_scans', 'bid_original_scans exists');
select ok(not has_table_privilege('authenticated', 'public.ai_check_items', 'insert')
      and not has_table_privilege('authenticated', 'public.ai_check_runs', 'update')
      and not has_table_privilege('authenticated', 'public.ai_check_reviews', 'insert')
      and not has_table_privilege('authenticated', 'public.bid_original_scans', 'select'),
  'no direct API access to the AI check tables');
select ok((select bool_and(has_function_privilege('authenticated', f, 'execute')
                           and not has_function_privilege('anon', f, 'execute'))
             from unnest(array['public.start_ai_check(uuid, text)', 'public.record_ai_check_document(uuid, jsonb)',
                               'public.begin_ai_check_document(uuid, text, text)',
                               'public.finish_ai_check(uuid, text)', 'public.review_ai_check_item(uuid, text, text)',
                               'public.bid_ai_check(uuid)', 'public.ai_check_documents(uuid)',
                               'public.attach_original_scan(uuid, text)', 'public.original_scans(uuid)']) f),
  'AI check functions: authenticated only');
select is(app.ai_check_codes('signed_form'),
  array['signature_present', 'amount_in_words', 'addenda_listed', 'form_version', 'resident_certificate'],
  'signed_form item codes');

-- ---------------------------------------------------------------------------
-- Fixtures: a closed solicitation with one paper-bond bid, an open one with a bid.
-- ---------------------------------------------------------------------------
insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000af1', 'AC Office', 'office'),
  ('00000000-0000-0000-0000-000000000aa1', 'AC Agency', 'agency');
select tests.make_user('ac.author@test.test', '00000000-0000-0000-0000-000000000aa1') as author \gset
select tests.make_user('ac.r1@test.test', '00000000-0000-0000-0000-000000000af1') as r1 \gset
select tests.make_user('ac.r2@test.test', '00000000-0000-0000-0000-000000000af1') as r2 \gset
select tests.make_bidder('ac.bidder@test.test', 'AC Builders LLC') as bidder \gset

select tests.make_published_solicitation('00000000-0000-0000-0000-000000000aa1', :'author',
  now() - interval '1 hour') as sol \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-000000000aa1', :'author',
  now() + interval '3 days') as open_sol \gset
select tests.make_closed_bid(:'sol', :'bidder', '{100000}', '{}', 'paper', null, true, true) as bid \gset
select tests.make_closed_bid(:'open_sol', :'bidder', '{100000}') as open_bid \gset
select id as entry from public.bid_original_log where bid_id = :'bid' and item = 'signed_form' \gset
select id as bond_entry from public.bid_original_log where bid_id = :'bid' and item = 'bid_bond' \gset
select id as open_entry from public.bid_original_log where bid_id = :'open_bid' and item = 'signed_form' \gset
select format('bids/%s/%s/scan-a.pdf', :'bid', :'entry') as scan_a,
       format('bids/%s/%s/scan-b.pdf', :'bid', :'entry') as scan_b,
       format('bids/%s/%s/scan-big.pdf', :'bid', :'entry') as scan_big,
       format('bids/%s/%s/scan-a.pdf', :'open_bid', :'open_entry') as scan_open \gset

-- ---------------------------------------------------------------------------
-- Who and when
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder');
select is(tests.ac_error(format('select public.start_ai_check(%L, %L)', :'bid', 'm')), 'not_authorized',
  'a bidder cannot start a check');
select tests.act_as(:'author');
select is(tests.ac_error(format('select public.bid_ai_check(%L)', :'bid')), 'not_authorized',
  'the agency cannot read check results');
select tests.act_as_anon();
select is(tests.ac_error(format('select public.bid_ai_check(%L)', :'bid')), 'permission denied for function bid_ai_check',
  'anon cannot read check results');
select tests.act_as(:'r1');
select is(tests.ac_error(format('select public.start_ai_check(%L, %L)', :'open_bid', 'm')), 'sealed',
  'no check before close');
select is(tests.ac_error(format('select public.ai_check_documents(%L)', :'open_bid')), 'sealed',
  'no document list before close');
select is(tests.ac_error(format($$insert into storage.objects (bucket_id, name) values ('bid-files', %L)$$, :'scan_open')),
  'new row violates row-level security policy for table "objects"', 'no scan upload before close');

-- ---------------------------------------------------------------------------
-- Scans
-- ---------------------------------------------------------------------------
select lives_ok(format($$insert into storage.objects (bucket_id, name, metadata) values ('bid-files', %L, '{"size": 2048}')$$,
  :'scan_a'), 'office uploads a scan after close');
select ok((select public.attach_original_scan(:'entry', :'scan_a')) is not null, 'office attaches the scan');
select ok(exists (select 1 from storage.objects where bucket_id = 'bid-files' and name = :'scan_a'),
  'office reads the attached scan');
reset role;
insert into storage.objects (bucket_id, name, metadata) values
  ('bid-files', :'scan_b', '{"size": 4096}'), ('bid-files', :'scan_big', '{"size": 20971521}');
select tests.act_as(:'r1');
select is(tests.ac_error(format('select public.attach_original_scan(%L, %L)', :'entry', :'scan_big')), 'scan_too_large',
  'a scan over 20 MB is refused');
select ok((select public.attach_original_scan(:'entry', :'scan_b')) is not null, 'a second scan is attached');
reset role;
select is((select count(*)::int from public.bid_original_scans where log_entry_id = :'entry' and superseded_by is null), 1,
  'the second scan supersedes the first');
select is((select path from public.bid_original_scans where log_entry_id = :'entry' and superseded_by is null),
  :'scan_b', 'the current scan is the newest');
-- A voided entry cannot take a scan.
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, voids_entry_id, reason, logged_by)
select solicitation_id, bid_id, reference, version, item, id, 'wrong bid', :'r2'
  from public.bid_original_log where id = :'bond_entry';
insert into storage.objects (bucket_id, name, metadata)
values ('bid-files', format('bids/%s/%s/scan-bond.pdf', :'bid', :'bond_entry'), '{"size": 10}');
select tests.act_as(:'r1');
select is(tests.ac_error(format('select public.attach_original_scan(%L, %L)', :'bond_entry',
  format('bids/%s/%s/scan-bond.pdf', :'bid', :'bond_entry'))), 'not_scannable', 'a voided entry takes no scan');

select is((select count(*)::int from public.original_scans(:'sol') where bid_id = :'bid' and path = :'scan_b'), 1,
  'original_scans lists the entry with its bid and current scan');
select is((select count(*)::int from public.original_scans(:'sol') where log_entry_id = :'bond_entry'), 0,
  'original_scans leaves out a voided entry');

-- An uploaded insurance certificate for the bid (a version file).
reset role;
select format('bids/%s/%s/insurance.pdf', :'bid', gen_random_uuid()) as ins \gset
with o as (insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'ins', '{"size": 10}') returning id)
insert into public.bid_version_files (version_id, slot, path, file_name, object_id, object_size, object_etag)
select v.id, 'insurance', :'ins', 'insurance.pdf', o.id, 10, '"x"' from public.bid_versions v, o where v.bid_id = :'bid';
select tests.act_as(:'r1');

-- ---------------------------------------------------------------------------
-- Documents
-- ---------------------------------------------------------------------------
select is((select path from public.ai_check_documents(:'bid') where document_kind = 'signed_form'), :'scan_b',
  'the document list carries the current signed-form scan');
select is((select count(*)::int from public.ai_check_documents(:'bid') where document_kind = 'bid_bond_scan' and path is null), 1,
  'a voided bond entry leaves the paper bond scan as not attached');

-- ---------------------------------------------------------------------------
-- Run lifecycle (Review Focus 3)
-- ---------------------------------------------------------------------------
select public.start_ai_check(:'bid', 'test-model') as run1 \gset
select is(tests.ac_error(format('select public.start_ai_check(%L, %L)', :'bid', 'm')), 'ai_check_running',
  'a second start while running is refused');
-- A document must be reserved (begin) before the paid call, and only the run's own documents can be.
select tests.act_as(:'r2');
select is(tests.ac_error(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run1', 'signed_form', :'scan_b')),
  'invalid_state', 'only the starter begins a document');
select tests.act_as(:'r1');
select is(tests.ac_error(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run1', 'insurance',
  format('bids/%s/%s/insurance.pdf', :'open_bid', gen_random_uuid()))), 'invalid_data',
  'a path that is not one of the bid''s documents is refused before any call');
select is(tests.ac_error(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run1', 'insurance', :'scan_b')),
  'invalid_data', 'a real path under the wrong kind is refused');
select is(tests.ac_error(format('select public.record_ai_check_document(%L, %L)', :'run1',
  tests.ac_items('signed_form', :'scan_b'))), 'invalid_state', 'items for a file need a begun document');
select is((select bid_id from public.begin_ai_check_document(:'run1', 'signed_form', :'scan_b')), :'bid'::uuid,
  'begin returns the run''s own bid');
select lives_ok(format('select public.record_ai_check_document(%L, %L)', :'run1', tests.ac_items('signed_form', :'scan_b')),
  'the starter records a begun document''s items');
select is(tests.ac_error(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run1', 'signed_form', :'scan_b')),
  'invalid_state', 'a document already checked in this run is not checked again');
select lives_ok(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run1', 'insurance', :'ins'),
  'begin the insurance document');
select is(tests.ac_error(format('select public.record_ai_check_document(%L, %L)', :'run1',
  tests.ac_items('insurance', :'ins', 'signature_present'))), 'invalid_data', 'an item code of another kind is refused');
select lives_ok(format('select public.finish_ai_check(%L, %L)', :'run1', 'done'), 'the starter finishes the run');
select is(tests.ac_error(format('select public.record_ai_check_document(%L, %L)', :'run1',
  tests.ac_items('insurance', :'ins'))), 'invalid_state', 'a finished run takes no more items');
select is(tests.ac_error(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run1', 'insurance', :'ins')),
  'invalid_state', 'a finished run begins no more documents');

-- Stale running run
select public.start_ai_check(:'bid', 'test-model') as run2 \gset
reset role;
update public.ai_check_runs set started_at = now() - interval '11 minutes' where id = :'run2';
select tests.act_as(:'r1');
select ok((select public.start_ai_check(:'bid', 'test-model')) is not null, 'a run stale for 10 minutes no longer blocks');
reset role;
select is((select status from public.ai_check_runs where id = :'run2'), 'failed', 'the stale run is marked failed');

-- Caps (Review Focus 4): runs per bid = 3, the 4th is refused.
select tests.act_as(:'r1');
select is(tests.ac_error(format('select public.start_ai_check(%L, %L)', :'bid', 'm')), 'ai_check_running',
  'the third run is running');
reset role;
update public.ai_check_runs set status = 'done' where bid_id = :'bid' and status = 'running';
select tests.act_as(:'r1');
select is(tests.ac_error(format('select public.start_ai_check(%L, %L)', :'bid', 'm')), 'ai_cap_reached',
  'the fourth run on a bid is refused');
-- A recorded run doesn't count.
reset role;
insert into public.ai_check_runs (bid_id, started_by, started_at, status, model, bid_version, solicitation_version, recorded)
values (:'bid', null, clock_timestamp() + interval '1 second', 'done', 'recorded', 1, 1, true);
select tests.act_as(:'r1');
select is(((public.bid_ai_check(:'bid')) ->> 'runsUsed')::int, 3, 'recorded runs are not counted');
select is(((public.bid_ai_check(:'bid')) -> 'run' ->> 'recorded')::boolean, true, 'the latest run is the recorded one');

-- A failed call can be retried in the same run; every begin with a file counts as a call (run1 made 2 today).
reset role;
update public.settings set ai_runs_per_bid = 10, ai_calls_per_user_day = 4 where id = 1;
select tests.act_as(:'r1');
select public.start_ai_check(:'bid', 'm') as run4 \gset
select lives_ok(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run4', 'insurance', :'ins'),
  'third call today');
select lives_ok(format('select public.record_ai_check_document(%L, %L)', :'run4',
  (select jsonb_agg(x || '{"result": "unclear", "call_failed": true}'::jsonb)
     from jsonb_array_elements(tests.ac_items('insurance', :'ins')) x)),
  'a failed call is recorded');
select lives_ok(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run4', 'insurance', :'ins'),
  'a failed document can be begun again (fourth call today)');
select lives_ok(format('select public.record_ai_check_document(%L, %L)', :'run4', tests.ac_items('insurance', :'ins')),
  'the retry is recorded');
select is(tests.ac_error(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run4', 'signed_form', :'scan_b')),
  'ai_cap_reached', 'the fifth call today is refused before the call');
select lives_ok(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run4', 'bid_bond_scan', null),
  'a document with no file needs no call');
select lives_ok(format('select public.record_ai_check_document(%L, %L)', :'run4', tests.ac_items('bid_bond_scan', null)),
  'and is recorded at no cost');
-- The total daily cap.
reset role;
update public.settings set ai_calls_per_user_day = 100, ai_calls_per_day = 4 where id = 1;
select tests.act_as(:'r1');
select is(tests.ac_error(format('select * from public.begin_ai_check_document(%L, %L, %L)', :'run4', 'signed_form', :'scan_b')),
  'ai_cap_reached', 'the total daily cap is enforced too');

-- ---------------------------------------------------------------------------
-- Reviews
-- ---------------------------------------------------------------------------
reset role;
select id as item from public.ai_check_items where run_id = :'run4' and item_code = 'insured_name' and not call_failed \gset
select tests.act_as(:'r1');
select is(tests.ac_error(format('select public.review_ai_check_item(%L, %L, %L)', :'item', 'override', ' ')),
  'reason_required', 'an override needs a reason');
select lives_ok(format('select public.review_ai_check_item(%L, %L, %L)', :'item', 'confirm', null), 'confirm');
select lives_ok(format('select public.review_ai_check_item(%L, %L, %L)', :'item', 'override', 'Name differs'), 'override');
select lives_ok(format('select public.finish_ai_check(%L, %L)', :'run4', 'done'), 'finish run 4');
-- The latest run is now run 4 (started after the recorded one).
reset role;
update public.ai_check_runs set started_at = clock_timestamp() + interval '2 seconds' where id = :'run4';
select tests.act_as(:'r1');
select is((select count(*)::int from jsonb_array_elements((public.bid_ai_check(:'bid')) -> 'items') i
            where i ->> 'code' = 'insured_name'), 1, 'the panel shows only the latest result of a retried item');
select is((select i ->> 'review' from jsonb_array_elements((public.bid_ai_check(:'bid')) -> 'items') i
            where i ->> 'code' = 'insured_name')::jsonb ->> 'decision', 'override', 'the latest review shows');

-- ---------------------------------------------------------------------------
-- Append-only and advisory only
-- ---------------------------------------------------------------------------
reset role;
select throws_ok(format('update public.ai_check_items set result = %L where id = %L', 'not_met', :'item'), 'P0001', null,
  'items are append-only');
select throws_ok(format('delete from public.ai_check_reviews where item_id = %L', :'item'), 'P0001', null,
  'reviews are append-only');
select is((select count(*)::int from public.bid_outcomes where bid_id = :'bid'), 0, 'no check writes an outcome');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname in ('public', 'app')
                         and p.proname in ('start_ai_check', 'record_ai_check_document', 'begin_ai_check_document', 'finish_ai_check',
                                           'review_ai_check_item', 'attach_original_scan')
                         and (p.prosrc ilike '%bid_outcomes%' or p.prosrc ilike '%flagged_decisions%'
                              or p.prosrc ilike '%recaps%' or p.prosrc ilike '%awards%')),
  'no AI check writer touches outcomes, flags, recaps or awards');

select * from finish();
rollback;
