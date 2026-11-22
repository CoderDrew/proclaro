-- 0029: app.schedule_changed (parity with src/domain/addendum/diff.test.ts), app.local_deadline,
-- app.addendum_too_close, public.publish_addendum, and the replaced storage checks app.can_write_published_file
-- (v{n} uploads for an approved addendum) and app.can_access_attachment (agency uploads while an addendum is a draft).
begin;

select plan(89);

-- Direct deletes from storage.objects (the test stand-in for the Storage API delete; RLS still applies).
select set_config('storage.allow_delete_query', 'true', true);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000002a1', 'AP Office', 'office'),
  ('00000000-0000-0000-0000-0000000002a2', 'AP Agency', 'agency');

select tests.make_user('ap.author@test.test', '00000000-0000-0000-0000-0000000002a2') as author \gset
select tests.make_user('ap.r1@test.test',     '00000000-0000-0000-0000-0000000002a1') as r1 \gset
select tests.make_user('ap.r2@test.test',     '00000000-0000-0000-0000-0000000002a1') as r2 \gset
select tests.make_user('ap.r3@test.test',     '00000000-0000-0000-0000-0000000002a1') as r3 \gset

-- ===========================================================================
-- Schema objects and grants
-- ===========================================================================
select has_function('app', 'schedule_changed', array['jsonb', 'jsonb'], 'app.schedule_changed exists');
select has_function('app', 'local_deadline', array['jsonb'], 'app.local_deadline exists');
select has_function('app', 'path_version', array['text'], 'app.path_version exists');
select has_function('app', 'addendum_too_close', array['timestamp with time zone', 'timestamp with time zone'],
  'app.addendum_too_close exists');
select has_function('public', 'publish_addendum',
  array['uuid', 'text', 'text', 'text', 'jsonb', 'timestamp with time zone', 'bigint'], 'publish_addendum exists');
select ok(not has_function_privilege('authenticated', 'app.schedule_changed(jsonb, jsonb)', 'execute'),
  'app.schedule_changed is not callable through the API');
select ok(not has_function_privilege('authenticated', 'app.local_deadline(jsonb)', 'execute'),
  'app.local_deadline is not callable through the API');
select ok(not has_function_privilege('authenticated', 'app.addendum_too_close(timestamptz, timestamptz)', 'execute'),
  'app.addendum_too_close is not callable through the API');
select ok(has_function_privilege('authenticated',
  'public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)', 'execute'),
  'authenticated can execute publish_addendum');
select ok(not has_function_privilege('anon',
  'public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)', 'execute'),
  'anon cannot execute publish_addendum');

-- ===========================================================================
-- app.schedule_changed: the six parity cases (same base and changes as diff.test.ts)
-- ===========================================================================
\set base '{"schedule": {"items": [{"name": "Base bid", "description": "Site work"}, {"name": "Item 2", "description": "Roofing"}], "alternates": [{"kind": "deductive", "description": "Omit canopy"}]}}'

select is(app.schedule_changed(:'base'::jsonb, :'base'::jsonb), false, 'parity: identical -> false');
select is(app.schedule_changed(:'base'::jsonb,
  '{"schedule": {"items": [{"name": "Base bid", "description": "Site work"}, {"name": "Item 2", "description": "Roofing"}, {"name": "Item 3", "description": "Paving"}], "alternates": [{"kind": "deductive", "description": "Omit canopy"}]}}'),
  true, 'parity: item added at end -> true');
select is(app.schedule_changed(:'base'::jsonb,
  '{"schedule": {"items": [{"name": "Base bid", "description": "Site work"}], "alternates": [{"kind": "deductive", "description": "Omit canopy"}]}}'),
  true, 'parity: item removed -> true');
select is(app.schedule_changed(:'base'::jsonb,
  '{"schedule": {"items": [{"name": "Base bid", "description": "Site work"}, {"name": "Roof replacement", "description": "Roofing"}], "alternates": [{"kind": "deductive", "description": "Omit canopy"}]}}'),
  true, 'parity: item renamed -> true');
