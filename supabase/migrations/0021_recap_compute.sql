-- 0021_recap_compute: the recap, computed in Postgres from sealed bid prices (slice 2b, Task 8).
--
-- The recap is the single source of truth for ranking: nobody types a number. Every figure comes from the stored
-- bid_versions cents (base = sum of item_cents; alternate_cents as sealed), the solicitation's published estimate and
-- alternates, and the confidential funding amount (app.funding_cents, 0014).
--
-- Arithmetic is exact. For a bid b and a set S of selected alternates (1-based indexes):
--   sign(j)     = +1 for an additive alternate, -1 for a deductive one
--   T(b,S)      = baseCents(b) + sum_{j in S} sign(j) * alternateCents(b)[j]        actual price, cents
--   credit(b)   = apprentice(b) and estimate >= 100,000,000 ($1M job)
--   E(b,S)      = T(b,S) * (credit(b) ? 99 : 100)                                   evaluated, hundredths of a cent
-- E is compared as an exact integer; evaluatedCents = floor((E + 50) / 100) is for display only (half-up).
--
-- Alternate selection (controller Ruling 4, overriding the plan's single additive loop):
--   lowest(S) = bids with the minimum E(b,S) (no resident preference); fits(S) = max T over lowest(S) <= funding.
--   Memo first (revised Ruling 9): all_rejected / over_funding iff EVERY bid's T(b, all deductives) > funding (with
--   no deductives: every base total exceeds funding, as spec section 5 says).
--   Otherwise S := {}; if not fits(S), take deductive alternates in listed order until fits(S). If fits(S) still
--   fails after all deductives (credit made an over-funding bid the lowest while another bid fits), S stays all
--   deductives, no additive is taken, and winnerOverFunding warns (Ruling 5). If fits(S), take additive alternates
--   in listed order while fits(S + j), stopping at the first that does not fit. Deductives are never taken when the
--   base already fits. A negative T (memo check or final S) is invalid_data.
-- Ranking for the final S: N = min E over non-resident bids; a resident bid is preferred when E * 100 <= N * 105
-- (within 5%, inclusive). key = (preferred ? 0 : 1, E); rank = 1 + count of strictly smaller keys (1,1,3); tied when
-- another bid has the same key. expectedWinnerBidId is the sole rank-1 bid, else null.
--
-- Snapshot JSON shape: names.md "Recap snapshot JSON" (camelCase), parsed by src/domain/recap/snapshot.ts.

-- ---------------------------------------------------------------------------
-- app.recap_lines: T, E and credit for every bid in p_bids under the alternate set p_set. Immutable and pure.
-- i is the 1-based position of the bid in p_bids. invalid_data when a bid's alternateCents length differs from the
-- number of alternates.
-- ---------------------------------------------------------------------------
create function app.recap_lines(p_bids jsonb, p_alternate_kinds text[], p_set int[], p_estimate_cents bigint)
returns table (i int, total numeric, evaluated numeric, credit boolean)
language plpgsql immutable
set search_path = ''
as $$
declare
  v_n    int := coalesce(cardinality(p_alternate_kinds), 0);
  v_bid  jsonb;
  v_pos  bigint;
  v_j    int;
  v_tot  numeric;
begin
  for v_bid, v_pos in select e.value, e.ordinality from jsonb_array_elements(p_bids) with ordinality e loop
    if jsonb_typeof(v_bid -> 'alternateCents') is distinct from 'array'
       or jsonb_array_length(v_bid -> 'alternateCents') <> v_n then
      raise exception 'invalid_data' using errcode = 'P0001';
    end if;
    v_tot := (v_bid ->> 'baseCents')::bigint;
    foreach v_j in array coalesce(p_set, '{}'::int[]) loop
      v_tot := v_tot + case when p_alternate_kinds[v_j] = 'additive' then 1 else -1 end
                       * ((v_bid -> 'alternateCents') ->> (v_j - 1))::bigint;
    end loop;
    i := v_pos::int;
    total := v_tot;
    credit := coalesce((v_bid ->> 'apprentice')::boolean, false) and coalesce(p_estimate_cents >= 100000000, false);
    evaluated := v_tot * case when credit then 99 else 100 end;
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- app.recap_fits: the lowest evaluated bid(s) under p_set fit the funding amount (max T over the tied lowest set).
-- ---------------------------------------------------------------------------
create function app.recap_fits(
  p_bids jsonb, p_alternate_kinds text[], p_set int[], p_funding_cents bigint, p_estimate_cents bigint)
