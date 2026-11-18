-- Bid lifecycle functions: start, replace, submit, withdraw, receipts and the office index (slice 2a, Task 4).
begin;

select plan(170);

select set_config('storage.allow_delete_query', 'true', true);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000af1', 'BL Office', 'office'),
  ('00000000-0000-0000-0000-000000000aa1', 'BL Agency', 'agency');

select tests.make_user('bl.author@test.test', '00000000-0000-0000-0000-000000000aa1') as author \gset
select tests.make_user('bl.office@test.test', '00000000-0000-0000-0000-000000000af1') as office_u \gset
select tests.make_bidder('bl.bidder.a@test.test', 'BL Bidder A') as bidder_a \gset
select tests.make_bidder('bl.bidder.b@test.test', 'BL Bidder B') as bidder_b \gset
-- Review Focus 1: one bidder per operation, each with its own bid on two solicitations.
select tests.make_bidder('bl.edge.submit@test.test', 'BL Edge Submit') as e_submit \gset
select tests.make_bidder('bl.edge.withdraw@test.test', 'BL Edge Withdraw') as e_withdraw \gset
select tests.make_bidder('bl.edge.replace@test.test', 'BL Edge Replace') as e_replace \gset
select tests.make_bidder('bl.edge.start@test.test', 'BL Edge Start') as e_start \gset
select p.org_id as org_b from public.profiles p where p.user_id = :'bidder_b' \gset

\set agency '00000000-0000-0000-0000-000000000aa1'
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol_before \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol_at \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol_unreleased \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day',
  '{"estimateCents": 14999999, "optionalSections": ["qualifications", "current_work"]}'::jsonb) as sol_small \gset
alter table public.solicitations disable trigger solicitations_published_frozen;
update public.solicitations set release_date = app.today() + 1 where id = :'sol_unreleased';
alter table public.solicitations enable trigger solicitations_published_frozen;
insert into public.solicitations (agency_id, created_by, data)
values (:'agency', :'author', tests.solicitation_data()) returning id as sol_draft \gset

-- Test-only helpers (rolled back with the transaction).
-- The error a statement raises, as 'sqlstate|message|detail', or 'ok'.
create function tests.t4_error(p_sql text)
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
-- Fill a draft as the calling bidder (RLS applies): prices, paper bond, insurance + references uploaded and attached.
create function tests.t4_fill(p_bid uuid, p_tag text)
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
grant execute on function tests.t4_error(text), tests.t4_fill(uuid, text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Function shape and grants
-- ---------------------------------------------------------------------------
select has_function('public', f, a, 'public.' || f || ' exists')
  from (values ('start_bid', array['uuid']), ('replace_bid', array['uuid']), ('submit_bid', array['uuid']),
               ('withdraw_bid', array['uuid']), ('my_bid_receipts', array['uuid']),
               ('office_bid_index', array['uuid'])) v(f, a);
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('start_bid','replace_bid','submit_bid','withdraw_bid','my_bid_receipts','office_bid_index')
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')),
  6, 'the six bid functions are security definer, empty search_path, execute for authenticated only');
select has_function('app', f, 'app.' || f || ' exists')
  from unnest(array['new_bid_reference','normalize_bid_reference','lock_bid','bonds_required',
                    'required_bid_slots','bid_draft_problems','require_bidding_open','require_bidder','bid_audit']) f;
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'app'::regnamespace
      and p.proname in ('new_bid_reference','normalize_bid_reference','lock_bid','bonds_required',
                        'required_bid_slots','bid_draft_problems','require_bidding_open','require_bidder','bid_audit')
      and (has_function_privilege('anon', p.oid, 'execute')
           or has_function_privilege('authenticated', p.oid, 'execute')
           or has_function_privilege('service_role', p.oid, 'execute'))),
  0, 'the bid lifecycle helpers execute for no API role');
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'app'::regnamespace
      and p.proname in ('new_bid_reference','normalize_bid_reference','lock_bid','bonds_required',
                        'required_bid_slots','bid_draft_problems','require_bidding_open','require_bidder','bid_audit')
      and p.prosecdef and p.proconfig @> array['search_path=""']),
  9, 'the bid lifecycle helpers are security definer with an empty search_path');
select has_column('public', 'bid_version_files', c, 'bid_version_files.' || c || ' exists')
  from unnest(array['object_id','object_size','object_etag']) c;

