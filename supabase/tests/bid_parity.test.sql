-- GENERATED from src/domain/bid/parityFixtures.ts by parity.test.ts. Do not edit by hand:
-- run `UPDATE_PARITY_SQL=1 npm test -- parity` after changing the fixtures.
-- Each case builds a bid and its draft, then compares app.bid_draft_problems with the TypeScript validator's
-- expected codes (the same cases run through validateBidDraft in parity.test.ts).
begin;

select plan(33);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000008a1', 'BP Agency', 'agency');
select tests.make_user('bp.author@test.test', '00000000-0000-0000-0000-0000000008a1') as author \gset
select tests.make_bidder('bp.bidder@test.test', 'BP Bidder') as bidder \gset
select p.org_id as org from public.profiles p where p.user_id = :'bidder' \gset

-- 1: complete draft with a paper bond
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_1 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_1', :'org', app.new_bid_reference(), :'bidder') returning id as bid_1 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_1', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_1' || '/' || gen_random_uuid() || '/insurance.pdf' as path_1_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_1_insurance', jsonb_build_object('eTag', '"parity-1-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_1', 'insurance', :'path_1_insurance', 'insurance.pdf');
select 'bids/' || :'bid_1' || '/' || gen_random_uuid() || '/references.pdf' as path_1_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_1_references', jsonb_build_object('eTag', '"parity-1-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_1', 'references', :'path_1_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_1')::text, '{}', 'complete draft with a paper bond');

-- 2: complete draft with an electronic bond
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_2 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_2', :'org', app.new_bid_reference(), :'bidder') returning id as bid_2 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_2', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'electronic', null);
select 'bids/' || :'bid_2' || '/' || gen_random_uuid() || '/insurance.pdf' as path_2_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_2_insurance', jsonb_build_object('eTag', '"parity-2-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_2', 'insurance', :'path_2_insurance', 'insurance.pdf');
select 'bids/' || :'bid_2' || '/' || gen_random_uuid() || '/references.pdf' as path_2_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_2_references', jsonb_build_object('eTag', '"parity-2-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_2', 'references', :'path_2_references', 'references.pdf');
select 'bids/' || :'bid_2' || '/' || gen_random_uuid() || '/bid_bond.pdf' as path_2_bid_bond \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_2_bid_bond', jsonb_build_object('eTag', '"parity-2-bid_bond"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_2', 'bid_bond', :'path_2_bid_bond', 'bid_bond.pdf');
select is(app.bid_draft_problems(:'bid_2')::text, '{}', 'complete draft with an electronic bond');

-- 3: null item price
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_3 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_3', :'org', app.new_bid_reference(), :'bidder') returning id as bid_3 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_3', 1, '{12500000,NULL}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_3' || '/' || gen_random_uuid() || '/insurance.pdf' as path_3_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_3_insurance', jsonb_build_object('eTag', '"parity-3-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_3', 'insurance', :'path_3_insurance', 'insurance.pdf');
select 'bids/' || :'bid_3' || '/' || gen_random_uuid() || '/references.pdf' as path_3_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_3_references', jsonb_build_object('eTag', '"parity-3-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_3', 'references', :'path_3_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_3')::text, '{price_missing}', 'null item price');

-- 4: null alternate price
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_4 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_4', :'org', app.new_bid_reference(), :'bidder') returning id as bid_4 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_4', 1, '{12500000,234567}'::bigint[], '{NULL}'::bigint[], 'paper', null);
select 'bids/' || :'bid_4' || '/' || gen_random_uuid() || '/insurance.pdf' as path_4_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_4_insurance', jsonb_build_object('eTag', '"parity-4-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_4', 'insurance', :'path_4_insurance', 'insurance.pdf');
select 'bids/' || :'bid_4' || '/' || gen_random_uuid() || '/references.pdf' as path_4_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_4_references', jsonb_build_object('eTag', '"parity-4-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_4', 'references', :'path_4_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_4')::text, '{price_missing}', 'null alternate price');

