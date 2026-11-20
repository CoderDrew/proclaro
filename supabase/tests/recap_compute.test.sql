-- 0021: the recap computed in Postgres from sealed prices (slice 2b, Task 8).
begin;

select plan(118);

select set_config('storage.allow_delete_query', 'true', true);
update public.settings set timezone = 'America/Denver' where id = 1;

-- The error a statement raises, as 'sqlstate|message', or 'ok'.
create function tests.rc_error(p_sql text)
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
grant execute on function tests.rc_error(text) to anon, authenticated, service_role;

-- One rank_recap input bid. bidId and reference are the same short label, for readable assertions.
create function tests.rc_bid(p_id text, p_base bigint, p_alts bigint[] default '{}',
                             p_resident boolean default false, p_apprentice boolean default false)
returns jsonb
language sql immutable
as $$
  select jsonb_build_object('bidId', p_id, 'reference', p_id, 'bidderName', 'Bidder ' || p_id,
                            'baseCents', p_base, 'alternateCents', to_jsonb(p_alts),
                            'resident', p_resident, 'apprentice', p_apprentice);
$$;

-- The row of a recap snapshot for one bidId.
create function tests.rc_row(p_recap jsonb, p_id text)
returns jsonb
language sql immutable
as $$
  select x from jsonb_array_elements(p_recap -> 'rows') x where x ->> 'bidId' = p_id;
$$;

-- [[bidId, rank], ...] in row order.
create function tests.rc_order(p_recap jsonb)
returns jsonb
language sql immutable
as $$
  select coalesce(jsonb_agg(jsonb_build_array(x ->> 'bidId', (x ->> 'rank')::int) order by o), '[]'::jsonb)
    from jsonb_array_elements(p_recap -> 'rows') with ordinality t(x, o);
$$;

-- ---------------------------------------------------------------------------
-- Shape and privileges
-- ---------------------------------------------------------------------------
select has_function('app', 'rank_recap', array['jsonb', 'text[]', 'bigint', 'bigint'], 'app.rank_recap exists');
select has_function('app', 'recap_lines', array['jsonb', 'text[]', 'integer[]', 'bigint'], 'app.recap_lines exists');
select has_function('app', 'recap_fits', array['jsonb', 'text[]', 'integer[]', 'bigint', 'bigint'], 'app.recap_fits exists');
select has_function('app', 'recap_bids', array['uuid', 'timestamptz'], 'app.recap_bids exists');
select has_function('app', 'build_recap', array['uuid', 'timestamptz'], 'app.build_recap exists');
select has_function('app', 'recap_blockers', array['uuid', 'timestamptz'], 'app.recap_blockers exists');
select has_function('public', 'preview_recap', array['uuid'], 'public.preview_recap exists');

select is((select array_agg(p.provolatile::text order by p.proname) from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname in ('rank_recap', 'recap_lines', 'recap_fits')),
  array['i', 'i', 'i'], 'rank_recap, recap_lines, recap_fits are immutable');
select ok((select bool_and(not p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname in ('rank_recap', 'recap_lines', 'recap_fits')),
  'the pure helpers are not security definer (they read nothing)');
select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where (n.nspname = 'app' and p.proname in ('recap_bids', 'build_recap', 'recap_blockers'))
               or (n.nspname = 'public' and p.proname = 'preview_recap')),
  'build_recap, recap_bids, recap_blockers, preview_recap: security definer with an empty search_path');

select ok(not has_function_privilege('authenticated', 'app.rank_recap(jsonb, text[], bigint, bigint)', 'execute')
      and not has_function_privilege('anon', 'app.rank_recap(jsonb, text[], bigint, bigint)', 'execute')
      and not has_function_privilege('service_role', 'app.rank_recap(jsonb, text[], bigint, bigint)', 'execute')
      and not has_function_privilege('authenticated', 'app.recap_lines(jsonb, text[], int[], bigint)', 'execute')
      and not has_function_privilege('authenticated', 'app.recap_fits(jsonb, text[], int[], bigint, bigint)', 'execute'),
  'the pure recap helpers: no execute for API roles');