returns boolean
language sql immutable
set search_path = ''
as $$
  with l as (select * from app.recap_lines(p_bids, p_alternate_kinds, p_set, p_estimate_cents))
  select coalesce(max(l.total) <= p_funding_cents, false)
    from l
   where l.evaluated = (select min(l2.evaluated) from l l2);
$$;

-- ---------------------------------------------------------------------------
-- app.rank_recap: the recap snapshot for the given bids. Immutable and pure (reads no tables).
-- Each p_bids element: {bidId, reference, bidderName, baseCents, alternateCents[], resident, apprentice}.
-- Returns {kind, reason, fundingCents, selectedAlternates, rows, expectedWinnerBidId, winnerOverFunding}.
-- ---------------------------------------------------------------------------
create function app.rank_recap(
  p_bids jsonb, p_alternate_kinds text[], p_funding_cents bigint, p_estimate_cents bigint)
returns jsonb
language plpgsql immutable
set search_path = ''
as $$
declare
  v_kinds  text[] := coalesce(p_alternate_kinds, '{}'::text[]);
  v_n      int := coalesce(cardinality(p_alternate_kinds), 0);
  v_sel    int[] := '{}';
  v_j      int;
  v_rows   jsonb;
  v_winner text;
  v_over   boolean := false;
  v_ded    int[];
  v_min    numeric;
  v_fits   boolean;