-- 5: empty price arrays are price_missing
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_5 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_5', :'org', app.new_bid_reference(), :'bidder') returning id as bid_5 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_5', 1, '{}'::bigint[], '{}'::bigint[], 'paper', null);
select 'bids/' || :'bid_5' || '/' || gen_random_uuid() || '/insurance.pdf' as path_5_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_5_insurance', jsonb_build_object('eTag', '"parity-5-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_5', 'insurance', :'path_5_insurance', 'insurance.pdf');
select 'bids/' || :'bid_5' || '/' || gen_random_uuid() || '/references.pdf' as path_5_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_5_references', jsonb_build_object('eTag', '"parity-5-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_5', 'references', :'path_5_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_5')::text, '{price_missing}', 'empty price arrays are price_missing');

-- 6: empty item array only
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_6 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_6', :'org', app.new_bid_reference(), :'bidder') returning id as bid_6 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_6', 1, '{}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_6' || '/' || gen_random_uuid() || '/insurance.pdf' as path_6_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_6_insurance', jsonb_build_object('eTag', '"parity-6-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_6', 'insurance', :'path_6_insurance', 'insurance.pdf');
select 'bids/' || :'bid_6' || '/' || gen_random_uuid() || '/references.pdf' as path_6_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_6_references', jsonb_build_object('eTag', '"parity-6-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_6', 'references', :'path_6_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_6')::text, '{price_missing}', 'empty item array only');

-- 7: too many item prices
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_7 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_7', :'org', app.new_bid_reference(), :'bidder') returning id as bid_7 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_7', 1, '{1,2,3}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_7' || '/' || gen_random_uuid() || '/insurance.pdf' as path_7_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_7_insurance', jsonb_build_object('eTag', '"parity-7-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_7', 'insurance', :'path_7_insurance', 'insurance.pdf');
select 'bids/' || :'bid_7' || '/' || gen_random_uuid() || '/references.pdf' as path_7_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_7_references', jsonb_build_object('eTag', '"parity-7-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_7', 'references', :'path_7_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_7')::text, '{price_count}', 'too many item prices');

-- 8: too few item prices
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_8 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_8', :'org', app.new_bid_reference(), :'bidder') returning id as bid_8 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_8', 1, '{1}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_8' || '/' || gen_random_uuid() || '/insurance.pdf' as path_8_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_8_insurance', jsonb_build_object('eTag', '"parity-8-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_8', 'insurance', :'path_8_insurance', 'insurance.pdf');
select 'bids/' || :'bid_8' || '/' || gen_random_uuid() || '/references.pdf' as path_8_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_8_references', jsonb_build_object('eTag', '"parity-8-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_8', 'references', :'path_8_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_8')::text, '{price_count}', 'too few item prices');

-- 9: too many alternate prices
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_9 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_9', :'org', app.new_bid_reference(), :'bidder') returning id as bid_9 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_9', 1, '{12500000,234567}'::bigint[], '{1,2}'::bigint[], 'paper', null);
select 'bids/' || :'bid_9' || '/' || gen_random_uuid() || '/insurance.pdf' as path_9_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_9_insurance', jsonb_build_object('eTag', '"parity-9-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_9', 'insurance', :'path_9_insurance', 'insurance.pdf');
select 'bids/' || :'bid_9' || '/' || gen_random_uuid() || '/references.pdf' as path_9_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_9_references', jsonb_build_object('eTag', '"parity-9-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_9', 'references', :'path_9_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_9')::text, '{price_count}', 'too many alternate prices');

-- 10: alternate prices where the schedule has none
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_10 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_10', :'org', app.new_bid_reference(), :'bidder') returning id as bid_10 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_10', 1, '{12500000,234567}'::bigint[], '{1}'::bigint[], 'paper', null);
select 'bids/' || :'bid_10' || '/' || gen_random_uuid() || '/insurance.pdf' as path_10_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_10_insurance', jsonb_build_object('eTag', '"parity-10-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_10', 'insurance', :'path_10_insurance', 'insurance.pdf');
select 'bids/' || :'bid_10' || '/' || gen_random_uuid() || '/references.pdf' as path_10_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_10_references', jsonb_build_object('eTag', '"parity-10-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_10', 'references', :'path_10_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_10')::text, '{price_count}', 'alternate prices where the schedule has none');