select ok(not has_function_privilege('authenticated', 'app.build_recap(uuid, timestamptz)', 'execute')
      and not has_function_privilege('anon', 'app.build_recap(uuid, timestamptz)', 'execute')
      and not has_function_privilege('service_role', 'app.build_recap(uuid, timestamptz)', 'execute')
      and not has_function_privilege('authenticated', 'app.recap_bids(uuid, timestamptz)', 'execute')
      and not has_function_privilege('service_role', 'app.recap_bids(uuid, timestamptz)', 'execute')
      and not has_function_privilege('authenticated', 'app.recap_blockers(uuid, timestamptz)', 'execute')
      and not has_function_privilege('service_role', 'app.recap_blockers(uuid, timestamptz)', 'execute'),
  'build_recap, recap_bids, recap_blockers: no execute for API roles');
select ok(has_function_privilege('authenticated', 'public.preview_recap(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.preview_recap(uuid)', 'execute')
      and not has_function_privilege('service_role', 'public.preview_recap(uuid)', 'execute')
      and not has_function_privilege('public', 'public.preview_recap(uuid)', 'execute'),
  'preview_recap: authenticated only');

-- ---------------------------------------------------------------------------
-- rank_recap. Unless stated: no alternates, funding 200,000,000, estimate 150,000,000, not resident, no apprentice.
-- ---------------------------------------------------------------------------

-- Review Focus 2: resident 5% boundary.
select app.rank_recap(jsonb_build_array(tests.rc_bid('N', 100000000), tests.rc_bid('R', 105000000, '{}', true)),
                      '{}', 200000000, 150000000) as r \gset
select is((tests.rc_row(:'r', 'R') ->> 'rank')::int, 1, 'F2: resident at exactly 105% ranks 1');
select is((tests.rc_row(:'r', 'R') ->> 'residentPreferred')::boolean, true, 'F2: resident at exactly 105% is preferred');
select is(:'r'::jsonb ->> 'expectedWinnerBidId', 'R', 'F2: expected winner is the resident');

select app.rank_recap(jsonb_build_array(tests.rc_bid('N', 100000000), tests.rc_bid('R', 105000001, '{}', true)),
                      '{}', 200000000, 150000000) as r \gset
select is((tests.rc_row(:'r', 'N') ->> 'rank')::int, 1, 'F2: resident one cent over 105% -> non-resident ranks 1');
select is((tests.rc_row(:'r', 'R') ->> 'rank')::int, 2, 'F2: resident one cent over 105% ranks 2');
select is((tests.rc_row(:'r', 'R') ->> 'residentPreferred')::boolean, false, 'F2: one cent over -> not preferred');

select app.rank_recap(jsonb_build_array(tests.rc_bid('N', 100000000), tests.rc_bid('R', 104000000)),
                      '{}', 200000000, 150000000) as r \gset
select is(tests.rc_order(:'r'), '[["N", 1], ["R", 2]]'::jsonb,
  'unverified resident (resident false) gets no preference: N ranks 1');

select app.rank_recap(jsonb_build_array(tests.rc_bid('N1', 100000000), tests.rc_bid('N2', 103000000),
                                        tests.rc_bid('R', 104000000, '{}', true)),
                      '{}', 200000000, 150000000) as r \gset
select is(tests.rc_order(:'r'), '[["R", 1], ["N1", 2], ["N2", 3]]'::jsonb,
  'resident within 5% of the lowest non-resident ranks 1, then non-residents ascending');

select app.rank_recap(jsonb_build_array(tests.rc_bid('R1', 103000000, '{}', true),
                                        tests.rc_bid('R2', 100000000, '{}', true)),
                      '{}', 200000000, 150000000) as r \gset
select is(tests.rc_order(:'r'), '[["R2", 1], ["R1", 2]]'::jsonb, 'all residents: plain ascending order');
select is((select count(*)::int from jsonb_array_elements(:'r'::jsonb -> 'rows') x
            where (x ->> 'residentPreferred')::boolean), 0, 'all residents: nobody is preferred');