select is(app.schedule_changed(:'base'::jsonb,
  '{"schedule": {"items": [{"name": "Base bid", "description": "Site work"}, {"name": "Item 2", "description": "Roofing"}], "alternates": [{"kind": "additive", "description": "Omit canopy"}]}}'),
  true, 'parity: alternate kind flipped -> true');
select is(app.schedule_changed(:'base'::jsonb,
  '{"schedule": {"items": [{"name": "Item 2", "description": "Roofing"}, {"name": "Base bid", "description": "Site work"}], "alternates": [{"kind": "deductive", "description": "Omit canopy"}]}}'),
  true, 'parity: two items swapped -> true');

-- Only {name, description} / {kind, description} count; key order and other data keys don't.
select is(app.schedule_changed(:'base'::jsonb || '{"shortTitle": "Old"}',
  '{"shortTitle": "New", "schedule": {"alternates": [{"description": "Omit canopy", "kind": "deductive"}], "items": [{"description": "Site work", "name": "Base bid", "note": "x"}, {"name": "Item 2", "description": "Roofing"}]}}'),
  false, 'other data keys, key order and extra element keys do not count');
select is(app.schedule_changed('{}', '{"schedule": {"items": [], "alternates": []}}'), false,
  'a missing schedule equals an empty one');

-- ===========================================================================
-- app.local_deadline and app.addendum_too_close (the exact 5-day edge)
-- ===========================================================================
select is(app.local_deadline('{"date": "2026-12-01", "time": "13:00"}'),
  ('2026-12-01 13:00'::timestamp at time zone (select timezone from public.settings where id = 1)),
  'local_deadline reads {date, time} in settings.timezone');
select is(app.local_deadline('{"date": "2026-12-01", "time": "25:00"}'), null::timestamptz,
  'local_deadline returns null for a bad time');
select is(app.local_deadline(null), null::timestamptz, 'local_deadline returns null for null');
select is(app.path_version('solicitations/00000000-0000-0000-0000-000000000001/v12/rfb.pdf'), 12,
  'path_version reads the v{n} folder');
select is(app.path_version('solicitations/00000000-0000-0000-0000-000000000001/v0/rfb.pdf'), null::int,
  'path_version is null for a name without a valid version folder');

select is(app.addendum_too_close(timestamptz '2026-12-06 13:00:00+00', timestamptz '2026-12-01 13:00:00+00'), false,
  'a due time of exactly now + 5 days is allowed');
select is(app.addendum_too_close(timestamptz '2026-12-06 12:59:59+00', timestamptz '2026-12-01 13:00:00+00'), true,
  'one second less is too close');

-- ===========================================================================
-- Fixtures. Each solicitation gets its version-1 row (make_published_solicitation writes none).
--   sa: happy path; addendum 1 approved (r1 reviewer, r2 checker) moves the due date, adds an item, raises funding.
--   sb: refusals, then a publish just over 5 days out with the schedule unchanged and answersDue already past.
--   sc: open by now() but past due on the wall clock (bids_closed).
--   sd: an addendum still in draft.
-- ===========================================================================
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000002a2', :'author',
  now() + interval '20 days') as sa \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000002a2', :'author',
  now() + interval '20 days',
  jsonb_build_object('answersDue', jsonb_build_object('date', to_char(app.today() - 1, 'YYYY-MM-DD'),
                                                      'time', '13:00'))) as sb \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000002a2', :'author',
  now() + interval '20 days') as sc \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000002a2', :'author',
  now() + interval '20 days') as sd \gset

insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path, bid_due_at)
select s.id, 1, s.published_snapshot, format('solicitations/%s/v1/rfb.pdf', s.id),
       format('solicitations/%s/v1/bid-form.pdf', s.id), s.bid_due_at
  from public.solicitations s where s.id in (:'sa', :'sb', :'sc', :'sd');