-- ---------------------------------------------------------------------------
-- Reference helpers
-- ---------------------------------------------------------------------------
select is(app.normalize_bid_reference(' k7qm 2xvo '), 'K7QM-2XV0', 'normalize_bid_reference uppercases, maps O to 0, adds the dash');
select is(app.normalize_bid_reference('k7qm-2xvl'), 'K7QM-2XV1', 'normalize_bid_reference maps L to 1');
select is(app.normalize_bid_reference('K7QM-2XV'), null, 'normalize_bid_reference rejects 7 characters');
select is(app.normalize_bid_reference('K7QM-2XVU'), null, 'normalize_bid_reference rejects U');
select is(app.normalize_bid_reference(null), null, 'normalize_bid_reference of null is null');
select matches(app.new_bid_reference(), '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$', 'new_bid_reference matches the reference check');
select isnt(app.new_bid_reference(), app.new_bid_reference(), 'new_bid_reference is random');

-- ---------------------------------------------------------------------------
-- Requirement helpers (snapshot-driven)
-- ---------------------------------------------------------------------------
select published_snapshot as snap from public.solicitations where id = :'sol' \gset
select published_snapshot as snap_small from public.solicitations where id = :'sol_small' \gset
select is(app.bonds_required(:'snap'), true, 'bonds are required at exactly $150,000.00');
select is(app.bonds_required(:'snap_small'), false, 'bonds are not required at $149,999.99');
select is(app.required_bid_slots(:'snap', 'paper'), array['insurance','references']::public.bid_upload_slot[],
  'paper bond: insurance then the optional sections');
select is(app.required_bid_slots(:'snap', 'electronic'), array['insurance','references','bid_bond']::public.bid_upload_slot[],
  'electronic bond adds bid_bond last');
select is(app.required_bid_slots(:'snap', null), array['insurance','references']::public.bid_upload_slot[],
  'no choice yet: no bid_bond slot');
select is(app.required_bid_slots(:'snap_small', 'electronic'),
  array['insurance','qualifications','current_work']::public.bid_upload_slot[],
  'optional sections keep snapshot order; no bid_bond when bonds are not required');

-- ---------------------------------------------------------------------------
-- start_bid
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_a');
select public.start_bid(:'sol') as bid_a \gset
select isnt(:'bid_a'::uuid, null::uuid, 'start_bid returns a bid id');
select matches((select reference from public.bids where id = :'bid_a'), '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$',
  'the new bid has a well-formed reference');
select is((select version from public.bid_drafts where bid_id = :'bid_a'), 1, 'start_bid creates draft version 1');
select is(public.start_bid(:'sol'), :'bid_a'::uuid, 'a second start_bid returns the same id');
select is((select count(*)::int from public.bids), 1, 'still one bid');
select reference as ref_a from public.bids where id = :'bid_a' \gset
select throws_ok(format('select public.start_bid(%L)', :'sol_unreleased'), 'P0001', 'not_open',
  'start_bid on an unreleased solicitation gives not_open');
select throws_ok(format('select public.start_bid(%L)', gen_random_uuid()), 'P0001', 'not_open',
  'start_bid on an unknown solicitation gives not_open');
select throws_ok(format('select public.start_bid(%L)', :'sol_draft'), 'P0001', 'not_open',
  'start_bid on an unpublished solicitation gives not_open');
select is(tests.t4_error(format('select public.start_bid(%L)', gen_random_uuid())),
          tests.t4_error(format('select public.start_bid(%L)', :'sol_draft')),
  'unknown and unpublished solicitation ids give the identical start_bid error');
select tests.act_as(:'author');
select throws_ok(format('select public.start_bid(%L)', :'sol'), 'P0001', 'not_authorized', 'an agency caller gets not_authorized');
select tests.act_as(:'office_u');
select throws_ok(format('select public.start_bid(%L)', :'sol'), 'P0001', 'not_authorized', 'an office caller gets not_authorized');

-- ---------------------------------------------------------------------------
-- Draft problems
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_a');
select is(tests.t4_error(format('select * from public.submit_bid(%L)', :'bid_a')),
  'P0001|invalid_bid|price_missing,upload_missing,bond_choice_missing',
  'submit_bid on an empty draft raises invalid_bid with the codes in the detail');
reset role;
select ok(app.bid_draft_problems(:'bid_a') @> array['price_missing','upload_missing'], 'an empty draft has price_missing and upload_missing');

