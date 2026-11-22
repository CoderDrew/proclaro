-- 0030: bids priced against a solicitation version. The draft reset at publish, stale_draft, resubmit required at
-- close (app.bid_stale / app.bid_excluded in every post-close reader), public.stale_bids and
-- public.my_bid_status_addenda. Pins Review Focus 2 (a draft submitted against a schedule that changed under it) and
-- Review Focus 3 (who counts at close after a schedule change).
begin;

select plan(76);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000003b1', 'BV Office', 'office'),
  ('00000000-0000-0000-0000-0000000003b2', 'BV Agency', 'agency');

select tests.make_user('bv.author@test.test', '00000000-0000-0000-0000-0000000003b2') as author \gset
select tests.make_user('bv.r1@test.test',     '00000000-0000-0000-0000-0000000003b1') as r1 \gset
select tests.make_user('bv.r2@test.test',     '00000000-0000-0000-0000-0000000003b1') as r2 \gset
select tests.make_bidder('bv.a@test.test', 'BV Bidder A') as bidder_a \gset
select tests.make_bidder('bv.b@test.test', 'BV Bidder B') as bidder_b \gset
select tests.make_bidder('bv.c@test.test', 'BV Bidder C') as bidder_c \gset
select tests.make_bidder('bv.d@test.test', 'BV Bidder D') as bidder_d \gset
select tests.make_bidder('bv.e@test.test', 'BV Bidder E') as bidder_e \gset
select tests.make_bidder('bv.f@test.test', 'BV Bidder F') as bidder_f \gset
select tests.make_bidder('bv.g@test.test', 'BV Bidder G') as bidder_g \gset
select tests.make_bidder('bv.w@test.test', 'BV Bidder W') as bidder_w \gset

-- Test-only helpers (rolled back with the transaction).
-- Fill a draft as the calling bidder (RLS applies): the given item prices, one alternate, paper bond, insurance and
-- references uploaded and attached.
create function tests.t5_fill(p_bid uuid, p_tag text, p_items bigint[])
returns void
language plpgsql
as $$
declare
  v_ins text := 'bids/' || p_bid || '/' || gen_random_uuid() || '/ins-' || p_tag || '.pdf';
  v_ref text := 'bids/' || p_bid || '/' || gen_random_uuid() || '/ref-' || p_tag || '.pdf';
begin
  update public.bid_drafts
     set item_cents = p_items, alternate_cents = '{1500000}', bid_bond_choice = 'paper'
   where bid_id = p_bid;
  delete from public.bid_draft_files where bid_id = p_bid;
  insert into storage.objects (bucket_id, name, metadata) values
    ('bid-files', v_ins, jsonb_build_object('eTag', '"' || p_tag || '-ins"', 'size', 2048, 'mimetype', 'application/pdf')),
    ('bid-files', v_ref, jsonb_build_object('eTag', '"' || p_tag || '-ref"', 'size', 4096, 'mimetype', 'application/pdf'));
  insert into public.bid_draft_files (bid_id, slot, path, file_name) values
    (p_bid, 'insurance', v_ins, 'ins-' || p_tag || '.pdf'),
    (p_bid, 'references', v_ref, 'ref-' || p_tag || '.pdf');
end;
$$;
grant execute on function tests.t5_fill(uuid, text, bigint[]) to authenticated;

-- ===========================================================================
-- Schema objects and grants
-- ===========================================================================
select has_column('public', 'bid_drafts', 'solicitation_version', 'bid_drafts.solicitation_version exists');
select col_not_null('public', 'bid_drafts', 'solicitation_version', 'bid_drafts.solicitation_version is not null');
select has_column('public', 'bid_versions', 'solicitation_version', 'bid_versions.solicitation_version exists');
select col_not_null('public', 'bid_versions', 'solicitation_version', 'bid_versions.solicitation_version is not null');
select ok(not has_column_privilege('authenticated', 'public.bid_drafts', 'solicitation_version', 'update'),
  'bidders cannot write a draft''s solicitation_version');
