-- 0004: failed-publish cleanup deletes, and blank-argument rejection in publish_solicitation.
begin;

select plan(12);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000007f1', 'PH Office',   'office'),
  ('00000000-0000-0000-0000-0000000007a1', 'PH Agency A', 'agency');

select tests.make_user('ph.author@test.test', '00000000-0000-0000-0000-0000000007a1') as author \gset
select tests.make_user('ph.r1@test.test',     '00000000-0000-0000-0000-0000000007f1') as r1 \gset
select tests.make_user('ph.r2@test.test',     '00000000-0000-0000-0000-0000000007f1') as r2 \gset

insert into public.solicitations (id, agency_id, created_by, data)
values ('00000000-0000-0000-0000-0000000007c1', '00000000-0000-0000-0000-0000000007a1', :'author',
        tests.solicitation_data(jsonb_build_object('shortTitle', 'Cleanup')));

-- Drive the row to approved through the workflow functions.
select tests.act_as(:'author');
select public.submit_solicitation('00000000-0000-0000-0000-0000000007c1');
select tests.act_as(:'r1');
select public.start_review('00000000-0000-0000-0000-0000000007c1');
select public.send_to_check('00000000-0000-0000-0000-0000000007c1');
select tests.act_as(:'r2');
select public.approve_check('00000000-0000-0000-0000-0000000007c1');

-- The Storage API sets this flag for its own deletes; a raw SQL delete is otherwise blocked by a Storage trigger.
-- The RLS policies still decide which rows the delete can see.
select set_config('storage.allow_delete_query', 'true', true);

-- Office uploads the files a publish attempt would write.
select tests.act_as(:'r1');
insert into storage.objects (bucket_id, name) values
  ('published', 'solicitations/00000000-0000-0000-0000-0000000007c1/v1/rfb.pdf'),
  ('published', 'solicitations/00000000-0000-0000-0000-0000000007c1/v1/bid-form.pdf');

-- ---------------------------------------------------------------------------
-- Cleanup deletes: allowed for office before publish, denied to agency, denied after publish.
-- ---------------------------------------------------------------------------
select tests.act_as(:'author');
delete from storage.objects
 where bucket_id = 'published' and name = 'solicitations/00000000-0000-0000-0000-0000000007c1/v1/bid-form.pdf';
reset role;
select is((select count(*)::int from storage.objects where bucket_id = 'published'
           and name like 'solicitations/00000000-0000-0000-0000-0000000007c1/%'), 2,
  'agency cannot delete published objects');

select tests.act_as(:'r1');
select lives_ok(
  $$delete from storage.objects where bucket_id = 'published'
    and name = 'solicitations/00000000-0000-0000-0000-0000000007c1/v1/bid-form.pdf'$$,
  'office delete of an unpublished solicitation object runs');
reset role;
select is((select count(*)::int from storage.objects where bucket_id = 'published'
           and name like 'solicitations/00000000-0000-0000-0000-0000000007c1/%'), 1,
  'office deleted the object before publish');

-- ---------------------------------------------------------------------------
-- Blank arguments raise invalid_data (valid caller, approved row, so no other check intervenes).
-- ---------------------------------------------------------------------------
select tests.act_as(:'r1');
select throws_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000007c1',
    null, 'solicitations/x/v1/bid-form.pdf', '{"k":1}', now(), 15000000)$$,
  'P0001', 'invalid_data', 'null rfb path raises invalid_data');
select throws_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000007c1',
    'solicitations/x/v1/rfb.pdf', '   ', '{"k":1}', now(), 15000000)$$,
  'P0001', 'invalid_data', 'blank bid form path raises invalid_data');
select throws_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000007c1',
    '', 'solicitations/x/v1/bid-form.pdf', '{"k":1}', now(), 15000000)$$,
  'P0001', 'invalid_data', 'empty rfb path raises invalid_data');
select throws_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000007c1',
    'solicitations/x/v1/rfb.pdf', 'solicitations/x/v1/bid-form.pdf', null, now(), 15000000)$$,
  'P0001', 'invalid_data', 'null snapshot raises invalid_data');
select throws_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000007c1',
    'solicitations/x/v1/rfb.pdf', 'solicitations/x/v1/bid-form.pdf', '{}', now(), 15000000)$$,
  'P0001', 'invalid_data', 'empty snapshot raises invalid_data');
select throws_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000007c1',
    'solicitations/x/v1/rfb.pdf', 'solicitations/x/v1/bid-form.pdf', '{"k":1}', null, 15000000)$$,
  'P0001', 'invalid_data', 'null bid_due_at raises invalid_data');

reset role;
select is((select state::text from public.solicitations where id = '00000000-0000-0000-0000-0000000007c1'),
  'approved', 'rejected calls leave the row approved');

-- A valid call still publishes.
select tests.act_as(:'r1');
select lives_ok($$select public.publish_solicitation('00000000-0000-0000-0000-0000000007c1',
    'solicitations/00000000-0000-0000-0000-0000000007c1/v1/rfb.pdf',
    'solicitations/00000000-0000-0000-0000-0000000007c1/v1/bid-form.pdf',
    '{"k":1}', tests.bid_due_at((select data from public.solicitations
                                 where id = '00000000-0000-0000-0000-0000000007c1')), 15000000)$$,
  'a valid publish succeeds');

-- After publish the remaining object can no longer be deleted.
delete from storage.objects
 where bucket_id = 'published' and name = 'solicitations/00000000-0000-0000-0000-0000000007c1/v1/rfb.pdf';
reset role;
select is((select count(*)::int from storage.objects where bucket_id = 'published'
           and name = 'solicitations/00000000-0000-0000-0000-0000000007c1/v1/rfb.pdf'), 1,
  'office cannot delete a published solicitation object');

select * from finish();
rollback;
