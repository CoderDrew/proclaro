-- 0024: my_bid_outcome, the bidder's own posted outcome (slice 2b, Task 11).
begin;

select plan(20);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

create function tests.bo2_error(p_sql text)
returns text
language plpgsql
as $$
declare
  v_state text; v_msg text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return v_state || '|' || v_msg;
end;
$$;
grant execute on function tests.bo2_error(text) to anon, authenticated, service_role;

insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000008f1', 'BO Office', 'office'),
  ('00000000-0000-0000-0000-0000000008a1', 'BO Agency', 'agency');
\set agency '00000000-0000-0000-0000-0000000008a1'
\set office '00000000-0000-0000-0000-0000000008f1'
select tests.make_user('bo.author@test.test', :'agency') as author \gset
select tests.make_user('bo.r1@test.test', :'office') as r1 \gset
select tests.make_bidder('bo.a@test.test', 'BO Bidder A') as bidder_a \gset
select tests.make_bidder('bo.b@test.test', 'BO Bidder B') as bidder_b \gset

select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour',
  jsonb_build_object('fundingAmountCents', 15000000, 'schedule', jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object('name', 'Base bid', 'description', 'Site work'),
                               jsonb_build_object('name', 'Item 2', 'description', 'Roofing')),
    'alternates', '[]'::jsonb))) as sol \gset
select tests.make_closed_bid(:'sol', :'bidder_a', '{3000000,1000000}', '{}', 'paper', null, true, true) as bid_a \gset
select tests.make_closed_bid(:'sol', :'bidder_b', '{3500000,1000000}', '{}', 'paper', null, true, true) as bid_b \gset

select tests.act_as(:'r1');
select public.set_bid_outcome(:'bid_a', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bid_b', 'non_responsive', 'wrong_form', 'Wrong form');

select has_function('public', 'my_bid_outcome', array['uuid'], 'public.my_bid_outcome exists');
select ok(has_function_privilege('authenticated', 'public.my_bid_outcome(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.my_bid_outcome(uuid)', 'execute')
      and not has_function_privilege('service_role', 'public.my_bid_outcome(uuid)', 'execute')
      and not has_function_privilege('public', 'public.my_bid_outcome(uuid)', 'execute'),
  'my_bid_outcome: authenticated only');

-- Before posting: no row for either owner.
select tests.act_as(:'bidder_a');
select is((select count(*)::int from public.my_bid_outcome(:'bid_a')), 0, 'before posting: owner A gets no row');
select tests.act_as(:'bidder_b');
select is((select count(*)::int from public.my_bid_outcome(:'bid_b')), 0, 'before posting: owner B gets no row');

-- Post the recap through the fallback.
select tests.act_as(:'r1');
select public.post_recap_alone(:'sol');

select tests.act_as(:'bidder_a');
select is((select status from public.my_bid_outcome(:'bid_a')), 'accepted', 'after posting: owner A sees accepted');
select is((select recap_kind::text from public.my_bid_outcome(:'bid_a')), 'recap',
  'after posting: recap_kind is recap (0025)');
select tests.act_as(:'bidder_b');
select is((select status from public.my_bid_outcome(:'bid_b')), 'non_responsive', 'after posting: owner B sees non_responsive');
select is((select reason is not null and reason <> '' from public.my_bid_outcome(:'bid_b')), true,
  'after posting: a non-responsive outcome carries its reason text');
select is(tests.bo2_error(format('select * from public.my_bid_outcome(%L)', :'bid_a')), 'P0001|not_found',
  'another bidder gets not_found');

select tests.act_as(:'r1');
select is(tests.bo2_error(format('select * from public.my_bid_outcome(%L)', :'bid_a')), 'P0001|not_authorized',
  'office is not a bidder: not_authorized');

select tests.act_as_anon();
select is(tests.bo2_error(format('select * from public.my_bid_outcome(%L)', :'bid_a')),
  '42501|permission denied for function my_bid_outcome', 'anon cannot execute it');

-- ---------------------------------------------------------------------------
-- 0025 (final review I3): flag decisions, a withdrawn bid, and the all-rejected memo.
-- ---------------------------------------------------------------------------
reset role;
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour',
  jsonb_build_object('fundingAmountCents', 15000000, 'schedule', jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object('name', 'Base bid', 'description', 'Site work'),
                               jsonb_build_object('name', 'Item 2', 'description', 'Roofing')),
    'alternates', '[]'::jsonb))) as sol_f \gset
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour',
  jsonb_build_object('fundingAmountCents', 99999999, 'schedule', jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object('name', 'Base bid', 'description', 'Site work'),
                               jsonb_build_object('name', 'Item 2', 'description', 'Roofing')),
    'alternates', '[]'::jsonb))) as sol_m \gset