select has_function('app', 'bid_stale', array['uuid', 'integer'], 'app.bid_stale exists');
select has_function('app', 'bid_excluded', array['uuid', 'integer'], 'app.bid_excluded exists');
select has_function('public', 'stale_bids', array['uuid'], 'public.stale_bids exists');
select has_function('public', 'my_bid_status_addenda', array['uuid'], 'public.my_bid_status_addenda exists');
select ok(not has_function_privilege('authenticated', 'app.bid_stale(uuid, int)', 'execute')
          and not has_function_privilege('authenticated', 'app.bid_excluded(uuid, int)', 'execute'),
  'app.bid_stale and app.bid_excluded are not callable through the API');
select ok(has_function_privilege('authenticated', 'public.stale_bids(uuid)', 'execute')
          and has_function_privilege('authenticated', 'public.my_bid_status_addenda(uuid)', 'execute'),
  'authenticated can execute stale_bids and my_bid_status_addenda');
select ok(not has_function_privilege('anon', 'public.stale_bids(uuid)', 'execute')
          and not has_function_privilege('anon', 'public.my_bid_status_addenda(uuid)', 'execute'),
  'anon cannot execute stale_bids or my_bid_status_addenda');

-- ===========================================================================
-- Fixtures. s1: addendum 1 changes the bid schedule (adds Item 3). s2: addendum 1 is schedule-neutral.
-- Each solicitation gets its version-1 row (make_published_solicitation writes none).
-- ===========================================================================
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000003b2', :'author',
  now() + interval '20 days') as s1 \gset
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000003b2', :'author',
  now() + interval '20 days') as s2 \gset
insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path, bid_due_at)
select s.id, 1, s.published_snapshot, format('solicitations/%s/v1/rfb.pdf', s.id),
       format('solicitations/%s/v1/bid-form.pdf', s.id), s.bid_due_at
  from public.solicitations s where s.id in (:'s1', :'s2');

-- ===========================================================================
-- Before the addendum (s1): A and B submit at version 1, D drafts prices at version 1.
-- ===========================================================================
select tests.act_as(:'bidder_a');
select public.start_bid(:'s1') as bid_a \gset
select is((select solicitation_version from public.bid_drafts where bid_id = :'bid_a'), 1,
  'start_bid prices the draft against the current solicitation version');
select tests.t5_fill(:'bid_a', 'a1', '{12500000,234567}');
select lives_ok(format('select * from public.submit_bid(%L)', :'bid_a'), 'A submits at version 1');

select tests.act_as(:'bidder_b');
select public.start_bid(:'s1') as bid_b \gset
select tests.t5_fill(:'bid_b', 'b1', '{12400000,234567}');
select lives_ok(format('select * from public.submit_bid(%L)', :'bid_b'), 'B submits at version 1');

select tests.act_as(:'bidder_d');
select public.start_bid(:'s1') as bid_d \gset
select tests.t5_fill(:'bid_d', 'd1', '{12300000,234567}');

-- W submits at version 1 and withdraws, all before the addendum and close.
select tests.act_as(:'bidder_w');
select public.start_bid(:'s1') as bid_w \gset
select tests.t5_fill(:'bid_w', 'w1', '{12200000,234567}');
select lives_ok(format('select * from public.submit_bid(%L)', :'bid_w'), 'W submits at version 1');
select lives_ok(format('select public.withdraw_bid(%L)', :'bid_w'), 'W withdraws version 1');
reset role;

select is((select solicitation_version from public.bid_versions where bid_id = :'bid_a' and version = 1), 1,
  'submit_bid copies the draft''s solicitation_version into bid_versions');
select is(app.bid_stale(:'bid_a', 1), false, 'a version-1 bid is not stale before any schedule change');
-- These bids were started before the addendum is published (the transaction clock is the same instant).
update public.bids set created_at = now() - interval '1 hour' where id in (:'bid_a', :'bid_b', :'bid_d');