begin
  if p_bids is null or jsonb_typeof(p_bids) is distinct from 'array' or p_funding_cents is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  for v_j in 1 .. v_n loop
    if v_kinds[v_j] is null or v_kinds[v_j] not in ('additive', 'deductive') then
      raise exception 'invalid_data' using errcode = 'P0001';
    end if;
  end loop;

  if jsonb_array_length(p_bids) = 0 then
    return jsonb_build_object('kind', 'all_rejected', 'reason', 'no_accepted_bids', 'fundingCents', p_funding_cents,
      'selectedAlternates', '[]'::jsonb, 'rows', '[]'::jsonb, 'expectedWinnerBidId', null,
      'winnerOverFunding', false);
  end if;

  -- 0. The memo (revised Ruling 9): every bid's total with ALL deductive alternates taken exceeds funding. With no
  --    deductives this is the spec's "every accepted bid's base total exceeds the funding amount". A negative total
  --    is invalid_data (it would break the 5% comparison).
  select coalesce(array_agg(x order by x), '{}') into v_ded
    from generate_series(1, v_n) x where v_kinds[x] = 'deductive';
  select min(l.total) into v_min from app.recap_lines(p_bids, v_kinds, v_ded, p_estimate_cents) l;
  if exists (select 1 from app.recap_lines(p_bids, v_kinds, v_ded, p_estimate_cents) l where l.total < 0) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if v_min > p_funding_cents then
    return jsonb_build_object('kind', 'all_rejected', 'reason', 'over_funding', 'fundingCents', p_funding_cents,
      'selectedAlternates', '[]'::jsonb, 'rows', '[]'::jsonb, 'expectedWinnerBidId', null,
      'winnerOverFunding', false);
  end if;

  -- 1. Alternate selection (Ruling 4): deductives only while the base does not fit, then additives in order. If the
  --    lowest evaluated bid still does not fit after every deductive (credit makes an over-funding bid the lowest
  --    while another bid fits), S is all deductives, no additive is taken, and winnerOverFunding reports it.
  v_fits := app.recap_fits(p_bids, v_kinds, v_sel, p_funding_cents, p_estimate_cents);
  if not v_fits then
    foreach v_j in array v_ded loop
      v_sel := v_sel || v_j;
      v_fits := app.recap_fits(p_bids, v_kinds, v_sel, p_funding_cents, p_estimate_cents);
      exit when v_fits;
    end loop;
  end if;
  if v_fits then
    for v_j in 1 .. v_n loop
      continue when v_kinds[v_j] <> 'additive';
      exit when not app.recap_fits(p_bids, v_kinds, v_sel || v_j, p_funding_cents, p_estimate_cents);
      v_sel := v_sel || v_j;
    end loop;
  end if;
  select coalesce(array_agg(x order by x), '{}') into v_sel from unnest(v_sel) x;
  if exists (select 1 from app.recap_lines(p_bids, v_kinds, v_sel, p_estimate_cents) l where l.total < 0) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  -- 2. Ranking for the final selection, with the resident preference.
  with l as (
    select l.i, l.total, l.evaluated, l.credit, e.value as bid,
           coalesce((e.value ->> 'resident')::boolean, false) as resident
      from app.recap_lines(p_bids, v_kinds, v_sel, p_estimate_cents) l
      join jsonb_array_elements(p_bids) with ordinality e on e.ordinality = l.i
  ), n as (
    select min(l.evaluated) as nmin from l where not l.resident
  ), k as (
    select l.*, (l.resident and n.nmin is not null and l.evaluated * 100 <= n.nmin * 105) as preferred
      from l cross join n
  ), kk as (
    select k.*, case when k.preferred then 0 else 1 end as pk from k
  ), r as (
    select kk.*,
           1 + (select count(*) from kk o where (o.pk, o.evaluated) < (kk.pk, kk.evaluated)) as rank,
           exists (select 1 from kk o where o.i <> kk.i and o.pk = kk.pk and o.evaluated = kk.evaluated) as tied
      from kk
  )
  select jsonb_agg(jsonb_build_object(
           'bidId', r.bid -> 'bidId', 'reference', r.bid -> 'reference', 'bidderName', r.bid -> 'bidderName',
           'baseCents', (r.bid ->> 'baseCents')::bigint, 'alternateCents', r.bid -> 'alternateCents',
           'totalCents', r.total::bigint, 'evaluatedCents', floor((r.evaluated + 50) / 100)::bigint,
           'resident', r.resident, 'apprenticeCredit', r.credit, 'residentPreferred', r.preferred,
           'rank', r.rank, 'tied', r.tied)
         order by r.rank, r.bid ->> 'reference'),
         case when count(*) filter (where r.rank = 1) = 1
              then max(r.bid ->> 'bidId') filter (where r.rank = 1) end,
         coalesce(bool_or(r.total > p_funding_cents) filter (where r.rank = 1 and not r.tied), false)
    into v_rows, v_winner, v_over
    from r;

  return jsonb_build_object('kind', 'recap', 'reason', null, 'fundingCents', p_funding_cents,
    'selectedAlternates', to_jsonb(v_sel), 'rows', v_rows, 'expectedWinnerBidId', v_winner,
    'winnerOverFunding', v_winner is not null and v_over);
end;
$$;

-- ---------------------------------------------------------------------------
-- app.recap_bids: the recap-eligible bids of a solicitation as rank_recap input, ordered by reference. A bid is
-- eligible when app.bid_review_status (as of now) is accepted or flag_accepted. resident is the office's latest
-- verification verdict (app.resident_verified): an unverified claim is passed as false. Reads only; no gates (the
-- caller gates).
-- ---------------------------------------------------------------------------
create function app.recap_bids(p_solicitation_id uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'bidId', b.id, 'reference', b.reference, 'bidderName', v.bidder_legal_name,
           'baseCents', coalesce((select sum(x) from unnest(v.item_cents) x), 0)::bigint,
           'alternateCents', to_jsonb(coalesce(v.alternate_cents, '{}'::bigint[])),
           'resident', app.resident_verified(b.id),
           'apprentice', coalesce(v.apprentice_commitment, false))
         order by b.reference), '[]'::jsonb)
    from public.bids b
    join public.bid_versions v on v.bid_id = b.id and v.version = app.latest_version(b.id)
    cross join lateral app.bid_review_status(b.id, now()) s
   where b.solicitation_id = p_solicitation_id
     and not app.is_withdrawn(b.id, v.version)
     and s.status in ('accepted', 'flag_accepted');