-- Review Focus 3: apprentice credit only on $1M+ jobs and only with the commitment.
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{}', false, true), tests.rc_bid('B', 99500000)),
                      '{}', 200000000, 100000000) as r \gset
select is((tests.rc_row(:'r', 'A') ->> 'rank')::int, 1, 'F3: estimate 100,000,000: credited A ranks 1');
select is((tests.rc_row(:'r', 'A') ->> 'apprenticeCredit')::boolean, true, 'F3: estimate 100,000,000: A credited');
select is((tests.rc_row(:'r', 'A') ->> 'evaluatedCents')::bigint, 99000000::bigint, 'F3: A evaluatedCents 99,000,000');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 100000000::bigint, 'F3: A totalCents stays 100,000,000');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{}', false, true), tests.rc_bid('B', 99500000)),
                      '{}', 200000000, 99999999) as r \gset
select is((tests.rc_row(:'r', 'B') ->> 'rank')::int, 1, 'F3: estimate 99,999,999: B ranks 1');
select is((tests.rc_row(:'r', 'A') ->> 'apprenticeCredit')::boolean, false, 'F3: estimate 99,999,999: A not credited');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000), tests.rc_bid('B', 99500000)),
                      '{}', 200000000, 100000000) as r \gset
select is((tests.rc_row(:'r', 'B') ->> 'rank')::int, 1, 'F3: no commitment: B ranks 1');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{}', false, true), tests.rc_bid('B', 99000000)),
                      '{}', 200000000, 100000000) as r \gset
select is(tests.rc_order(:'r'), '[["A", 1], ["B", 1]]'::jsonb, 'F3: exact evaluated tie: both rank 1');
select ok((tests.rc_row(:'r', 'A') ->> 'tied')::boolean and (tests.rc_row(:'r', 'B') ->> 'tied')::boolean,
  'F3: exact evaluated tie: both tied');
select ok(:'r'::jsonb -> 'expectedWinnerBidId' = 'null'::jsonb and not (:'r'::jsonb ->> 'winnerOverFunding')::boolean,
  'F3: exact evaluated tie: no expected winner, winnerOverFunding false');

-- Review Focus 4: additive alternates at the funding boundary.
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{10000000,1}'),
                                        tests.rc_bid('B', 101000000, '{9500000,5}')),
                      '{additive,additive}', 110000000, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[1]'::jsonb, 'F4: funding 110,000,000 -> alternate 1 only');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 110000000::bigint, 'F4: A totalCents 110,000,000');
select is((tests.rc_row(:'r', 'A') ->> 'rank')::int, 1, 'F4: A ranks 1');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{10000000,1}'),
                                        tests.rc_bid('B', 101000000, '{9500000,5}')),
                      '{additive,additive}', 109999999, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[]'::jsonb, 'F4: funding 109,999,999 -> no alternate');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 100000000::bigint, 'F4: A totalCents 100,000,000');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{10000000,1}'),
                                        tests.rc_bid('B', 101000000, '{9500000,5}')),
                      '{additive,additive}', 200000000, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[1, 2]'::jsonb, 'F4: funding 200,000,000 -> alternates 1 and 2');
select is(tests.rc_row(:'r', 'A') -> 'alternateCents', '[10000000, 1]'::jsonb, 'rows carry the sealed alternate cents');

-- Stop rule: once an additive does not fit, later ones are never considered.
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{20000000,1}')),
                      '{additive,additive}', 110000000, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[]'::jsonb, 'stop rule: alternate 2 is not taken after 1 fails');

-- Deductive alternates (Ruling 4): only when the base does not fit.
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{5000000}')),
                      '{deductive}', 200000000, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[]'::jsonb, 'deductive: base fits -> not taken');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 100000000::bigint, 'deductive: base fits -> total 100,000,000');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{5000000}')),
                      '{deductive}', 97000000, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[1]'::jsonb, 'deductive: over funding -> taken');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 95000000::bigint, 'deductive: total 95,000,000');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{2000000,5000000}')),
                      '{deductive,deductive}', 98000000, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[1]'::jsonb, 'two deductives, funding 98,000,000 -> [1]');
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{2000000,5000000}')),
                      '{deductive,deductive}', 97999999, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[1, 2]'::jsonb, 'two deductives, funding 97,999,999 -> [1,2]');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 93000000::bigint, 'two deductives: total 93,000,000');
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{2000000,5000000}')),
                      '{deductive,deductive}', 92999999, 150000000) as r \gset