-- ===========================================================================
-- Publish addendum 1 on s1 (adds Item 3): the schedule changed, every draft of s1 is reset.
-- ===========================================================================
insert into public.addenda (solicitation_id, number, state, data, narrative, created_by, reviewer_id, checker_id)
select s.id, 1, 'approved',
       s.data || jsonb_build_object(
         'fundingAmountCents', 15000000,
         'schedule', jsonb_set(s.data -> 'schedule', '{items}',
                               (s.data -> 'schedule' -> 'items')
                               || '[{"name": "Item 3", "description": "Paving"}]'::jsonb)),
       'Adds paving.', :'author', :'r1', :'r2'
  from public.solicitations s where s.id = :'s1'
returning id as add1 \gset
select jsonb_build_object('data', a.data - 'fundingAmountCents', 'clauses', '{}'::jsonb, 'settings', '{}'::jsonb) as snap1,
       tests.bid_due_at(a.data) as due1
  from public.addenda a where a.id = :'add1' \gset

select tests.stage_version_files(:'s1', 2);
select tests.act_as(:'r1');
select is(public.publish_addendum(:'add1', format('solicitations/%s/v2/rfb.pdf', :'s1'),
  format('solicitations/%s/v2/bid-form.pdf', :'s1'), format('solicitations/%s/v2/addendum.pdf', :'s1'),
  :'snap1', :'due1', 15000000), 2, 'addendum 1 publishes s1 as version 2');
reset role;

-- The originals log flags A's stale version before close (0035); B's and W's statuses are unchanged in kind.
select (select reference from public.bids where id = :'bid_a') as ref_a,
       (select reference from public.bids where id = :'bid_w') as ref_w \gset
select tests.act_as(:'r1');
select is((select i.status from public.office_bid_index(:'s1') i where i.reference = :'ref_a' and i.version = 1),
  'resubmit_required', 'office_bid_index flags a stale latest version as resubmit_required');
select is((select i.status from public.office_bid_index(:'s1') i where i.reference = :'ref_w' and i.version = 1),
  'withdrawn', 'office_bid_index: withdrawn still wins over stale');
reset role;

-- Review Focus 2: the reset.
select is((select array[cardinality(item_cents), cardinality(alternate_cents), solicitation_version]
             from public.bid_drafts where bid_id = :'bid_d'), array[0, 0, 2],
  'publish_addendum cleared D''s prices and moved its draft to version 2');
select is((select count(*)::int from public.bid_draft_files where bid_id = :'bid_d'), 2,
  'the reset keeps the draft''s uploaded files');

select tests.act_as(:'bidder_d');
select is((select row(r.resubmit_required, r.schedule_changed_in, r.draft_cleared_by)::text
             from public.my_bid_status_addenda(:'bid_d') r), '(f,,1)',
  'my_bid_status_addenda: D''s prices were cleared by addendum 1');
select throws_ok(format('select * from public.submit_bid(%L)', :'bid_d'), 'P0001', 'invalid_bid',
  'a cleared draft cannot be submitted until the prices are entered again');
select tests.t5_fill(:'bid_d', 'd2', '{12300000,234567,99000}');
select lives_ok(format('select * from public.submit_bid(%L)', :'bid_d'), 'D submits normally after the reset');
reset role;
select is((select solicitation_version from public.bid_versions where bid_id = :'bid_d' and version = 1), 2,
  'D''s submitted version is priced against version 2');

-- Review Focus 2: stale_draft. E's draft holds version-1 prices that the reset missed (simulating a draft written
-- in a race with publish); submit_bid refuses it after taking its locks.
select tests.act_as(:'bidder_e');
select public.start_bid(:'s1') as bid_e \gset
select is((select solicitation_version from public.bid_drafts where bid_id = :'bid_e'), 2,
  'start_bid after the addendum prices the draft against version 2');
