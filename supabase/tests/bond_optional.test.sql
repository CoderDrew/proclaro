-- 0017: the bid bond may be cured after submit (slice 2b, Task 3b, Ruling 7). An electronic choice may be submitted
-- without the bond file; after close the bid's cure is pending. Other required uploads still block submit, and the
-- bond choice itself stays required.
begin;

select plan(9);

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-000000000bd1', 'BO Agency', 'agency');
\set agency '00000000-0000-0000-0000-000000000bd1'
select tests.make_user('bo.author@test.test', :'agency') as author \gset
select tests.make_bidder('bo.bidder@test.test', 'BO Bidder') as bidder \gset
select tests.make_bidder('bo.other@test.test', 'BO Other Bidder') as other \gset
select tests.make_bidder('bo.empty@test.test', 'BO Empty Bidder') as empty_b \gset

select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 day',
  '{"estimateCents": 15000000, "optionalSections": []}'::jsonb) as sol \gset

create function tests.bo_error(p_sql text)
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
-- Fill a draft as the calling bidder: prices and the given bond choice; insurance attached only when asked.
create function tests.bo_fill(p_bid uuid, p_choice public.bid_bond_choice, p_insurance boolean)
returns void
language plpgsql
as $$
declare
  v_ins text := 'bids/' || p_bid || '/' || gen_random_uuid() || '/ins.pdf';
begin
  update public.bid_drafts
     set item_cents = '{12500000,234567}', alternate_cents = '{1500000}', bid_bond_choice = p_choice
   where bid_id = p_bid;
  if p_insurance then
    insert into storage.objects (bucket_id, name, metadata) values
      ('bid-files', v_ins, jsonb_build_object('eTag', '"bo-ins"', 'size', 2048, 'mimetype', 'application/pdf'));
    insert into public.bid_draft_files (bid_id, slot, path, file_name) values (p_bid, 'insurance', v_ins, 'ins.pdf');
  end if;
end;
$$;
grant execute on function tests.bo_error(text), tests.bo_fill(uuid, public.bid_bond_choice, boolean)
  to anon, authenticated, service_role;

select tests.act_as(:'bidder');
select public.start_bid(:'sol') as bid \gset
select tests.bo_fill(:'bid', 'electronic', true);
select tests.act_as(:'other');
select public.start_bid(:'sol') as bid_ins \gset
select tests.bo_fill(:'bid_ins', 'electronic', false);
select tests.act_as(:'empty_b');
select public.start_bid(:'sol') as bid_none \gset

reset role;
select is(app.bid_draft_problems(:'bid'), array[]::text[],
  'electronic choice, no bond file, insurance attached: no problems');
select ok((select count(*) = 0 from public.bid_draft_files where bid_id = :'bid' and slot = 'bid_bond'),
  'the draft really has no bid_bond file');
select is(app.bid_draft_problems(:'bid_ins'), array['upload_missing'],
  'electronic choice with insurance missing: upload_missing');
select is(app.bid_draft_problems(:'bid_none'), array['price_missing', 'upload_missing', 'bond_choice_missing'],
  'an empty draft still reports the bond choice (bond_choice_missing unchanged)');

select tests.act_as(:'other');
select is(tests.bo_error(format('select * from public.submit_bid(%L)', :'bid_ins')),
  'P0001|invalid_bid|upload_missing', 'submit_bid still refuses a bid missing the insurance upload');

select tests.act_as(:'bidder');
select is(tests.bo_error(format('select * from public.submit_bid(%L)', :'bid')), 'ok',
  'submit_bid accepts electronic with no bond file on a bonds-required solicitation');
reset role;
select is((select count(*)::int from public.bid_version_files f join public.bid_versions v on v.id = f.version_id
            where v.bid_id = :'bid' and f.slot = 'bid_bond'), 0,
  'the sealed version has no bond file');

-- Close the solicitation (the cure deadline freezes from the due time).
select tests.set_bid_due(:'sol', now() - interval '1 hour');
select is((select status from app.bond_cure(:'bid')), 'pending',
  'after close the electronic bid with no bond file is in the cure: pending');
select is((select due_at from app.bond_cure(:'bid')),
  app.cure_due_at((select bid_due_at from public.solicitations where id = :'sol')),
  'its cure deadline is app.cure_due_at(bid_due_at)');

select * from finish();
rollback;