-- 11: empty alternates are fine when the schedule has none
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_11 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_11', :'org', app.new_bid_reference(), :'bidder') returning id as bid_11 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_11', 1, '{12500000,234567}'::bigint[], '{}'::bigint[], 'paper', null);
select 'bids/' || :'bid_11' || '/' || gen_random_uuid() || '/insurance.pdf' as path_11_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_11_insurance', jsonb_build_object('eTag', '"parity-11-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_11', 'insurance', :'path_11_insurance', 'insurance.pdf');
select 'bids/' || :'bid_11' || '/' || gen_random_uuid() || '/references.pdf' as path_11_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_11_references', jsonb_build_object('eTag', '"parity-11-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_11', 'references', :'path_11_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_11')::text, '{}', 'empty alternates are fine when the schedule has none');

-- 12: count and missing together
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_12 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_12', :'org', app.new_bid_reference(), :'bidder') returning id as bid_12 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_12', 1, '{1,2,3}'::bigint[], '{NULL}'::bigint[], 'paper', null);
select 'bids/' || :'bid_12' || '/' || gen_random_uuid() || '/insurance.pdf' as path_12_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_12_insurance', jsonb_build_object('eTag', '"parity-12-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_12', 'insurance', :'path_12_insurance', 'insurance.pdf');
select 'bids/' || :'bid_12' || '/' || gen_random_uuid() || '/references.pdf' as path_12_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_12_references', jsonb_build_object('eTag', '"parity-12-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_12', 'references', :'path_12_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_12')::text, '{price_count,price_missing}', 'count and missing together');

-- 13: count on one array, empty on the other
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_13 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_13', :'org', app.new_bid_reference(), :'bidder') returning id as bid_13 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_13', 1, '{1,2,3}'::bigint[], '{}'::bigint[], 'paper', null);
select 'bids/' || :'bid_13' || '/' || gen_random_uuid() || '/insurance.pdf' as path_13_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_13_insurance', jsonb_build_object('eTag', '"parity-13-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_13', 'insurance', :'path_13_insurance', 'insurance.pdf');
select 'bids/' || :'bid_13' || '/' || gen_random_uuid() || '/references.pdf' as path_13_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_13_references', jsonb_build_object('eTag', '"parity-13-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_13', 'references', :'path_13_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_13')::text, '{price_count,price_missing}', 'count on one array, empty on the other');

-- 14: missing insurance upload
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_14 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_14', :'org', app.new_bid_reference(), :'bidder') returning id as bid_14 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_14', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_14' || '/' || gen_random_uuid() || '/references.pdf' as path_14_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_14_references', jsonb_build_object('eTag', '"parity-14-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_14', 'references', :'path_14_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_14')::text, '{upload_missing}', 'missing insurance upload');

-- 15: missing optional section upload
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_15 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_15', :'org', app.new_bid_reference(), :'bidder') returning id as bid_15 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_15', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_15' || '/' || gen_random_uuid() || '/insurance.pdf' as path_15_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_15_insurance', jsonb_build_object('eTag', '"parity-15-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_15', 'insurance', :'path_15_insurance', 'insurance.pdf');
select is(app.bid_draft_problems(:'bid_15')::text, '{upload_missing}', 'missing optional section upload');

-- 16: no uploads at all
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_16 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_16', :'org', app.new_bid_reference(), :'bidder') returning id as bid_16 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_16', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select is(app.bid_draft_problems(:'bid_16')::text, '{upload_missing}', 'no uploads at all');

-- 17: electronic bond without the bond file is curable after submit
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_17 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_17', :'org', app.new_bid_reference(), :'bidder') returning id as bid_17 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_17', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'electronic', null);
select 'bids/' || :'bid_17' || '/' || gen_random_uuid() || '/insurance.pdf' as path_17_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_17_insurance', jsonb_build_object('eTag', '"parity-17-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_17', 'insurance', :'path_17_insurance', 'insurance.pdf');
select 'bids/' || :'bid_17' || '/' || gen_random_uuid() || '/references.pdf' as path_17_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_17_references', jsonb_build_object('eTag', '"parity-17-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_17', 'references', :'path_17_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_17')::text, '{}', 'electronic bond without the bond file is curable after submit');

-- 18: electronic bond without the bond file, insurance still missing
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_18 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_18', :'org', app.new_bid_reference(), :'bidder') returning id as bid_18 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_18', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'electronic', null);
select 'bids/' || :'bid_18' || '/' || gen_random_uuid() || '/references.pdf' as path_18_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_18_references', jsonb_build_object('eTag', '"parity-18-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_18', 'references', :'path_18_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_18')::text, '{upload_missing}', 'electronic bond without the bond file, insurance still missing');