select is(:'r'::jsonb ->> 'kind', 'all_rejected', 'two deductives, funding 92,999,999 -> all_rejected');
select is(:'r'::jsonb ->> 'reason', 'over_funding', 'two deductives, funding 92,999,999 -> over_funding');
select ok(:'r'::jsonb -> 'rows' = '[]'::jsonb and :'r'::jsonb -> 'selectedAlternates' = '[]'::jsonb,
  'over_funding after deductives: no rows, no selected alternates');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{5000000,3000000}')),
                      '{deductive,additive}', 99000000, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[1, 2]'::jsonb, 'mixed, funding 99,000,000 -> [1,2]');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 98000000::bigint, 'mixed: total 98,000,000');
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{5000000,3000000}')),
                      '{deductive,additive}', 97999999, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[1]'::jsonb, 'mixed, funding 97,999,999 -> [1]');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 95000000::bigint, 'mixed: total 95,000,000');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{1}'), tests.rc_bid('B', 100000001, '{1}')),
                      '{deductive}', 99999999, 150000000) as r \gset
select is(:'r'::jsonb ->> 'kind', 'recap', 'one-cent deductive brings the lowest bid within funding -> recap');
select is(:'r'::jsonb -> 'selectedAlternates', '[1]'::jsonb, 'one-cent deductive selected');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 99999999::bigint, 'one-cent deductive: A total 99,999,999');

-- Selection ignores the resident preference; the ranking applies it.
select app.rank_recap(jsonb_build_array(tests.rc_bid('N', 100000000, '{10000000}'),
                                        tests.rc_bid('R', 104000000, '{10000000}', true)),
                      '{additive}', 110000000, 150000000) as r \gset
select is(:'r'::jsonb -> 'selectedAlternates', '[1]'::jsonb, 'selection uses the lowest evaluated bid (N), not R');
select is((tests.rc_row(:'r', 'R') ->> 'rank')::int, 1, 'ranking applies the preference: R ranks 1');
select is((:'r'::jsonb ->> 'winnerOverFunding')::boolean, true, 'R total 114,000,000 > funding: winnerOverFunding');

-- Revised Ruling 9: the memo only when no bid fits. Credit makes A (base 100,000,000) the lowest evaluated
-- (9,900,000,000 vs B's 9,950,000,000) though only B's base 99,500,000 fits 99,600,000 -> recap, A wins over funding.
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{}', false, true), tests.rc_bid('B', 99500000)),
                      '{}', 99600000, 150000000) as r \gset
select is(:'r'::jsonb ->> 'kind', 'recap', 'R9: a bid base fits funding -> recap, not the memo');
select is(:'r'::jsonb -> 'selectedAlternates', '[]'::jsonb, 'R9: no alternates selected');
select is((tests.rc_row(:'r', 'A') ->> 'rank')::int, 1, 'R9: credited A ranks 1');
select is((:'r'::jsonb ->> 'winnerOverFunding')::boolean, true, 'R9: winnerOverFunding true (A total 100,000,000)');

-- Deductive variant. {deductive, additive}, funding 99,000,000, estimate 150,000,000:
--   A credited, base 100,000,000, alts [500,000, 10,000]; B base 99,400,000, alts [500,000, 10,000].
--   S={}:  A T 100,000,000 E 9,900,000,000; B T 99,400,000 E 9,940,000,000 -> lowest A, 100,000,000 > funding.
--   S={1}: A T  99,500,000 E 9,850,500,000; B T 98,900,000 E 9,890,000,000 -> lowest A,  99,500,000 > funding.
--   All deductives taken and still no fit; memo check: B's T(D_all) 98,900,000 <= funding -> recap with S = {1}.
--   No additive is taken, although B + alternate 2 (98,910,000) would fit.
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{500000,10000}', false, true),
                                        tests.rc_bid('B', 99400000, '{500000,10000}')),
                      '{deductive,additive}', 99000000, 150000000) as r \gset