select tests.act_as(:'bidder_a');
select tests.t4_fill(:'bid_a', 'a1');
reset role;
select is(app.bid_draft_problems(:'bid_a'), array[]::text[], 'a filled draft has no problems');
update public.bid_drafts set item_cents = '{1,2,3}' where bid_id = :'bid_a';
select is(app.bid_draft_problems(:'bid_a'), array['price_count'], 'three item prices give price_count');
update public.bid_drafts set item_cents = '{12500000,null}' where bid_id = :'bid_a';
select is(app.bid_draft_problems(:'bid_a'), array['price_missing'], 'a null item price gives price_missing');
update public.bid_drafts set item_cents = '{12500000,234567}', alternate_cents = '{}' where bid_id = :'bid_a';
select is(app.bid_draft_problems(:'bid_a'), array['price_missing'], 'an unentered alternate gives price_missing');
update public.bid_drafts set alternate_cents = '{1500000}', bid_bond_choice = null where bid_id = :'bid_a';
select is(app.bid_draft_problems(:'bid_a'), array['bond_choice_missing'], 'no bond choice at $150,000.00 gives bond_choice_missing');
update public.bid_drafts set bid_bond_choice = 'paper', item_cents = '[2:3]={12500000,234567}' where bid_id = :'bid_a';
select is(app.bid_draft_problems(:'bid_a'), array['price_count'], 'item prices not starting at index 1 give price_count');
update public.bid_drafts set item_cents = '{{12500000,234567}}' where bid_id = :'bid_a';
select is(app.bid_draft_problems(:'bid_a'), array['price_count'], 'a 2-D item price array gives price_count');
update public.bid_drafts set item_cents = '{12500000,234567}', alternate_cents = '[2:2]={1500000}' where bid_id = :'bid_a';
select is(app.bid_draft_problems(:'bid_a'), array['price_count'], 'alternate prices not starting at index 1 give price_count');
update public.bid_drafts set alternate_cents = '{{1500000}}' where bid_id = :'bid_a';
select is(app.bid_draft_problems(:'bid_a'), array['price_count'], 'a 2-D alternate price array gives price_count');
select tests.act_as(:'bidder_a');
update public.bid_drafts set alternate_cents = '{1500000}', item_cents = '[2:3]={12500000,234567}' where bid_id = :'bid_a';
select is(tests.t4_error(format('select * from public.submit_bid(%L)', :'bid_a')), 'P0001|invalid_bid|price_count',
  'submit_bid turns a bidder-written offset array into invalid_bid, not a raw error');
update public.bid_drafts set item_cents = '{{12500000,234567}}' where bid_id = :'bid_a';
select is(tests.t4_error(format('select * from public.submit_bid(%L)', :'bid_a')), 'P0001|invalid_bid|price_count',
  'submit_bid turns a bidder-written 2-D array into invalid_bid, not a raw error');
update public.bid_drafts set item_cents = '{12500000,234567}', bid_bond_choice = null where bid_id = :'bid_a';
reset role;

select tests.act_as(:'bidder_a');
update public.bid_drafts set bid_bond_choice = 'electronic' where bid_id = :'bid_a';
reset role;
select is(app.bid_draft_problems(:'bid_a'), array['upload_missing'], 'electronic without a bid_bond file gives upload_missing');
select tests.act_as(:'bidder_a');
update public.bid_drafts set bid_bond_choice = 'paper' where bid_id = :'bid_a';
insert into public.bid_draft_files (bid_id, slot, path, file_name)
values (:'bid_a', 'qualifications', 'bids/' || :'bid_a' || '/' || gen_random_uuid() || '/ghost.pdf', 'ghost.pdf');
reset role;
select is(app.bid_draft_problems(:'bid_a'), array['file_missing'], 'a draft row with no storage object gives file_missing');
select tests.act_as(:'bidder_a');
select is(tests.t4_error(format('select * from public.submit_bid(%L)', :'bid_a')), 'P0001|invalid_bid|file_missing',
  'submit_bid refuses a draft with a missing file');
delete from public.bid_draft_files where bid_id = :'bid_a' and slot = 'qualifications';
-- M3: an object without an eTag, or without a size, is file_missing (never seal null tamper evidence).
\set path_noetag 'bids/' :bid_a '/aaaaaaaa-0000-4000-8000-000000000001/noetag.pdf'
\set path_nosize 'bids/' :bid_a '/aaaaaaaa-0000-4000-8000-000000000002/nosize.pdf'
insert into storage.objects (bucket_id, name, metadata) values
  ('bid-files', :'path_noetag', '{"size": 10}'), ('bid-files', :'path_nosize', '{"eTag": "\"x\""}');
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_a', 'qualifications', :'path_noetag', 'noetag.pdf');
select is(tests.t4_error(format('select * from public.submit_bid(%L)', :'bid_a')), 'P0001|invalid_bid|file_missing',
  'an object with no eTag gives file_missing');
reset role;
select is(app.bid_draft_problems(:'bid_a'), array['file_missing'], 'bid_draft_problems flags an object with no eTag');
select tests.act_as(:'bidder_a');
delete from public.bid_draft_files where bid_id = :'bid_a' and slot = 'qualifications';
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_a', 'qualifications', :'path_nosize', 'nosize.pdf');
select is(tests.t4_error(format('select * from public.submit_bid(%L)', :'bid_a')), 'P0001|invalid_bid|file_missing',
  'an object with no size gives file_missing');