select tests.t5_fill(:'bid_e', 'e1', '{12000000,234567}');
reset role;
update public.bid_drafts set solicitation_version = 1 where bid_id = :'bid_e';
select tests.act_as(:'bidder_e');
select throws_ok(format('select * from public.submit_bid(%L)', :'bid_e'), 'P0001', 'stale_draft',
  'submit_bid refuses a draft priced against a schedule that has since changed');
reset role;
select is((select count(*)::int from public.bid_versions where bid_id = :'bid_e'), 0, 'nothing was sealed for E');

-- F starts after the addendum: its bid is not older than version 2, so nothing was cleared.
select tests.act_as(:'bidder_f');
select public.start_bid(:'s1') as bid_f \gset
select is((select row(r.resubmit_required, r.schedule_changed_in, r.draft_cleared_by)::text
             from public.my_bid_status_addenda(:'bid_f') r), '(f,,)',
  'my_bid_status_addenda: a bid started at version 2 had nothing cleared');

-- B resubmits at version 2 through replace_bid.
select tests.act_as(:'bidder_b');
select is((select row(r.resubmit_required, r.schedule_changed_in, r.draft_cleared_by)::text
             from public.my_bid_status_addenda(:'bid_b') r), '(t,1,)',
  'my_bid_status_addenda: B must resubmit (addendum 1 changed the schedule)');
select lives_ok(format('select public.replace_bid(%L)', :'bid_b'), 'B replaces its stale bid');
select is((select array[version, cardinality(item_cents), cardinality(alternate_cents), solicitation_version]
             from public.bid_drafts where bid_id = :'bid_b'), array[2, 0, 0, 2],
  'replace_bid on a stale bid starts an empty draft at the current solicitation version');
select tests.t5_fill(:'bid_b', 'b2', '{12400000,234567,88000}');
select lives_ok(format('select * from public.submit_bid(%L)', :'bid_b'), 'B submits version 2');
select is((select row(r.resubmit_required, r.schedule_changed_in, r.draft_cleared_by)::text
             from public.my_bid_status_addenda(:'bid_b') r), '(f,,)',
  'my_bid_status_addenda: B no longer needs to resubmit');

-- A never resubmits.
select tests.act_as(:'bidder_a');
select is((select row(r.resubmit_required, r.schedule_changed_in, r.draft_cleared_by)::text
             from public.my_bid_status_addenda(:'bid_a') r), '(t,1,)',
  'my_bid_status_addenda: A must resubmit');
select throws_ok(format('select * from public.my_bid_status_addenda(%L)', :'bid_b'), 'P0001', 'not_found',
  'my_bid_status_addenda: another bidder''s bid is not_found');
select tests.act_as(:'r1');
select throws_ok(format('select * from public.my_bid_status_addenda(%L)', :'bid_a'), 'P0001', 'not_authorized',
  'my_bid_status_addenda: office staff are not_authorized');

-- stale_bids before close.
select throws_ok(format('select * from public.stale_bids(%L)', :'s1'), 'P0001', 'sealed',
  'stale_bids is sealed before close');
select tests.act_as(:'bidder_a');
select throws_ok(format('select * from public.stale_bids(%L)', :'s1'), 'P0001', 'not_authorized',
  'stale_bids: a bidder is not_authorized');
reset role;

select is(app.bid_stale(:'bid_a', 1), true, 'bid_stale: A''s version 1 is stale after the schedule change');
select is(app.bid_stale(:'bid_b', 2), false, 'bid_stale: B''s version 2 is current');
select is(app.bid_excluded(:'bid_a', 1), true, 'bid_excluded: a stale version is excluded');
select is(app.bid_excluded(:'bid_b', 2), false, 'bid_excluded: a current, not withdrawn version is not excluded');

-- ===========================================================================
-- Close s1. Signed originals for A v1, B v2 and D v1, all before the due time.
-- Review Focus 3: A is excluded everywhere, B counts at version 2, A's original does not count.
-- ===========================================================================
select tests.set_bid_due(:'s1', now());
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
select :'s1', b.id, b.reference, x.version, 'signed_form', now() - interval '1 hour', :'r1', now() - interval '1 hour'
  from public.bids b
  join (values (:'bid_a'::uuid, 1), (:'bid_b'::uuid, 2), (:'bid_d'::uuid, 1)) x(bid_id, version) on x.bid_id = b.id;