select is(:'r'::jsonb ->> 'kind', 'recap', 'R9 deductive: B fits after deductives -> recap');
select is(:'r'::jsonb -> 'selectedAlternates', '[1]'::jsonb, 'R9 deductive: all deductives, no additive');
select is(tests.rc_order(:'r'), '[["A", 1], ["B", 2]]'::jsonb, 'R9 deductive: credited A ranks 1');
select is((tests.rc_row(:'r', 'A') ->> 'totalCents')::bigint, 99500000::bigint, 'R9 deductive: A total 99,500,000');
select is((tests.rc_row(:'r', 'B') ->> 'totalCents')::bigint, 98900000::bigint, 'R9 deductive: B total 98,900,000');
select is((:'r'::jsonb ->> 'winnerOverFunding')::boolean, true, 'R9 deductive: winnerOverFunding true');

-- Every T(b, all deductives) over funding -> memo. {deductive}: A 100,000,000 - 1,000,000 = 99,000,000;
-- B 100,500,000 - 1,000,000 = 99,500,000; funding 98,999,999.
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000, '{1000000}'), tests.rc_bid('B', 100500000, '{1000000}')),
                      '{deductive}', 98999999, 150000000) as r \gset
select is(:'r'::jsonb ->> 'reason', 'over_funding', 'R9: every total with all deductives over funding -> memo');

-- Negative totals are invalid_data: in the memo check (100 - 200 with the deductive) ...
select is(tests.rc_error($q$select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100, '{200}')), '{deductive}', 50, 1)$q$),
  'P0001|invalid_data', 'negative total with all deductives -> invalid_data');
-- ... and for the final selection (a negative additive: 100 + -200 = -100 "fits", then fails the guard).
select is(tests.rc_error($q$select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100, '{-200}')), '{additive}', 1000, 1)$q$),
  'P0001|invalid_data', 'negative total in the final selection -> invalid_data');

-- Review Focus 6: all bids rejected.
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000), tests.rc_bid('B', 100000001)),
                      '{}', 99999999, 150000000) as r \gset
select is(:'r'::jsonb ->> 'kind', 'all_rejected', 'F6: every base over funding -> all_rejected');
select is(:'r'::jsonb ->> 'reason', 'over_funding', 'F6: reason over_funding');
select is(:'r'::jsonb -> 'rows', '[]'::jsonb, 'F6: no rows (the memo discloses no bid)');
select is((:'r'::jsonb ->> 'fundingCents')::bigint, 99999999::bigint, 'F6: fundingCents carried');

select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 100000000), tests.rc_bid('B', 100000001)),
                      '{}', 100000000, 150000000) as r \gset
select is(:'r'::jsonb ->> 'kind', 'recap', 'F6: funding 100,000,000 -> recap');
select ok(:'r'::jsonb -> 'reason' = 'null'::jsonb and (:'r'::jsonb ->> 'expectedWinnerBidId') = 'A'
          and not (:'r'::jsonb ->> 'winnerOverFunding')::boolean,
  'F6: recap reason null, expected winner A within funding');

select app.rank_recap('[]', '{}', 100000000, 150000000) as r \gset
select is(:'r'::jsonb ->> 'kind', 'all_rejected', 'F6: no bids -> all_rejected');
select is(:'r'::jsonb ->> 'reason', 'no_accepted_bids', 'F6: no bids -> no_accepted_bids');

-- Competition ranking with a three-way key: 1, 1, 3; rows by rank then reference.
select app.rank_recap(jsonb_build_array(tests.rc_bid('C', 100000000), tests.rc_bid('B', 100000000),
                                        tests.rc_bid('A', 100000001)),
                      '{}', 200000000, 150000000) as r \gset
select is(tests.rc_order(:'r'), '[["B", 1], ["C", 1], ["A", 3]]'::jsonb, 'competition ranking 1,1,3; ties by reference');
select is((tests.rc_row(:'r', 'A') ->> 'tied')::boolean, false, 'rank 3 is not tied');