-- 19: electronic bond without the bond file, no bond choice is not the same
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_19 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_19', :'org', app.new_bid_reference(), :'bidder') returning id as bid_19 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_19', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], null, null);
select 'bids/' || :'bid_19' || '/' || gen_random_uuid() || '/insurance.pdf' as path_19_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_19_insurance', jsonb_build_object('eTag', '"parity-19-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_19', 'insurance', :'path_19_insurance', 'insurance.pdf');
select 'bids/' || :'bid_19' || '/' || gen_random_uuid() || '/references.pdf' as path_19_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_19_references', jsonb_build_object('eTag', '"parity-19-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_19', 'references', :'path_19_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_19')::text, '{bond_choice_missing}', 'electronic bond without the bond file, no bond choice is not the same');

-- 20: extra bond file with a paper choice is not an issue
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_20 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_20', :'org', app.new_bid_reference(), :'bidder') returning id as bid_20 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_20', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_20' || '/' || gen_random_uuid() || '/insurance.pdf' as path_20_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_20_insurance', jsonb_build_object('eTag', '"parity-20-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_20', 'insurance', :'path_20_insurance', 'insurance.pdf');
select 'bids/' || :'bid_20' || '/' || gen_random_uuid() || '/references.pdf' as path_20_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_20_references', jsonb_build_object('eTag', '"parity-20-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_20', 'references', :'path_20_references', 'references.pdf');
select 'bids/' || :'bid_20' || '/' || gen_random_uuid() || '/bid_bond.pdf' as path_20_bid_bond \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_20_bid_bond', jsonb_build_object('eTag', '"parity-20-bid_bond"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_20', 'bid_bond', :'path_20_bid_bond', 'bid_bond.pdf');
select is(app.bid_draft_problems(:'bid_20')::text, '{}', 'extra bond file with a paper choice is not an issue');

-- 21: no bond choice at $150,000.00
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_21 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_21', :'org', app.new_bid_reference(), :'bidder') returning id as bid_21 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_21', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], null, null);
select 'bids/' || :'bid_21' || '/' || gen_random_uuid() || '/insurance.pdf' as path_21_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_21_insurance', jsonb_build_object('eTag', '"parity-21-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_21', 'insurance', :'path_21_insurance', 'insurance.pdf');
select 'bids/' || :'bid_21' || '/' || gen_random_uuid() || '/references.pdf' as path_21_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_21_references', jsonb_build_object('eTag', '"parity-21-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_21', 'references', :'path_21_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_21')::text, '{bond_choice_missing}', 'no bond choice at $150,000.00');

-- 22: bond choice below the threshold
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":14999999,"optionalSections":["references"]}'::jsonb) as sol_22 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_22', :'org', app.new_bid_reference(), :'bidder') returning id as bid_22 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_22', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_22' || '/' || gen_random_uuid() || '/insurance.pdf' as path_22_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_22_insurance', jsonb_build_object('eTag', '"parity-22-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_22', 'insurance', :'path_22_insurance', 'insurance.pdf');
select 'bids/' || :'bid_22' || '/' || gen_random_uuid() || '/references.pdf' as path_22_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_22_references', jsonb_build_object('eTag', '"parity-22-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_22', 'references', :'path_22_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_22')::text, '{bond_not_required}', 'bond choice below the threshold');

-- 23: electronic choice below the threshold
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":14999999,"optionalSections":["references"]}'::jsonb) as sol_23 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_23', :'org', app.new_bid_reference(), :'bidder') returning id as bid_23 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_23', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'electronic', null);
select 'bids/' || :'bid_23' || '/' || gen_random_uuid() || '/insurance.pdf' as path_23_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_23_insurance', jsonb_build_object('eTag', '"parity-23-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_23', 'insurance', :'path_23_insurance', 'insurance.pdf');
select 'bids/' || :'bid_23' || '/' || gen_random_uuid() || '/references.pdf' as path_23_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_23_references', jsonb_build_object('eTag', '"parity-23-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_23', 'references', :'path_23_references', 'references.pdf');
select 'bids/' || :'bid_23' || '/' || gen_random_uuid() || '/bid_bond.pdf' as path_23_bid_bond \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_23_bid_bond', jsonb_build_object('eTag', '"parity-23-bid_bond"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_23', 'bid_bond', :'path_23_bid_bond', 'bid_bond.pdf');
select is(app.bid_draft_problems(:'bid_23')::text, '{bond_not_required}', 'electronic choice below the threshold');