insert into public.addenda (solicitation_id, number, state, data, narrative, created_by, reviewer_id, checker_id)
select s.id, 1, 'approved',
       s.data || jsonb_build_object(
         'fundingAmountCents', 16000000,
         'bidDueDate', to_char(app.today() + 30, 'YYYY-MM-DD'),
         'schedule', jsonb_set(s.data -> 'schedule', '{items}',
                               (s.data -> 'schedule' -> 'items')
                               || '[{"name": "Item 3", "description": "Paving"}]'::jsonb)),
       'Adds paving and moves the due date.', :'author', :'r1', :'r2'
  from public.solicitations s where s.id = :'sa'
returning id as aa \gset

insert into public.addenda (solicitation_id, number, state, data, narrative, created_by, reviewer_id, checker_id)
select s.id, 1, 'approved', s.data || '{"fundingAmountCents": 15000000}'::jsonb, 'Clarifies.', :'author', :'r1', :'r2'
  from public.solicitations s where s.id = :'sb'
returning id as ab \gset

insert into public.addenda (solicitation_id, number, state, data, narrative, created_by, reviewer_id, checker_id)
select s.id, 1, 'approved', s.data || '{"fundingAmountCents": 15000000}'::jsonb, 'Clarifies.', :'author', :'r1', :'r2'
  from public.solicitations s where s.id = :'sc'
returning id as ac \gset

insert into public.addenda (solicitation_id, number, state, data, narrative, created_by)
select s.id, 1, 'draft', s.data || '{"fundingAmountCents": 15000000}'::jsonb, '', :'author'
  from public.solicitations s where s.id = :'sd'
returning id as ad \gset

-- ===========================================================================
-- Storage: v{n} uploads while an approved addendum n - 1 exists; agency attachments while an addendum is a draft
-- ===========================================================================
select tests.act_as(:'r1');
select lives_ok(format($$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/%s/v2/rfb.pdf')$$, :'sa'),
  'office may upload v2/rfb.pdf while approved addendum 1 exists');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/%s/v3/rfb.pdf')$$, :'sa'),
  '42501', null, 'office may not upload v3 for addendum 1');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/%s/v1/rfb.pdf')$$, :'sa'),
  '42501', null, 'office may not upload into a published solicitation''s v1');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/%s/v2/rfb.pdf')$$, :'sd'),
  '42501', null, 'office may not upload v2 while addendum 1 is only a draft');
select tests.act_as(:'author');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/%s/v2/x.pdf')$$, :'sb'),
  '42501', null, 'the agency may not upload to the published bucket');
select lives_ok(format($$insert into storage.objects (bucket_id, name) values ('attachments', 'solicitations/%s/rev-drawings.pdf')$$, :'sd'),
  'the owning agency may upload an attachment while an addendum is a draft');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('attachments', 'solicitations/%s/rev-drawings.pdf')$$, :'sb'),
  '42501', null, 'no attachment uploads when no addendum is a draft');
reset role;

-- Pre-publication files are hidden from everyone but office staff (anon, bidders); v1 stays readable.
select tests.make_bidder('ap.bidder@test.test', 'AP Bidder Co') as bidder \gset
insert into storage.objects (bucket_id, name) select 'published', format('solicitations/%s/v1/rfb.pdf', :'sa');
insert into storage.objects (bucket_id, name) select 'attachments', format('solicitations/%s/old-drawings.pdf', :'sb');
select tests.act_as_anon();
select is((select count(*)::int from storage.objects where bucket_id = 'published'
             and name = format('solicitations/%s/v2/rfb.pdf', :'sa')), 0,
  'anon cannot read v2/rfb.pdf while addendum 1 is only approved');
select is((select count(*)::int from storage.objects where bucket_id = 'published'
             and name = format('solicitations/%s/v1/rfb.pdf', :'sa')), 1, 'anon still reads v1/rfb.pdf');
select tests.act_as(:'bidder');
select is((select count(*)::int from storage.objects where bucket_id = 'published'
             and name = format('solicitations/%s/v2/rfb.pdf', :'sa')), 0,
  'a bidder cannot read v2/rfb.pdf while addendum 1 is only approved');