-- evaluatedCents rounds half-up for display only: 99 * 50 = 4950 hundredths -> 50 cents (49.5 rounds up).
select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 50, '{}', false, true)), '{}', 200000000, 100000000) as r \gset
select is((tests.rc_row(:'r', 'A') ->> 'evaluatedCents')::bigint, 50::bigint, 'evaluatedCents rounds 49.5 half-up to 50');

select is(tests.rc_error($q$select app.rank_recap(jsonb_build_array(tests.rc_bid('A', 1, '{1,2}')), '{additive}', 1, 1)$q$),
  'P0001|invalid_data', 'rank_recap: alternateCents length differs from the alternates -> invalid_data');
select is(tests.rc_error($q$select app.rank_recap('[]', '{bogus}', 1, 1)$q$),
  'P0001|invalid_data', 'rank_recap: unknown alternate kind -> invalid_data');
select is(tests.rc_error($q$select app.rank_recap('[]', '{}', null, 1)$q$),
  'P0001|invalid_data', 'rank_recap: null funding -> invalid_data');

select is((select l.total from app.recap_lines(jsonb_build_array(tests.rc_bid('A', 100, '{10,3}')),
                                               '{additive,deductive}', '{1,2}', 1) l), 107::numeric,
  'recap_lines: T = base + additive - deductive');
select is(app.recap_fits(jsonb_build_array(tests.rc_bid('A', 100), tests.rc_bid('B', 100)), '{}', '{}', 99, 1), false,
  'recap_fits: tied lowest over funding -> false');

-- ---------------------------------------------------------------------------
-- Integration: build_recap / recap_blockers / preview_recap
-- ---------------------------------------------------------------------------
insert into public.organizations (id, name, kind) values
  ('00000000-0000-0000-0000-0000000008f1', 'RC Office', 'office'),
  ('00000000-0000-0000-0000-0000000008a1', 'RC Agency', 'agency');
\set agency '00000000-0000-0000-0000-0000000008a1'
select tests.make_user('rc.author@test.test', :'agency') as author \gset
select tests.make_user('rc.office@test.test', '00000000-0000-0000-0000-0000000008f1') as office_u \gset
select tests.make_bidder('rc.a@test.test', 'RC Bidder A') as bidder_a \gset
select tests.make_bidder('rc.b@test.test', 'RC Bidder B') as bidder_b \gset
select tests.make_bidder('rc.c@test.test', 'RC Bidder C') as bidder_c \gset
select tests.make_bidder('rc.d@test.test', 'RC Bidder D') as bidder_d \gset
select tests.make_bidder('rc.e@test.test', 'RC Bidder E') as bidder_e \gset
select tests.make_bidder('rc.f@test.test', 'RC Bidder F') as bidder_f \gset
select tests.make_bidder('rc.g@test.test', 'RC Bidder G') as bidder_g \gset
update public.bidder_companies set resident_claimed = true, resident_certificate = 'CR-8001'
 where org_id = (select org_id from public.profiles where user_id = :'bidder_e');

-- sol (closed): estimate $150,000 (bonds required, no apprentice credit), funding $150,000 (a funding row), one
-- additive alternate. A accepted; B flagged then agency-accepted; C paper bond not received (pending cure);
-- D non-responsive (office ground); E verified resident; F resident claimed later; G flagged then agency-rejected.
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour',
  jsonb_build_object('schedule', jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object('name', 'Base bid', 'description', 'Site work'),
                               jsonb_build_object('name', 'Item 2', 'description', 'Roofing')),
    'alternates', jsonb_build_array(jsonb_build_object('kind', 'additive', 'description', 'Add canopy'))))) as sol \gset
select tests.make_published_solicitation(:'agency', :'author', now() - interval '1 hour',
  '{"fundingAmountCents": null}'::jsonb) as sol_est \gset
select tests.make_published_solicitation(:'agency', :'author', now() + interval '1 hour') as sol_open \gset