reset role;
select is(app.bid_draft_problems(:'bid_a'), array['file_missing'], 'bid_draft_problems flags an object with no size');
select tests.act_as(:'bidder_a');
delete from public.bid_draft_files where bid_id = :'bid_a' and slot = 'qualifications';

-- bond_not_required on a small solicitation (B's bid)
select tests.act_as(:'bidder_b');
select public.start_bid(:'sol_small') as bid_b_small \gset
update public.bid_drafts set item_cents = '{1,2}', alternate_cents = '{3}', bid_bond_choice = 'paper' where bid_id = :'bid_b_small';
reset role;
select ok(app.bid_draft_problems(:'bid_b_small') @> array['bond_not_required'], 'a bond choice when bonds are not required gives bond_not_required');

-- ---------------------------------------------------------------------------
-- I1: an object deleted between validation and the copy is refused, never sealed as an incomplete bid.
-- Simulated with a test-only trigger that deletes the references object when the bid_versions row is inserted,
-- i.e. after bid_draft_problems has passed and before the file copy.
-- ---------------------------------------------------------------------------
reset role;
create function tests.t4_drop_ref_object() returns trigger language plpgsql as $fn$
begin
  delete from storage.objects o using public.bid_draft_files f
   where f.bid_id = new.bid_id and f.slot = 'references' and o.bucket_id = 'bid-files' and o.name = f.path;
  return new;
end;
$fn$;
create trigger t4_drop_ref_object after insert on public.bid_versions
  for each row execute function tests.t4_drop_ref_object();
select is(app.bid_draft_problems(:'bid_a'), array[]::text[], 'the draft is valid before the simulated race');
select tests.act_as(:'bidder_a');
select is(tests.t4_error(format('select * from public.submit_bid(%L)', :'bid_a')), 'P0001|invalid_bid|file_missing',
  'an object gone at copy time raises invalid_bid file_missing');
select is((select count(*)::int from public.bid_drafts where bid_id = :'bid_a'), 1, 'the refused submit leaves the draft');
reset role;
drop trigger t4_drop_ref_object on public.bid_versions;
select is((select count(*)::int from public.bid_versions where bid_id = :'bid_a'), 0, 'the refused submit sealed nothing');
select is(app.bid_draft_problems(:'bid_a'), array[]::text[], 'the deletion rolled back with the refused submit');

-- ---------------------------------------------------------------------------
-- submit_bid v1
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_a');
select results_eq(format('select reference, version, submitted_at from public.submit_bid(%L)', :'bid_a'),
  format('values (%L::text, 1, now())', :'ref_a'),
  'submit_bid returns the reference, version 1 and submitted_at = now()');
-- Draft emptied on submit (carried from the Task 3 review)
select is((select count(*)::int from public.bid_drafts where bid_id = :'bid_a'), 0, 'the draft is gone after submit');
select is((select count(*)::int from public.bid_draft_files where bid_id = :'bid_a'), 0, 'no draft file rows remain after submit');
select throws_ok('select item_cents from public.bid_versions', '42501', null, 'the bidder cannot read back submitted prices');
select throws_ok('select path from public.bid_version_files', '42501', null, 'the bidder cannot read back submitted file paths');
select is((select count(*)::int from storage.objects where bucket_id = 'bid-files' and name like 'bids/' || :'bid_a' || '/%'), 0,
  'the bidder cannot read its submitted storage objects');
select is((select count(*)::int from public.bid_audit_log), 0, 'the bidder reads no audit rows');
select throws_ok(format('select * from public.submit_bid(%L)', :'bid_a'), 'P0001', 'invalid_state', 'a second submit_bid raises invalid_state');
select throws_ok(format('select public.start_bid(%L)', :'sol'), 'P0001', 'invalid_state',
  'start_bid with versions and no draft raises invalid_state');
reset role;
select is((select count(*)::int from public.bid_versions where bid_id = :'bid_a'), 1, 'one bid_versions row');
select is((select row(item_cents, alternate_cents, bid_bond_choice, submitted_by)::text from public.bid_versions where bid_id = :'bid_a'),
  row('{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper'::public.bid_bond_choice, :'bidder_a'::uuid)::text,
  'the sealed version holds the draft prices, bond choice and submitter');
select is((select array_agg(vf.slot::text order by vf.slot) from public.bid_version_files vf
             join public.bid_versions v on v.id = vf.version_id where v.bid_id = :'bid_a'),
  array['insurance','references'], 'the sealed version holds the draft files');
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_a' and action = 'submit_bid'), 1, 'one submit_bid audit row');
select is((select detail from public.bid_audit_log where bid_id = :'bid_a' and action = 'submit_bid'),
  jsonb_build_object('reference', :'ref_a', 'version', 1, 'supersedes', null), 'submit audit detail: reference, version, supersedes');
select is((select count(*)::int from public.bid_audit_log a, jsonb_object_keys(a.detail) k
            where a.bid_id = :'bid_a' and k like '%cents%'), 0, 'no audit detail key contains cents');
select is((select actor_id from public.bid_audit_log where bid_id = :'bid_a' and action = 'submit_bid'), :'bidder_a'::uuid,
  'the audit row names the bidder');

-- Ruling 5: tamper evidence recorded at submit
select ok(has_table_privilege('postgres', 'storage.objects', 'select'), 'postgres (the function owner) can read storage.objects');
select is(
  (select row(vf.object_id, vf.object_size, vf.object_etag)::text
     from public.bid_version_files vf join public.bid_versions v on v.id = vf.version_id
    where v.bid_id = :'bid_a' and vf.slot = 'insurance'),
  (select row(o.id, 2048::bigint, '"a1-ins"'::text)::text from storage.objects o
    where o.bucket_id = 'bid-files' and o.name = (select vf.path from public.bid_version_files vf
      join public.bid_versions v on v.id = vf.version_id where v.bid_id = :'bid_a' and vf.slot = 'insurance')),
  'submit records the insurance object''s id, size and eTag');
select is(
  (select count(*)::int from public.bid_version_files vf
     join public.bid_versions v on v.id = vf.version_id
     join storage.objects o on o.bucket_id = 'bid-files' and o.name = vf.path
    where v.bid_id = :'bid_a' and vf.object_id = o.id
      and vf.object_size = (o.metadata->>'size')::bigint and vf.object_etag = o.metadata->>'eTag'),
  2, 'every submitted file matches its storage object');

-- ---------------------------------------------------------------------------
-- replace_bid, v2
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_a');
select lives_ok(format('select public.replace_bid(%L)', :'bid_a'), 'replace_bid succeeds after a submit');
select is((select row(version, item_cents, alternate_cents, bid_bond_choice)::text from public.bid_drafts where bid_id = :'bid_a'),
  '(2,{},{},)', 'replace_bid starts an empty draft version 2');
select is((select count(*)::int from public.bid_draft_files where bid_id = :'bid_a'), 0, 'the replacement draft has no files');
select throws_ok(format('select public.replace_bid(%L)', :'bid_a'), 'P0001', 'invalid_state', 'a second replace_bid raises invalid_state');
select is(public.start_bid(:'sol'), :'bid_a'::uuid, 'start_bid is idempotent while the replacement draft exists');
select tests.t4_fill(:'bid_a', 'a2');
select results_eq(format('select version from public.submit_bid(%L)', :'bid_a'), 'values (2)', 'the replacement submits as version 2');
select results_eq(format('select version, is_current, withdrawn_at from public.my_bid_receipts(%L) order by version', :'bid_a'),
  $$values (1, false, null::timestamptz), (2, true, null::timestamptz)$$, 'receipts: v1 superseded, v2 current');
select results_eq(format('select distinct reference from public.my_bid_receipts(%L)', :'bid_a'),
  format('values (%L::text)', :'ref_a'), 'receipts carry the bid reference');
reset role;
select is((select detail from public.bid_audit_log where bid_id = :'bid_a' and action = 'replace_bid'),
  '{"from_version": 1, "draft_version": 2}'::jsonb, 'replace audit detail');
select is((select detail from public.bid_audit_log where bid_id = :'bid_a' and action = 'submit_bid' and (detail->>'version')::int = 2),
  jsonb_build_object('reference', :'ref_a', 'version', 2, 'supersedes', 1), 'v2 submit audit names the superseded version');

-- ---------------------------------------------------------------------------
-- withdraw_bid, then v3
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_a');
select lives_ok(format('select public.withdraw_bid(%L)', :'bid_a'), 'withdraw_bid succeeds');
select results_eq(format('select withdrawn_at, is_current from public.my_bid_receipts(%L) where version = 2', :'bid_a'),
  'values (now(), false)', 'v2 shows withdrawn_at and is no longer current');
select throws_ok(format('select public.withdraw_bid(%L)', :'bid_a'), 'P0001', 'invalid_state', 'a second withdraw raises invalid_state');
reset role;
select is((select detail from public.bid_audit_log where bid_id = :'bid_a' and action = 'withdraw_bid'),
  '{"version": 2}'::jsonb, 'withdraw audit detail');
select tests.act_as(:'office_u');
select results_eq(format('select reference, version, status from public.office_bid_index(%L) order by version', :'sol'),
  format('values (%L::text, 1, %L::text), (%L, 2, %L)', :'ref_a', 'superseded', :'ref_a', 'withdrawn'),
  'office index: v1 superseded, v2 withdrawn');
select tests.act_as(:'bidder_a');
select lives_ok(format('select public.replace_bid(%L)', :'bid_a'), 'replace_bid after a withdrawal');
select is((select version from public.bid_drafts where bid_id = :'bid_a'), 3, 'the new draft is version 3');
select tests.t4_fill(:'bid_a', 'a3');
select results_eq(format('select version from public.submit_bid(%L)', :'bid_a'), 'values (3)', 'v3 submits');
select results_eq(format('select version, is_current from public.my_bid_receipts(%L) order by version', :'bid_a'),
  $$values (1, false), (2, false), (3, true)$$, 'receipts: v3 is current');
select tests.act_as(:'office_u');
select results_eq(format('select version, status from public.office_bid_index(%L) order by version', :'sol'),
  $$values (1, 'superseded'::text), (2, 'withdrawn'), (3, 'current')$$, 'office index: v3 current');
-- A draft left in place by a withdrawal is still submittable.
select tests.act_as(:'bidder_a');
select lives_ok(format('select public.replace_bid(%L)', :'bid_a'), 'replace starts draft v4');
select lives_ok(format('select public.withdraw_bid(%L)', :'bid_a'), 'withdraw v3 while drafting v4');
select is((select version from public.bid_drafts where bid_id = :'bid_a'), 4, 'withdraw leaves the draft in place');
reset role;
select is((select count(*)::int from public.bid_audit_log where bid_id = :'bid_a'), 8,
  'audit rows: 3 submits, 3 replaces, 2 withdrawals; none for start_bid');

-- ---------------------------------------------------------------------------
-- Review Focus 5: another bidder probing A's bid
-- ---------------------------------------------------------------------------
select tests.act_as(:'bidder_b');
select throws_ok(format('select * from public.my_bid_receipts(%L)', :'bid_a'), 'P0001', 'not_found', 'B reading A''s receipts gets not_found');
select throws_ok(format('select * from public.submit_bid(%L)', :'bid_a'), 'P0001', 'not_found', 'B submitting A''s bid gets not_found');
select throws_ok(format('select public.replace_bid(%L)', :'bid_a'), 'P0001', 'not_found', 'B replacing A''s bid gets not_found');
select throws_ok(format('select public.withdraw_bid(%L)', :'bid_a'), 'P0001', 'not_found', 'B withdrawing A''s bid gets not_found');
select is(tests.t4_error(format('select * from public.my_bid_receipts(%L)', :'bid_a')),
          tests.t4_error(format('select * from public.my_bid_receipts(%L)', gen_random_uuid())),
  'A''s bid id and an unknown id give B the identical receipts error');
select is(tests.t4_error(format('select * from public.submit_bid(%L)', :'bid_a')),
          tests.t4_error(format('select * from public.submit_bid(%L)', gen_random_uuid())),
  'A''s bid id and an unknown id give B the identical submit error');
select is((select count(*)::int from public.bids where id = :'bid_a'), 0, 'B selecting A''s bids row gets 0 rows');
select throws_ok('select 1 from public.bid_versions', '42501', null, 'B selecting bid_versions raises 42501');
select results_eq(format('select count(*)::int from public.my_bid_receipts(%L)', :'bid_b_small'), 'values (0)',
  'B reads its own (empty) receipts');
select throws_ok(format('select * from public.office_bid_index(%L)', :'sol'), 'P0001', 'not_authorized',
  'a bidder calling office_bid_index gets not_authorized');
select tests.act_as(:'office_u');
select throws_ok(format('select * from public.my_bid_receipts(%L)', :'bid_a'), 'P0001', 'not_authorized',
  'the office calling my_bid_receipts gets not_authorized');
select throws_ok(format('select public.withdraw_bid(%L)', :'bid_a'), 'P0001', 'not_authorized',
  'the office calling withdraw_bid gets not_authorized');
select tests.act_as(:'author');
select throws_ok(format('select * from public.office_bid_index(%L)', :'sol'), 'P0001', 'not_authorized',
  'the agency author calling office_bid_index gets not_authorized');
select throws_ok(format('select * from public.my_bid_receipts(%L)', :'bid_a'), 'P0001', 'not_authorized',
  'the agency author calling my_bid_receipts gets not_authorized');

-- anon and service_role: no execute on any of the six
select tests.act_as_anon();
select throws_ok(format(s, :'bid_a'), '42501', null, 'anon: ' || s)
  from unnest(array['select public.start_bid(%L)', 'select public.replace_bid(%L)', 'select * from public.submit_bid(%L)',
                    'select public.withdraw_bid(%L)', 'select * from public.my_bid_receipts(%L)',
                    'select * from public.office_bid_index(%L)']) s;
select tests.act_as_service_role();
select throws_ok(format(s, :'bid_a'), '42501', null, 'service_role: ' || s)
  from unnest(array['select public.start_bid(%L)', 'select public.replace_bid(%L)', 'select * from public.submit_bid(%L)',
                    'select public.withdraw_bid(%L)', 'select * from public.my_bid_receipts(%L)',
                    'select * from public.office_bid_index(%L)']) s;
reset role;

-- ---------------------------------------------------------------------------
-- Review Focus 1: exactly at bid_due_at, and one second before.
-- Each operation runs on its own fixture bid, set up while open, on sol_before and on sol_at.
-- ---------------------------------------------------------------------------
-- e_submit: a filled draft. e_withdraw: a submitted v1. e_replace: a submitted v1, no draft. e_start: no bid.
select tests.act_as(:'e_submit');
select public.start_bid(:'sol_before') as eb_submit \gset
select public.start_bid(:'sol_at') as ea_submit \gset
select tests.t4_fill(:'eb_submit', 'eb-s');
select tests.t4_fill(:'ea_submit', 'ea-s');
select tests.act_as(:'e_withdraw');
select public.start_bid(:'sol_before') as eb_withdraw \gset
select public.start_bid(:'sol_at') as ea_withdraw \gset
select tests.t4_fill(:'eb_withdraw', 'eb-w');
select tests.t4_fill(:'ea_withdraw', 'ea-w');
select version from public.submit_bid(:'eb_withdraw') \gset
select version from public.submit_bid(:'ea_withdraw') \gset
select tests.act_as(:'e_replace');
select public.start_bid(:'sol_before') as eb_replace \gset
select public.start_bid(:'sol_at') as ea_replace \gset
select tests.t4_fill(:'eb_replace', 'eb-r');
select tests.t4_fill(:'ea_replace', 'ea-r');
select version from public.submit_bid(:'eb_replace') \gset
select version from public.submit_bid(:'ea_replace') \gset
reset role;

-- Guard for the boundary below: the bid writers also refuse once clock_timestamp() >= bid_due_at (Ruling 8), so
-- "now() + 1 second" is still open only while this transaction is younger than one second. If this fails, the
-- run was slow, not the rule.
select ok(clock_timestamp() - now() < interval '1 second', 'this transaction is under one second old at the boundary');
select tests.set_bid_due(:'sol_before', now() + interval '1 second');
select tests.set_bid_due(:'sol_at', now());
select is(app.bids_closed(:'sol_before'), false, 'one second before the due time is open');
select is(app.bids_closed(:'sol_at'), true, 'exactly the due time is closed');

select tests.act_as(:'e_submit');
select lives_ok(format('select * from public.submit_bid(%L)', :'eb_submit'), 'submit_bid one second before the due time succeeds');
select throws_ok(format('select * from public.submit_bid(%L)', :'ea_submit'), 'P0001', 'bids_closed',
  'submit_bid at exactly the due time raises bids_closed');
select tests.act_as(:'e_withdraw');
select lives_ok(format('select public.withdraw_bid(%L)', :'eb_withdraw'), 'withdraw_bid one second before the due time succeeds');
select throws_ok(format('select public.withdraw_bid(%L)', :'ea_withdraw'), 'P0001', 'bids_closed',
  'withdraw_bid at exactly the due time raises bids_closed');
select tests.act_as(:'e_replace');
select lives_ok(format('select public.replace_bid(%L)', :'eb_replace'), 'replace_bid one second before the due time succeeds');
select throws_ok(format('select public.replace_bid(%L)', :'ea_replace'), 'P0001', 'bids_closed',
  'replace_bid at exactly the due time raises bids_closed');
select tests.act_as(:'e_start');
select lives_ok(format('select public.start_bid(%L)', :'sol_before'), 'start_bid one second before the due time succeeds');
select throws_ok(format('select public.start_bid(%L)', :'sol_at'), 'P0001', 'bids_closed',
  'start_bid at exactly the due time raises bids_closed');
reset role;
select is((select count(*)::int from public.bids where solicitation_id = :'sol_at'), 3,
  'the refused start_bid created no bid');
select is((select count(*)::int from public.bid_audit_log where solicitation_id = :'sol_at'), 2,
  'the refused calls wrote no audit rows (only the two earlier submits)');
select is((select count(*)::int from public.bid_versions v join public.bids b on b.id = v.bid_id where b.solicitation_id = :'sol_at'), 2,
  'the refused submit wrote no version');

-- ---------------------------------------------------------------------------
-- Ruling 8: the second deadline check on the database clock, after the bid lock.
-- Fixture: one bid per operation on sol_clock, then bid_due_at = clock_timestamp() + 50 ms and a 100 ms sleep. The
-- transaction-start now() is still before the due time (app.bids_closed is false, so the old check alone would
-- allow the write), but clock_timestamp() is past it. This stands in for a transaction that began before the due
-- time and reached the bid lock after it (for example, after waiting on the opener's FOR SHARE).
-- ---------------------------------------------------------------------------
select has_function('app', 'require_before_due_clock', array['uuid'], 'app.require_before_due_clock exists');
select is(
  (select count(*)::int from pg_proc p
    where p.oid = 'app.require_before_due_clock(uuid)'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""'] and p.provolatile = 'v'
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')
      and not has_function_privilege('service_role', p.oid, 'execute')),
  1, 'app.require_before_due_clock: definer, empty search_path, volatile, executable by no API role');
select ok(
  (select bool_and(p.prosrc ~ 'app\.lock_bid\([^)]*\);\s*perform app\.require_before_due_clock\(v_bid\.solicitation_id\);')
     from pg_proc p
    where p.oid in ('public.start_bid(uuid)'::regprocedure, 'public.replace_bid(uuid)'::regprocedure,
                    'public.submit_bid(uuid)'::regprocedure, 'public.withdraw_bid(uuid)'::regprocedure)),
  'start, replace, submit and withdraw re-check the clock directly after app.lock_bid');

select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day') as sol_clock \gset
select tests.act_as(:'e_submit');
select public.start_bid(:'sol_clock') as ec_submit \gset
select tests.t4_fill(:'ec_submit', 'ec-s');
select tests.act_as(:'e_withdraw');
select public.start_bid(:'sol_clock') as ec_withdraw \gset
select tests.t4_fill(:'ec_withdraw', 'ec-w');
select version from public.submit_bid(:'ec_withdraw') \gset
select tests.act_as(:'e_replace');
select public.start_bid(:'sol_clock') as ec_replace \gset
select tests.t4_fill(:'ec_replace', 'ec-r');
select version from public.submit_bid(:'ec_replace') \gset
reset role;
select is((select count(*)::int from public.bid_audit_log where solicitation_id = :'sol_clock'), 2,
  'clock fixture: two submits audited');

select tests.set_bid_due(:'sol_clock', clock_timestamp() + interval '50 milliseconds');
select pg_sleep(0.1);
select ok(now() < (select bid_due_at from public.solicitations where id = :'sol_clock')
          and clock_timestamp() >= (select bid_due_at from public.solicitations where id = :'sol_clock'),
  'clock fixture: now() is before the due time, clock_timestamp() is past it');
select is(app.bids_closed(:'sol_clock'), false, 'clock fixture: by now() alone the solicitation is still open');
select throws_ok(format('select app.require_before_due_clock(%L)', :'sol_clock'), 'P0001', 'bids_closed',
  'the helper raises bids_closed once clock_timestamp() is past the due time');

select tests.act_as(:'e_submit');
select throws_ok(format('select * from public.submit_bid(%L)', :'ec_submit'), 'P0001', 'bids_closed',
  'submit_bid: on time by now() but late by clock_timestamp() raises bids_closed');
select tests.act_as(:'e_withdraw');
select throws_ok(format('select public.withdraw_bid(%L)', :'ec_withdraw'), 'P0001', 'bids_closed',
  'withdraw_bid: on time by now() but late by clock_timestamp() raises bids_closed');
select tests.act_as(:'e_replace');
select throws_ok(format('select public.replace_bid(%L)', :'ec_replace'), 'P0001', 'bids_closed',
  'replace_bid: on time by now() but late by clock_timestamp() raises bids_closed');
select tests.act_as(:'e_start');
select throws_ok(format('select public.start_bid(%L)', :'sol_clock'), 'P0001', 'bids_closed',
  'start_bid: on time by now() but late by clock_timestamp() raises bids_closed');
reset role;
select is((select count(*)::int from public.bid_audit_log where solicitation_id = :'sol_clock'), 2,
  'the refused clock-late calls wrote no audit rows');
select is((select count(*)::int from public.bid_withdrawals w join public.bids b on b.id = w.bid_id
            where b.solicitation_id = :'sol_clock'), 0, 'the clock-late withdraw wrote no withdrawal');
select is((select count(*)::int from public.bids where solicitation_id = :'sol_clock'), 3,
  'the clock-late start_bid created no bid');

-- Receipts stay readable after close; the office index works after close.
select tests.act_as(:'e_withdraw');
select results_eq(format('select version, is_current from public.my_bid_receipts(%L)', :'ea_withdraw'), 'values (1, true)',
  'receipts are readable after close');
select tests.act_as(:'office_u');
select results_eq(format('select count(*)::int from public.office_bid_index(%L)', :'sol_at'), 'values (2)',
  'office index after close lists the two submitted versions');
reset role;

select * from finish();
rollback;