select tests.act_as(:'r2');
select is((select count(*)::int from storage.objects where bucket_id = 'published'
             and name = format('solicitations/%s/v2/rfb.pdf', :'sa')), 1, 'office staff read pre-publication v2 files');
select tests.act_as(:'author');
select is((select count(*)::int from storage.objects where bucket_id = 'attachments'
             and name = format('solicitations/%s/rev-drawings.pdf', :'sd')), 1,
  'the owning agency reads its attachment while an addendum is a draft');
select is((select count(*)::int from storage.objects where bucket_id = 'attachments'
             and name = format('solicitations/%s/old-drawings.pdf', :'sb')), 0,
  'the owning agency cannot read attachments of a published solicitation with no draft addendum');
reset role;

-- ===========================================================================
-- Refusals (sb unless noted). Each throws_ok rolls back, so ab stays approved.
-- ===========================================================================
select jsonb_build_object('data', a.data - 'fundingAmountCents', 'clauses', '{}'::jsonb, 'settings', '{}'::jsonb) as snap_b,
       tests.bid_due_at(a.data) as due_b
  from public.addenda a where a.id = :'ab' \gset
select format('solicitations/%s/v2/rfb.pdf', :'sb') as rfb_b, format('solicitations/%s/v2/bid-form.pdf', :'sb') as form_b,
       format('solicitations/%s/v2/addendum.pdf', :'sb') as add_b \gset

select tests.act_as(:'author');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', :'rfb_b', :'form_b', :'add_b', :'snap_b', :'due_b', 15000000),
  'P0001', 'not_authorized', 'the agency cannot publish');
select tests.act_as(:'r1');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  gen_random_uuid(), :'rfb_b', :'form_b', :'add_b', :'snap_b', :'due_b', 15000000),
  'P0001', 'not_found', 'a missing addendum is not_found');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ad', format('solicitations/%s/v2/rfb.pdf', :'sd'), format('solicitations/%s/v2/bid-form.pdf', :'sd'),
  format('solicitations/%s/v2/addendum.pdf', :'sd'), :'snap_b', :'due_b', 15000000),
  'P0001', 'invalid_state', 'a draft addendum is invalid_state');
select tests.act_as(:'r3');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', :'rfb_b', :'form_b', :'add_b', :'snap_b', :'due_b', 15000000),
  'P0001', 'not_authorized', 'office staff other than the reviewer or checker cannot publish');

select tests.act_as(:'r1');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', null, :'form_b', :'add_b', :'snap_b', :'due_b', 15000000),
  'P0001', 'invalid_data', 'a missing path is invalid_data');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', format('solicitations/%s/v3/rfb.pdf', :'sb'), :'form_b', :'add_b', :'snap_b', :'due_b', 15000000),
  'P0001', 'invalid_paths', 'an RFB path for the wrong version is invalid_paths');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', :'rfb_b', :'form_b', format('solicitations/%s/v2/other.pdf', :'sb'), :'snap_b', :'due_b', 15000000),
  'P0001', 'invalid_paths', 'a wrong addendum path is invalid_paths');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', :'rfb_b', format('solicitations/%s/v2/bid-form.pdf', :'sa'), :'add_b', :'snap_b', :'due_b', 15000000),
  'P0001', 'invalid_paths', 'another solicitation''s bid form path is invalid_paths');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', :'rfb_b', :'form_b', :'add_b', :'snap_b', (:'due_b'::timestamptz + interval '1 minute')::text, 15000000),
  'P0001', 'bid_due_mismatch', 'a due time that differs from the recomputed one is bid_due_mismatch');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', :'rfb_b', :'form_b', :'add_b', :'snap_b', :'due_b', 15000001),
  'P0001', 'snapshot_mismatch', 'a funding amount that differs from the addendum is snapshot_mismatch');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', :'rfb_b', :'form_b', :'add_b',
  jsonb_set(:'snap_b'::jsonb, '{data,location,fundingAmountCents}', '15000000'), :'due_b', 15000000),
  'P0001', 'snapshot_mismatch', 'funding anywhere in the snapshot is snapshot_mismatch');