-- 24: no choice below the threshold
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":14999999,"optionalSections":["references"]}'::jsonb) as sol_24 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_24', :'org', app.new_bid_reference(), :'bidder') returning id as bid_24 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_24', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], null, null);
select 'bids/' || :'bid_24' || '/' || gen_random_uuid() || '/insurance.pdf' as path_24_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_24_insurance', jsonb_build_object('eTag', '"parity-24-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_24', 'insurance', :'path_24_insurance', 'insurance.pdf');
select 'bids/' || :'bid_24' || '/' || gen_random_uuid() || '/references.pdf' as path_24_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_24_references', jsonb_build_object('eTag', '"parity-24-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_24', 'references', :'path_24_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_24')::text, '{}', 'no choice below the threshold');

-- 25: unknown estimate is below the threshold
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":null,"optionalSections":["references"]}'::jsonb) as sol_25 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_25', :'org', app.new_bid_reference(), :'bidder') returning id as bid_25 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_25', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], null, null);
select 'bids/' || :'bid_25' || '/' || gen_random_uuid() || '/insurance.pdf' as path_25_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_25_insurance', jsonb_build_object('eTag', '"parity-25-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_25', 'insurance', :'path_25_insurance', 'insurance.pdf');
select 'bids/' || :'bid_25' || '/' || gen_random_uuid() || '/references.pdf' as path_25_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_25_references', jsonb_build_object('eTag', '"parity-25-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_25', 'references', :'path_25_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_25')::text, '{}', 'unknown estimate is below the threshold');

-- 26: several optional sections in solicitation order
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":14999999,"optionalSections":["qualifications","current_work"]}'::jsonb) as sol_26 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_26', :'org', app.new_bid_reference(), :'bidder') returning id as bid_26 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_26', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], null, null);
select 'bids/' || :'bid_26' || '/' || gen_random_uuid() || '/insurance.pdf' as path_26_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_26_insurance', jsonb_build_object('eTag', '"parity-26-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_26', 'insurance', :'path_26_insurance', 'insurance.pdf');
select 'bids/' || :'bid_26' || '/' || gen_random_uuid() || '/qualifications.pdf' as path_26_qualifications \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_26_qualifications', jsonb_build_object('eTag', '"parity-26-qualifications"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_26', 'qualifications', :'path_26_qualifications', 'qualifications.pdf');
select is(app.bid_draft_problems(:'bid_26')::text, '{upload_missing}', 'several optional sections in solicitation order');

-- 27: everything wrong at once
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":15000000,"optionalSections":["references"]}'::jsonb) as sol_27 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_27', :'org', app.new_bid_reference(), :'bidder') returning id as bid_27 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_27', 1, '{1,2,3}'::bigint[], '{NULL}'::bigint[], null, null);
select is(app.bid_draft_problems(:'bid_27')::text, '{price_count,price_missing,upload_missing,bond_choice_missing}', 'everything wrong at once');

-- 28: apprentice answer missing at $1,000,000.00
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":100000000,"optionalSections":["references"]}'::jsonb) as sol_28 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_28', :'org', app.new_bid_reference(), :'bidder') returning id as bid_28 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_28', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', null);
select 'bids/' || :'bid_28' || '/' || gen_random_uuid() || '/insurance.pdf' as path_28_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_28_insurance', jsonb_build_object('eTag', '"parity-28-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_28', 'insurance', :'path_28_insurance', 'insurance.pdf');
select 'bids/' || :'bid_28' || '/' || gen_random_uuid() || '/references.pdf' as path_28_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_28_references', jsonb_build_object('eTag', '"parity-28-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_28', 'references', :'path_28_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_28')::text, '{apprentice_missing}', 'apprentice answer missing at $1,000,000.00');