select tests.make_closed_bid(:'sol', :'bidder_a', '{3000000,1000000}', '{500000}', 'paper', null, true, true) as bid_a \gset
select tests.make_closed_bid(:'sol', :'bidder_b', '{3500000,1000000}', '{400000}', 'paper', null, true, true) as bid_b \gset
select tests.make_closed_bid(:'sol', :'bidder_c', '{4000000,1000000}', '{300000}', 'paper', null, true, false) as bid_c \gset
select tests.make_closed_bid(:'sol', :'bidder_d', '{1000000,1000000}', '{100000}', 'paper', null, true, true) as bid_d \gset
select tests.make_closed_bid(:'sol', :'bidder_e', '{4100000,1000000}', '{200000}', 'paper', null, true, true) as bid_e \gset
select tests.make_closed_bid(:'sol', :'bidder_f', '{4500000,1000000}', '{200000}', 'paper', true, true, true) as bid_f \gset
select tests.make_closed_bid(:'sol', :'bidder_g', '{4600000,1000000}', '{200000}', 'paper', null, true, true) as bid_g \gset
select reference as ref_c from public.bids where id = :'bid_c' \gset
select number as sol_number from public.solicitations where id = :'sol' \gset

-- Nothing decided yet: the codes come in order, each once.
select is(app.recap_blockers(:'sol'), array['cure_pending', 'undecided_bids'],
  'blockers: pending cure and undecided bids, in order');