-- locked_field: an addendum whose data changed a locked key (written around the drafting guard).
reset role;
update public.addenda set data = jsonb_set(data, '{newspapers}', '"Other Paper"') where id = :'ab';
select tests.act_as(:'r1');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', :'rfb_b', :'form_b', :'add_b', :'snap_b', :'due_b', 15000000),
  'P0001', 'locked_field', 'a changed locked field is re-checked at publish');
reset role;
update public.addenda set data = jsonb_set(data, '{newspapers}', to_jsonb((select s.data ->> 'newspapers'
  from public.solicitations s where s.id = :'sb'))) where id = :'ab';

-- too_close: a due time on the minute at or before clock_timestamp() + 5 days (the exact edge is pinned on
-- app.addendum_too_close above; data times have minute precision).
select date_trunc('minute', clock_timestamp() + interval '5 days')
         at time zone (select timezone from public.settings where id = 1) as close_local \gset
update public.addenda
   set data = data || jsonb_build_object('bidDueDate', to_char(:'close_local'::timestamp, 'YYYY-MM-DD'),
                                         'bidDueTime', to_char(:'close_local'::timestamp, 'HH24:MI'))
 where id = :'ab';
select tests.bid_due_at(data) as due_close from public.addenda where id = :'ab' \gset
select ok(:'due_close'::timestamptz < clock_timestamp() + interval '5 days', 'the too_close fixture is under 5 days');
select tests.act_as(:'r1');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ab', :'rfb_b', :'form_b', :'add_b', :'snap_b', :'due_close', 15000000),
  'P0001', 'too_close', 'a due time under 5 days from publish is too_close');

-- bids_closed: sc is open by now() (transaction start) but past due on the wall clock.
reset role;
select tests.set_bid_due(:'sc', clock_timestamp());
select ok(not app.bids_closed(:'sc'), 'sc is not closed by now()');
select tests.act_as(:'r2');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'ac', format('solicitations/%s/v2/rfb.pdf', :'sc'), format('solicitations/%s/v2/bid-form.pdf', :'sc'),
  format('solicitations/%s/v2/addendum.pdf', :'sc'),
  (select jsonb_build_object('data', a.data - 'fundingAmountCents') from public.addenda a where a.id = :'ac'),
  (select tests.bid_due_at(a.data) from public.addenda a where a.id = :'ac'), 15000000),
  'P0001', 'bids_closed', 'publishing at or after the due time on the wall clock is bids_closed');
reset role;

select is((select state::text from public.addenda where id = :'ab'), 'approved', 'refusals leave ab approved');
select is((select version from public.solicitations where id = :'sb'), 1, 'refusals leave sb at version 1');

-- A refused publish leaves its uploads behind: office may delete v2 files no published version owns, then retry.
select tests.act_as(:'r1');
select lives_ok(format($$insert into storage.objects (bucket_id, name) values ('published', %L)$$, :'rfb_b'),
  'office uploads sb v2/rfb.pdf for addendum 1');
delete from storage.objects where bucket_id = 'published' and name = :'rfb_b';
reset role;
select is((select count(*)::int from storage.objects where bucket_id = 'published' and name = :'rfb_b'), 0,
  'office deletes an unpublished v2 file after a refused publish');
select tests.act_as(:'r1');
select lives_ok(format($$insert into storage.objects (bucket_id, name) values ('published', %L)$$, :'rfb_b'),
  'and uploads it again for the retry');
reset role;

-- ===========================================================================
-- Happy path: r1 publishes sa's addendum 1 as version 2
-- ===========================================================================
select jsonb_build_object('data', a.data - 'fundingAmountCents', 'clauses', '{}'::jsonb, 'settings', '{}'::jsonb) as snap_a,
       tests.bid_due_at(a.data) as due_a, a.data - 'fundingAmountCents' as data_a
  from public.addenda a where a.id = :'aa' \gset