$$;

-- ---------------------------------------------------------------------------
-- app.build_recap: the full recap snapshot for a solicitation (rank_recap plus solicitationNumber, alternates and
-- fundingFromEstimate). Alternates and the estimate come from the published snapshot; the funding amount from
-- app.funding_cents (confidential until posting). not_found for an unknown solicitation. No gates: callers gate.
-- ---------------------------------------------------------------------------
create function app.build_recap(p_solicitation_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_sol   public.solicitations;
  v_data  jsonb;
  v_alts  jsonb;
  v_kinds text[];
begin
  select s.* into v_sol from public.solicitations s where s.id = p_solicitation_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  v_data := coalesce(v_sol.published_snapshot -> 'data', v_sol.data);
  v_alts := coalesce(v_data -> 'schedule' -> 'alternates', '[]'::jsonb);
  select coalesce(array_agg(a.value ->> 'kind' order by a.ordinality), '{}') into v_kinds
    from jsonb_array_elements(v_alts) with ordinality a;

  return app.rank_recap(app.recap_bids(p_solicitation_id), v_kinds, app.funding_cents(p_solicitation_id),
                        (v_data ->> 'estimateCents')::bigint)
         || jsonb_build_object('solicitationNumber', v_sol.number, 'alternates', v_alts,
                               'fundingFromEstimate', app.funding_from_estimate(p_solicitation_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- app.recap_blockers: why the recap cannot be sent to check yet, in this order, each code at most once:
-- cure_pending, undecided_bids, flags_pending, resident_unverified (a recap-eligible bid whose bidder claims
-- residency with no verification row). Statuses as of now. Empty array when nothing blocks.
-- ---------------------------------------------------------------------------
create function app.recap_blockers(p_solicitation_id uuid)
returns text[]
language sql stable security definer
set search_path = ''
as $$
  with st as (
    select b.id, s.status
      from public.bids b
      cross join lateral app.bid_review_status(b.id, now()) s
     where b.solicitation_id = p_solicitation_id
  )
  select array_remove(array[
    case when exists (select 1 from st where st.status = 'pending_cure') then 'cure_pending' end,
    case when exists (select 1 from st where st.status = 'undecided') then 'undecided_bids' end,
    case when exists (select 1 from st where st.status = 'flagged') then 'flags_pending' end,
    case when exists (select 1 from st where st.status in ('accepted', 'flag_accepted')
                                         and app.resident_unverified(st.id)) then 'resident_unverified' end
  ]::text[], null);
$$;

revoke all on function app.recap_lines(jsonb, text[], int[], bigint),
  app.recap_fits(jsonb, text[], int[], bigint, bigint),
  app.rank_recap(jsonb, text[], bigint, bigint),
  app.recap_bids(uuid), app.build_recap(uuid), app.recap_blockers(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- preview_recap: the office's live recap preview with its blockers. Gates (app.open_bids_gate): not_authorized (not
-- office) -> not_found (unknown solicitation) -> sealed (before close). Writes nothing beyond the gate's FOR SHARE.
-- ---------------------------------------------------------------------------
create function public.preview_recap(p_solicitation_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  perform app.open_bids_gate(p_solicitation_id);
  return jsonb_build_object('recap', app.build_recap(p_solicitation_id),
                            'blockers', to_jsonb(app.recap_blockers(p_solicitation_id)));
end;
$$;

revoke all on function public.preview_recap(uuid) from public, anon, authenticated, service_role;
grant execute on function public.preview_recap(uuid) to authenticated;