-- 29: apprentice answered below $1,000,000.00
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":99999999,"optionalSections":["references"]}'::jsonb) as sol_29 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_29', :'org', app.new_bid_reference(), :'bidder') returning id as bid_29 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_29', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', true);
select 'bids/' || :'bid_29' || '/' || gen_random_uuid() || '/insurance.pdf' as path_29_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_29_insurance', jsonb_build_object('eTag', '"parity-29-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_29', 'insurance', :'path_29_insurance', 'insurance.pdf');
select 'bids/' || :'bid_29' || '/' || gen_random_uuid() || '/references.pdf' as path_29_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_29_references', jsonb_build_object('eTag', '"parity-29-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_29', 'references', :'path_29_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_29')::text, '{apprentice_not_required}', 'apprentice answered below $1,000,000.00');

-- 30: apprentice answered no at $1,000,000.00
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":100000000,"optionalSections":["references"]}'::jsonb) as sol_30 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_30', :'org', app.new_bid_reference(), :'bidder') returning id as bid_30 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_30', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', false);
select 'bids/' || :'bid_30' || '/' || gen_random_uuid() || '/insurance.pdf' as path_30_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_30_insurance', jsonb_build_object('eTag', '"parity-30-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_30', 'insurance', :'path_30_insurance', 'insurance.pdf');
select 'bids/' || :'bid_30' || '/' || gen_random_uuid() || '/references.pdf' as path_30_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_30_references', jsonb_build_object('eTag', '"parity-30-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_30', 'references', :'path_30_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_30')::text, '{}', 'apprentice answered no at $1,000,000.00');

-- 31: apprentice answered yes at $1,000,000.00
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":100000000,"optionalSections":["references"]}'::jsonb) as sol_31 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_31', :'org', app.new_bid_reference(), :'bidder') returning id as bid_31 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_31', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], 'paper', true);
select 'bids/' || :'bid_31' || '/' || gen_random_uuid() || '/insurance.pdf' as path_31_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_31_insurance', jsonb_build_object('eTag', '"parity-31-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_31', 'insurance', :'path_31_insurance', 'insurance.pdf');
select 'bids/' || :'bid_31' || '/' || gen_random_uuid() || '/references.pdf' as path_31_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_31_references', jsonb_build_object('eTag', '"parity-31-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_31', 'references', :'path_31_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_31')::text, '{}', 'apprentice answered yes at $1,000,000.00');

-- 32: bond and apprentice problems together, bond first
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":100000000,"optionalSections":["references"]}'::jsonb) as sol_32 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_32', :'org', app.new_bid_reference(), :'bidder') returning id as bid_32 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_32', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], null, null);
select 'bids/' || :'bid_32' || '/' || gen_random_uuid() || '/insurance.pdf' as path_32_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_32_insurance', jsonb_build_object('eTag', '"parity-32-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_32', 'insurance', :'path_32_insurance', 'insurance.pdf');
select 'bids/' || :'bid_32' || '/' || gen_random_uuid() || '/references.pdf' as path_32_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_32_references', jsonb_build_object('eTag', '"parity-32-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_32', 'references', :'path_32_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_32')::text, '{bond_choice_missing,apprentice_missing}', 'bond and apprentice problems together, bond first');

-- 33: unknown estimate never asks for an apprentice answer
select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', '{"schedule":{"items":[{"name":"Item 1","description":""},{"name":"Item 2","description":""}],"alternates":[{"kind":"deductive","description":"Alternate 1"}]},"estimateCents":null,"optionalSections":["references"]}'::jsonb) as sol_33 \gset
insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_33', :'org', app.new_bid_reference(), :'bidder') returning id as bid_33 \gset
insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_33', 1, '{12500000,234567}'::bigint[], '{1500000}'::bigint[], null, false);
select 'bids/' || :'bid_33' || '/' || gen_random_uuid() || '/insurance.pdf' as path_33_insurance \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_33_insurance', jsonb_build_object('eTag', '"parity-33-insurance"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_33', 'insurance', :'path_33_insurance', 'insurance.pdf');
select 'bids/' || :'bid_33' || '/' || gen_random_uuid() || '/references.pdf' as path_33_references \gset
insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_33_references', jsonb_build_object('eTag', '"parity-33-references"', 'size', 1024));
insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_33', 'references', :'path_33_references', 'references.pdf');
select is(app.bid_draft_problems(:'bid_33')::text, '{apprentice_not_required}', 'unknown estimate never asks for an apprentice answer');

select * from finish();
rollback;