select to_jsonb(v) as v1_before from public.solicitation_versions v where v.solicitation_id = :'sa' and v.version = 1 \gset
select format('solicitations/%s/v2/rfb.pdf', :'sa') as rfb_a, format('solicitations/%s/v2/bid-form.pdf', :'sa') as form_a,
       format('solicitations/%s/v2/addendum.pdf', :'sa') as add_a \gset

-- 0035: the files must be in the published bucket. sa's v2/rfb.pdf was uploaded above; the other two are not yet.
select tests.act_as(:'r1');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'aa', :'rfb_a', :'form_a', :'add_a', :'snap_a', :'due_a', 16000000), 'P0001', 'invalid_paths',
  'publish_addendum refuses while any of the version''s files is missing from storage');
reset role;
select is((select state::text from public.addenda where id = :'aa'), 'approved', 'the refused publish changed nothing');
select tests.stage_version_files(:'sa', 2);
select tests.act_as(:'r1');
select is(public.publish_addendum(:'aa', :'rfb_a', :'form_a', :'add_a', :'snap_a', :'due_a', 16000000), 2,
  'publish_addendum returns the new version');
select is(current_setting('app.publishing_addendum', true), '',
  'the publishing_addendum setting is reset before publish_addendum returns');
reset role;

select is((select row(version, rfb_path, bid_form_path, bid_due_at, published_snapshot, data)::text
             from public.solicitations where id = :'sa'),
          row(2, :'rfb_a', :'form_a', :'due_a'::timestamptz, :'snap_a'::jsonb, :'data_a'::jsonb)::text,
  'the pointer columns moved to version 2');
select ok((select not (data ? 'fundingAmountCents') from public.solicitations where id = :'sa'),
  'solicitations.data carries no funding amount');
select is((select state::text from public.solicitations where id = :'sa'), 'published', 'sa is still published');
select is((select to_jsonb(v) from public.solicitation_versions v where v.solicitation_id = :'sa' and v.version = 1),
  :'v1_before'::jsonb, 'the version 1 row is unchanged');
select is((select row(snapshot, rfb_path, bid_form_path, addendum_path, bid_due_at, published_by, schedule_changed)::text
             from public.solicitation_versions where solicitation_id = :'sa' and version = 2),
          row(:'snap_a'::jsonb, :'rfb_a', :'form_a', :'add_a', :'due_a'::timestamptz, :'r1'::uuid, true)::text,
  'the version 2 row records the snapshot, paths, due time, publisher and schedule change');
select is((select funding_cents from public.solicitation_funding_changes where solicitation_id = :'sa' and version = 2),
  16000000::bigint, 'the funding change is frozen for version 2');
select is(app.funding_cents(:'sa'), 16000000::bigint, 'app.funding_cents returns the new funding');
select is(app.funding_from_estimate(:'sa'), false, 'funding is no longer from the estimate');
select is(app.last_schedule_change(:'sa'), 2, 'version 2 is the latest schedule change');
select is((select row(state::text, published_version)::text from public.addenda where id = :'aa'),
          row('published', 2)::text, 'the addendum is published as version 2');
select is((select row(actor_id, detail ->> 'addendum_id', (detail ->> 'number')::int, (detail ->> 'version')::int,
                      (detail ->> 'schedule_changed')::boolean, (detail ->> 'bid_due_at')::timestamptz,
                      (detail ->> 'after_answers_due')::boolean)::text
             from public.audit_log where solicitation_id = :'sa' and action = 'publish_addendum'),
          row(:'r1'::uuid, :'aa', 1, 2, true, :'due_a'::timestamptz, false)::text,
  'one publish_addendum audit row with version, schedule_changed, bid_due_at and after_answers_due');

-- The freeze is back in force in the same transaction (the setting was reset).
select throws_ok(format($$update public.solicitations set bid_due_at = bid_due_at + interval '1 day' where id = %L$$, :'sa'),
  'P0001', null, 'a later pointer update in the same transaction is refused');