select tests.act_as(:'office_u');
select public.set_bid_outcome(:'bid_a', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bid_b', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bid_d', 'non_responsive', 'wrong_form', 'Old form revision');
select public.set_bid_outcome(:'bid_e', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bid_f', 'accepted', null, 'In order');
select public.set_bid_outcome(:'bid_g', 'accepted', null, 'In order');
select public.verify_resident(:'bid_e', true, 'Certificate CR-8001 checked');
reset role;
select is(app.recap_blockers(:'sol'), array['cure_pending'], 'blockers: one pending cure -> {cure_pending}');

select tests.act_as(:'office_u');
select public.log_bid_original(:'sol', :'ref_c', 1, 'bid_bond');
reset role;
select is(app.recap_blockers(:'sol'), array['undecided_bids'], 'blockers: bond logged, C undecided -> {undecided_bids}');

select tests.act_as(:'office_u');
select public.set_bid_outcome(:'bid_c', 'accepted', null, 'Bond received in cure period');
select public.set_bid_outcome(:'bid_b', 'accepted_flagged', null, 'Addendum 1 not acknowledged') as out_b \gset
select public.set_bid_outcome(:'bid_g', 'accepted_flagged', null, 'Unbalanced unit prices') as out_g \gset
reset role;
select is(app.recap_blockers(:'sol'), array['flags_pending'], 'blockers: flagged bids -> {flags_pending}');

select tests.act_as(:'office_u');
select public.send_flags_to_agency(:'sol');
select tests.act_as(:'author');
select public.decide_flagged_bid(:'out_b', 'accept', 'Acknowledged by phone; minor');
select public.decide_flagged_bid(:'out_g', 'reject', 'Unbalanced');
reset role;
select is(app.recap_blockers(:'sol'), '{}'::text[], 'blockers: all resolved -> empty');

update public.bidder_companies set resident_claimed = true, resident_certificate = 'CR-8002'
 where org_id = (select org_id from public.profiles where user_id = :'bidder_f');
select is(app.recap_blockers(:'sol'), array['resident_unverified'],
  'blockers: an accepted bid with an unverified resident claim -> {resident_unverified}');

select tests.act_as(:'office_u');
select public.verify_resident(:'bid_f', false, 'Certificate CR-8002 expired');
reset role;
select is(app.recap_blockers(:'sol'), '{}'::text[], 'blockers: claim verified (as not resident) -> empty');

select app.build_recap(:'sol') as rc \gset
select is(:'rc'::jsonb ->> 'kind', 'recap', 'build_recap: kind recap');
select is((select jsonb_agg(x ->> 'bidId' order by x ->> 'bidId') from jsonb_array_elements(:'rc'::jsonb -> 'rows') x),
          (select jsonb_agg(id::text order by id::text) from unnest(array[:'bid_a', :'bid_b', :'bid_c', :'bid_e', :'bid_f']::uuid[]) id),
  'build_recap: only accepted and flag_accepted bids (not D non-responsive, not G flag_rejected)');
select is((:'rc'::jsonb ->> 'fundingFromEstimate')::boolean, false, 'build_recap: funding row -> fundingFromEstimate false');
select is((:'rc'::jsonb ->> 'fundingCents')::bigint, 15000000::bigint, 'build_recap: fundingCents from the funding row');
select is(:'rc'::jsonb ->> 'solicitationNumber', :'sol_number', 'build_recap: solicitationNumber');
select is(:'rc'::jsonb -> 'alternates', '[{"kind": "additive", "description": "Add canopy"}]'::jsonb,
  'build_recap: alternates from the published snapshot');
select is(:'rc'::jsonb -> 'selectedAlternates', '[1]'::jsonb, 'build_recap: the additive alternate fits');
select is(tests.rc_row(:'rc', :'bid_a') - 'bidId',
  jsonb_build_object('reference', (select reference from public.bids where id = :'bid_a'), 'bidderName', 'RC Bidder A',
    'baseCents', 4000000, 'alternateCents', '[500000]'::jsonb, 'totalCents', 4500000, 'evaluatedCents', 4500000,
    'resident', false, 'apprenticeCredit', false, 'residentPreferred', false, 'rank', 1, 'tied', false),
  'build_recap: A row from sealed cents (base = sum of items + selected alternate)');
select is((tests.rc_row(:'rc', :'bid_e') ->> 'resident')::boolean, true, 'build_recap: verified resident E is resident');
select is((tests.rc_row(:'rc', :'bid_f') ->> 'resident')::boolean, false, 'build_recap: F verified not resident');
select is((tests.rc_row(:'rc', :'bid_f') ->> 'apprenticeCredit')::boolean, false,
  'build_recap: F committed apprentices but the estimate is under $1M -> no credit');
select is(:'rc'::jsonb ->> 'expectedWinnerBidId', :'bid_a', 'build_recap: expected winner A');

select is(app.build_recap(:'sol_est') - 'solicitationNumber',
  jsonb_build_object('kind', 'all_rejected', 'reason', 'no_accepted_bids', 'fundingCents', 15000000,
    'fundingFromEstimate', true, 'alternates', '[{"kind": "deductive", "description": "Omit canopy"}]'::jsonb,
    'selectedAlternates', '[]'::jsonb, 'rows', '[]'::jsonb, 'expectedWinnerBidId', null, 'winnerOverFunding', false),
  'build_recap: no funding row and no bids -> estimate fallback, no_accepted_bids');
select is(tests.rc_error(format('select app.build_recap(%L)', gen_random_uuid())), 'P0001|not_found',
  'build_recap: unknown solicitation -> not_found');

-- preview_recap
select tests.act_as(:'office_u');
select public.preview_recap(:'sol') as pv \gset
select is(:'pv'::jsonb -> 'recap', :'rc'::jsonb, 'preview_recap: recap is build_recap');
select is(:'pv'::jsonb -> 'blockers', '[]'::jsonb, 'preview_recap: blockers is recap_blockers');
select is(tests.rc_error(format('select public.preview_recap(%L)', :'sol_open')), 'P0001|sealed',
  'preview_recap: before close -> sealed');
select is(tests.rc_error(format('select public.preview_recap(%L)', gen_random_uuid())), 'P0001|not_found',
  'preview_recap: unknown solicitation -> not_found');
select tests.act_as(:'author');
select is(tests.rc_error(format('select public.preview_recap(%L)', :'sol')), 'P0001|not_authorized',
  'preview_recap: agency author -> not_authorized');
select tests.act_as(:'bidder_a');
select is(tests.rc_error(format('select public.preview_recap(%L)', :'sol')), 'P0001|not_authorized',
  'preview_recap: bidder -> not_authorized');
select tests.act_as_anon();
select is(tests.rc_error(format('select public.preview_recap(%L)', :'sol')), '42501|permission denied for function preview_recap',
  'preview_recap: anon has no execute');
reset role;

select * from finish();
rollback;