select tests.make_bidder('bo.c@test.test', 'BO Bidder C') as bidder_c \gset
select tests.make_closed_bid(:'sol_f', :'bidder_a', '{3000000,1000000}', '{}', 'paper', null, true, true) as f_a \gset
select tests.make_closed_bid(:'sol_f', :'bidder_b', '{3500000,1000000}', '{}', 'paper', null, true, true) as f_b \gset
select tests.make_closed_bid(:'sol_f', :'bidder_c', '{2000000,1000000}', '{}', 'paper', null, true, true) as f_c \gset
insert into public.bid_withdrawals (bid_id, version, withdrawn_by) values (:'f_c', 1, :'bidder_c');
select tests.make_closed_bid(:'sol_m', :'bidder_a', '{60000000,40000000}', '{}', 'paper', null, true, true) as m_a \gset

select tests.act_as(:'r1');
select public.set_bid_outcome(:'f_a', 'accepted_flagged', null, 'Unit prices look unbalanced') as out_f_a \gset
select public.set_bid_outcome(:'f_b', 'accepted_flagged', null, 'Missing a subcontractor list') as out_f_b \gset
select public.send_flags_to_agency(:'sol_f');
select public.set_bid_outcome(:'m_a', 'accepted', null, 'In order');
select tests.act_as(:'author');
select public.decide_flagged_bid(:'out_f_a', 'accept', 'Prices explained');
select public.decide_flagged_bid(:'out_f_b', 'reject', 'List not provided');
select tests.act_as(:'r1');
select public.post_recap_alone(:'sol_f');
select public.post_recap_alone(:'sol_m');

select tests.act_as(:'bidder_a');
select is((select row(status, reason, recap_kind::text)::text from public.my_bid_outcome(:'f_a')),
  row('flag_accepted', 'Prices explained', 'recap')::text, 'flag accepted by the agency: flag_accepted with its reason');
select tests.act_as(:'bidder_b');
select is((select row(status, reason, recap_kind::text)::text from public.my_bid_outcome(:'f_b')),
  row('flag_rejected', 'List not provided', 'recap')::text, 'flag rejected by the agency: flag_rejected with its reason');
select tests.act_as(:'bidder_c');
select is((select count(*)::int from public.my_bid_outcome(:'f_c')), 0, 'a withdrawn bid: no outcome row after posting');
select tests.act_as(:'bidder_a');
select is((select kind::text from public.recaps where solicitation_id = :'sol_m'), 'all_rejected',
  'fixture: sol_m posted the all-rejected memo');
select is((select row(status, recap_kind::text)::text from public.my_bid_outcome(:'m_a')),
  row('accepted', 'all_rejected')::text, 'under the memo: the accepted status comes with recap_kind all_rejected');
select is((select count(*)::int from public.my_bid_outcome(:'m_a')), 1, 'under the memo: exactly one row');

select tests.act_as(:'bidder_b');
select is(tests.bo2_error(format('select * from public.my_bid_outcome(%L)', :'m_a')), 'P0001|not_found',
  'under the memo: another bidder still gets not_found');
reset role;
select is((select count(*)::int from public.bid_outcomes where solicitation_id in (:'sol_f', :'sol_m')), 3,
  'my_bid_outcome wrote nothing (only the three outcomes set above)');
select has_function('public', 'my_bid_outcome', array['uuid'], 'my_bid_outcome still takes one uuid');

select * from finish();
rollback;