-- Published again: the addendum is no longer approved, and v2/v3 uploads are closed.
select tests.act_as(:'r1');
select throws_ok(format('select public.publish_addendum(%L, %L, %L, %L, %L, %L, %s)',
  :'aa', :'rfb_a', :'form_a', :'add_a', :'snap_a', :'due_a', 16000000),
  'P0001', 'invalid_state', 'publishing twice is invalid_state');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/%s/v2/x.pdf')$$, :'sa'),
  '42501', null, 'no v2 uploads once addendum 1 is published');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/%s/v3/rfb.pdf')$$, :'sa'),
  '42501', null, 'no v3 uploads without an approved addendum 2');
reset role;

-- Version 2 is published: its files are public now, and frozen.
select tests.act_as_anon();
select is((select count(*)::int from storage.objects where bucket_id = 'published' and name = :'rfb_a'), 1,
  'anon reads v2/rfb.pdf once version 2 is published');
select tests.act_as(:'bidder');
select is((select count(*)::int from storage.objects where bucket_id = 'published' and name = :'rfb_a'), 1,
  'a bidder reads v2/rfb.pdf once version 2 is published');
select tests.act_as(:'r1');
delete from storage.objects where bucket_id = 'published' and name = :'rfb_a';
reset role;
select is((select count(*)::int from storage.objects where bucket_id = 'published' and name = :'rfb_a'), 1,
  'office cannot delete a published version''s file');

-- ===========================================================================
-- sb: the checker publishes just over 5 days out; schedule unchanged; answersDue already past.
-- ===========================================================================
select (date_trunc('minute', clock_timestamp() + interval '5 days') + interval '2 minutes')
         at time zone (select timezone from public.settings where id = 1) as edge_local \gset
update public.addenda
   set data = data || jsonb_build_object('bidDueDate', to_char(:'edge_local'::timestamp, 'YYYY-MM-DD'),
                                         'bidDueTime', to_char(:'edge_local'::timestamp, 'HH24:MI'))
 where id = :'ab';
select tests.bid_due_at(data) as due_edge from public.addenda where id = :'ab' \gset
select tests.stage_version_files(:'sb', 2);
select tests.act_as(:'r2');
select is(public.publish_addendum(:'ab', :'rfb_b', :'form_b', :'add_b', :'snap_b', :'due_edge', 15000000), 2,
  'the checker publishes a due time just over 5 days out');
reset role;
select is((select schedule_changed from public.solicitation_versions where solicitation_id = :'sb' and version = 2),
  false, 'an unchanged schedule records schedule_changed = false');
select is(app.last_schedule_change(:'sb'), 1, 'the latest schedule change is still version 1');
select is((select bid_due_at from public.solicitations where id = :'sb'), :'due_edge'::timestamptz,
  'sb''s due time moved');
select is(app.funding_cents(:'sb'), 15000000::bigint, 'an unchanged funding amount is still frozen per version');
select is((select ((detail ->> 'schedule_changed')::boolean, (detail ->> 'after_answers_due')::boolean)::text
             from public.audit_log where solicitation_id = :'sb' and action = 'publish_addendum'),
          (false, true)::text, 'the audit records after_answers_due when answersDue has passed');


-- ===========================================================================
-- Uploads only for the next version (n = version + 1), and only while bidding is open.
-- ===========================================================================
insert into public.addenda (solicitation_id, number, state, data, narrative, created_by, reviewer_id, checker_id)
select s.id, 2, 'approved', s.data || '{"fundingAmountCents": 15000000}'::jsonb, 'x', :'author', :'r1', :'r2'
  from public.solicitations s where s.id = :'sd';
select tests.act_as(:'r1');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/%s/v3/rfb.pdf')$$, :'sd'),
  '42501', null, 'no upload for an approved addendum n - 1 when n is not version + 1');
reset role;
select tests.set_bid_due(:'sc', now() - interval '1 second');
select tests.act_as(:'r1');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('published', 'solicitations/%s/v2/rfb.pdf')$$, :'sc'),
  '42501', null, 'no v2 upload once bidding has closed (the approved addendum counts as withdrawn)');
reset role;

select * from finish();
rollback;