select f.path as path_a from public.bid_version_files f join public.bid_versions v on v.id = f.version_id
 where v.bid_id = :'bid_a' and v.version = 1 and f.slot = 'insurance' \gset
select f.path as path_b from public.bid_version_files f join public.bid_versions v on v.id = f.version_id
 where v.bid_id = :'bid_b' and v.version = 2 and f.slot = 'insurance' \gset

select tests.act_as(:'r1');
select set_eq(format('select bid_id from public.opened_bids(%L)', :'s1'), array[:'bid_b'::uuid, :'bid_d'::uuid],
  'opened_bids lists B and D, not A (resubmit required)');
select is((select row(o.version, o.original_received)::text from public.opened_bids(:'s1') o where o.bid_id = :'bid_b'),
  '(2,t)', 'B is opened at version 2 with its version-2 original counted');
select is((select count(*)::int from public.opened_bid_files(:'s1') f where f.bid_id = :'bid_a'), 0,
  'opened_bid_files has no files for A');
select is((select count(*)::int from public.opened_bid_files(:'s1') f where f.bid_id = :'bid_b'), 2,
  'opened_bid_files has B''s version-2 files');
select is((select count(*)::int from public.review_bids(:'s1') r where r.bid_id = :'bid_a'), 0,
  'review_bids does not list A');
select results_eq(format('select bid_id, version, solicitation_version, bidder_legal_name from public.stale_bids(%L)', :'s1'),
  format('values (%L::uuid, 1, 1, %L::text)', :'bid_a', 'BV Bidder A'),
  'stale_bids lists A only, at version 1 priced against version 1 (not W, withdrawn at version 1)');
select is(app.can_read_bid_file(:'path_a'), false, 'office staff cannot read A''s sealed files after close');
select is(app.can_read_bid_file(:'path_b'), true, 'office staff read B''s version-2 files after close');
select throws_ok(format('select public.set_bid_outcome(%L, %L, null, %L)', :'bid_a', 'accepted', 'ok'),
  'P0001', 'not_found', 'set_bid_outcome: A has no opened version');
select throws_ok(format('select public.verify_resident(%L, true, %L)', :'bid_a', 'ok'),
  'P0001', 'not_found', 'verify_resident: A has no opened version');
select lives_ok(format('select * from public.opened_bids(%L)', :'s1'), 'a second opening read');
reset role;

select is((select a.detail from public.bid_audit_log a
            where a.bid_id = :'bid_a' and a.action = 'bid_close_determination' order by a.id desc limit 1),
  '{"version": 1, "reason": "resubmit_required"}'::jsonb, 'A''s close determination records resubmit_required');
select is((select count(*)::int from public.bid_audit_log a
            where a.bid_id = :'bid_a' and a.action = 'bid_close_determination'), 1,
  'the resubmit_required determination is written once, not on every read');
select is((select count(*)::int from public.bid_audit_log a
            where a.bid_id = :'bid_w' and a.action = 'bid_close_determination'), 0,
  'no close determination (resubmit_required or other) is written for W''s withdrawn bid');
select tests.act_as(:'bidder_w');
select is((select r.resubmit_required from public.my_bid_status_addenda(:'bid_w') r), false,
  'my_bid_status_addenda: a withdrawn stale bid is not resubmit required');
reset role;
select is((select count(*)::int from app.bid_review_status(:'bid_a')), 0, 'bid_review_status returns no row for A');
select is((select count(*)::int from app.bid_review_status(:'bid_b')), 1, 'bid_review_status returns a row for B');
select is((select c.status from app.bond_cure(:'bid_a') c), 'not_required', 'bond_cure: A has no bond to cure');
select is((select c.status from app.bond_cure(:'bid_b') c), 'pending', 'bond_cure: B''s paper bond cure is pending');

select tests.act_as(:'bidder_a');
select is((select row(r.resubmit_required, r.schedule_changed_in, r.draft_cleared_by)::text
             from public.my_bid_status_addenda(:'bid_a') r), '(t,1,)',
  'my_bid_status_addenda: A still reads resubmit required after close');
reset role;

-- ===========================================================================
-- s2: a schedule-neutral addendum. C (submitted at version 1) still counts; G's draft is not reset.
-- ===========================================================================
select tests.act_as(:'bidder_c');
select public.start_bid(:'s2') as bid_c \gset
select tests.t5_fill(:'bid_c', 'c1', '{12600000,234567}');
select lives_ok(format('select * from public.submit_bid(%L)', :'bid_c'), 'C submits at version 1');
select tests.act_as(:'bidder_g');
select public.start_bid(:'s2') as bid_g \gset
select tests.t5_fill(:'bid_g', 'g1', '{12700000,234567}');
reset role;

insert into public.addenda (solicitation_id, number, state, data, narrative, created_by, reviewer_id, checker_id)
select s.id, 1, 'approved', s.data || '{"fundingAmountCents": 15000000, "summary": "Clarified summary."}'::jsonb,
       'Clarifies the summary.', :'author', :'r1', :'r2'
  from public.solicitations s where s.id = :'s2'
returning id as add2 \gset
select jsonb_build_object('data', a.data - 'fundingAmountCents', 'clauses', '{}'::jsonb, 'settings', '{}'::jsonb) as snap2,
       tests.bid_due_at(a.data) as due2
  from public.addenda a where a.id = :'add2' \gset
select tests.stage_version_files(:'s2', 2);
select tests.act_as(:'r1');
select is(public.publish_addendum(:'add2', format('solicitations/%s/v2/rfb.pdf', :'s2'),
  format('solicitations/%s/v2/bid-form.pdf', :'s2'), format('solicitations/%s/v2/addendum.pdf', :'s2'),
  :'snap2', :'due2', 15000000), 2, 'the schedule-neutral addendum publishes s2 as version 2');
reset role;

select is((select array[cardinality(item_cents), cardinality(alternate_cents), solicitation_version]
             from public.bid_drafts where bid_id = :'bid_g'), array[2, 1, 1],
  'a schedule-neutral addendum leaves G''s draft prices and version alone');
select is(app.bid_stale(:'bid_c', 1), false, 'bid_stale: C''s version 1 is not stale after a neutral addendum');
select tests.act_as(:'bidder_c');
select is((select row(r.resubmit_required, r.schedule_changed_in, r.draft_cleared_by)::text
             from public.my_bid_status_addenda(:'bid_c') r), '(f,,)',
  'my_bid_status_addenda: C need not resubmit');
select tests.act_as(:'bidder_g');
select lives_ok(format('select * from public.submit_bid(%L)', :'bid_g'),
  'G submits its version-1 prices after a neutral addendum');
reset role;

select tests.set_bid_due(:'s2', now());
insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by, logged_at)
select :'s2', b.id, b.reference, 1, 'signed_form', now() - interval '1 hour', :'r1', now() - interval '1 hour'
  from public.bids b where b.id = :'bid_c';
select tests.act_as(:'r1');
select set_eq(format('select bid_id from public.opened_bids(%L)', :'s2'), array[:'bid_c'::uuid, :'bid_g'::uuid],
  'opened_bids on s2 lists C and G (the addendum did not change the schedule)');
select is((select o.original_received from public.opened_bids(:'s2') o where o.bid_id = :'bid_c'), true,
  'C''s version-1 original counts');
select is((select count(*)::int from public.stale_bids(:'s2')), 0, 'stale_bids on s2 is empty');
reset role;
select is((select count(*)::int from app.bid_review_status(:'bid_c')), 1, 'bid_review_status returns a row for C');

select * from finish();
rollback;
