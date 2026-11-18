-- 0012_opening: sealed opening at the bid due time, the derived non-responsive rule, tamper evidence and the
-- office's internal tabulation.
--
-- Closed is `now() >= bid_due_at` (app.bids_closed, the database clock at transaction start). Nothing is stored to
-- open a solicitation: on every read after close, each bid's latest submitted, non-withdrawn version becomes readable
-- to office staff through the two functions below. Before close they raise `sealed` for the office and
-- `not_authorized` for everyone else; anon and service_role have no execute privilege (42501).
--
-- Non-responsive is DERIVED, never stored: a bid is non-responsive when app.original_received (0011) finds no
-- counted signed-form original for its latest version by the bid due time read from the solicitation row. Reason
-- (verbatim): 'signed original not received by the bid due time'.
--
-- Audit of the determination (spec "close-time non-responsive determination"): opened_bids writes one
-- `bid_close_determination` bid_audit_log row per bid on the first read after close, and another only when the
-- derived result ({version, original_received, reason}) differs from that bid's latest determination row (for
-- example after an original is voided post-close). An advisory lock per solicitation serializes concurrent readers,
-- so two simultaneous first reads write one row, not two.
--
-- Concurrency: app.open_bids_gate takes FOR SHARE on every bids row of the solicitation before anything about the
-- bids is read. submit_bid, replace_bid and withdraw_bid hold FOR UPDATE on their bid row (app.lock_bid) until they
-- commit, so a submit or withdraw that passed its time check just before the due time and is still in flight is
-- waited out; the functions are volatile, so each later statement takes a fresh read-committed snapshot that
-- includes it.
--
-- Bid bond: judged by the bidder's choice, not by file presence. For 'paper', bond_original_received shows whether a
-- paper bid bond original was counted for that version (same counting rule as the signed form). Display only in
-- 2a: it never makes a bid non-responsive (the bond cure is 2b).
--
-- Tamper evidence (Ruling 5): opened_bid_files compares each file's recorded object id, size and eTag (submit_bid,
-- 0010) with the current storage.objects row: 'missing' when no object has the path, 'changed' when the object id,
-- size or eTag differs, else 'ok'.

-- ---------------------------------------------------------------------------
-- Helpers (schema `app`, no API role executes them)
-- ---------------------------------------------------------------------------

-- A paper bid bond original for exactly this version, counted by the same rule as app.original_received.
create function app.bond_original_received(p_bid_id uuid, p_version int, p_due timestamptz)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bid_original_log r
     where r.bid_id = p_bid_id
       and r.version = p_version
       and r.item = 'bid_bond'
       and r.voids_entry_id is null
       and r.received_at <= p_due
       and r.logged_at <= p_due
       and not exists (select 1 from public.bid_original_log v where v.voids_entry_id = r.id));
$$;

-- The gate both opening functions pass first. Error order: not_authorized (not office) -> not_found (unknown
-- solicitation) -> sealed (not closed, including unpublished). Then FOR SHARE on the solicitation's bids rows.
-- Returns the bid due time, read from the database.
create function app.open_bids_gate(p_solicitation_id uuid)
returns timestamptz
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_due timestamptz;
begin
  perform app.require_office();
  select s.bid_due_at into v_due from public.solicitations s where s.id = p_solicitation_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if not app.bids_closed(p_solicitation_id) then
    raise exception 'sealed' using errcode = 'P0001';
  end if;
  perform 1 from public.bids b where b.solicitation_id = p_solicitation_id for share;
  return v_due;
end;
$$;

revoke all on function app.bond_original_received(uuid, int, timestamptz), app.open_bids_gate(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- opened_bids: the tabulation source. One row per bid at its latest version, withdrawn bids excluded, ordered by
-- base total then reference. bidder_name is the legal name recorded on that version at submit (as submitted), not
-- the live organization name. Office only, after close only. Writes determination audit rows (see header).
-- ---------------------------------------------------------------------------
create function public.opened_bids(p_solicitation_id uuid)
returns table (
  bid_id uuid, reference text, version int, submitted_at timestamptz, bidder_org_id uuid, bidder_name text,
  item_cents bigint[], alternate_cents bigint[], base_total_cents bigint, bid_bond_choice public.bid_bond_choice,
  original_received boolean, non_responsive_reason text, bond_original_received boolean)
language plpgsql volatile security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reason constant text := 'signed original not received by the bid due time';
  v_due    timestamptz;
  v_detail jsonb;
  r        record;
begin
  v_due := app.open_bids_gate(p_solicitation_id);
  perform pg_advisory_xact_lock(hashtext(p_solicitation_id::text));

  for r in
    select b.id as bid_id, b.reference, v.version, v.submitted_at, b.bidder_org_id, v.bidder_legal_name as bidder_name,
           v.item_cents, v.alternate_cents,
           coalesce((select sum(x) from unnest(v.item_cents) x), 0)::bigint as base_total_cents,
           v.bid_bond_choice,
           app.original_received(b.id, v.version, v_due) as received,
           case when v.bid_bond_choice = 'paper' then app.bond_original_received(b.id, v.version, v_due) end as bond
      from public.bids b
      join public.bid_versions v on v.bid_id = b.id and v.version = app.latest_version(b.id)
     where b.solicitation_id = p_solicitation_id
       and not app.is_withdrawn(b.id, v.version)
     order by 9, b.reference
  loop
    v_detail := jsonb_build_object('version', r.version, 'original_received', r.received,
                                   'reason', case when r.received then null else v_reason end);
    if (select a.detail from public.bid_audit_log a
         where a.bid_id = r.bid_id and a.action = 'bid_close_determination'
         order by a.id desc limit 1) is distinct from v_detail then
      insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
      values (p_solicitation_id, r.bid_id, auth.uid(), 'bid_close_determination', v_detail);
    end if;

    bid_id := r.bid_id;
    reference := r.reference;
    version := r.version;
    submitted_at := r.submitted_at;
    bidder_org_id := r.bidder_org_id;
    bidder_name := r.bidder_name;
    item_cents := r.item_cents;
    alternate_cents := r.alternate_cents;
    base_total_cents := r.base_total_cents;
    bid_bond_choice := r.bid_bond_choice;
    original_received := r.received;
    non_responsive_reason := case when r.received then null else v_reason end;
    bond_original_received := r.bond;
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- opened_bid_files: the files of each bid's latest, non-withdrawn version, with a tamper status. Same gates.
-- ---------------------------------------------------------------------------
create function public.opened_bid_files(p_solicitation_id uuid)
returns table (bid_id uuid, slot public.bid_upload_slot, path text, file_name text, file_status text)
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  perform app.open_bids_gate(p_solicitation_id);

  return query
    select b.id, f.slot, f.path, f.file_name,
           case when o.id is null then 'missing'
                when o.id is distinct from f.object_id
                  or (o.metadata->>'size') is distinct from f.object_size::text
                  or (o.metadata->>'eTag') is distinct from f.object_etag then 'changed'
                else 'ok' end
      from public.bids b
      join public.bid_versions v on v.bid_id = b.id and v.version = app.latest_version(b.id)
      join public.bid_version_files f on f.version_id = v.id
      left join storage.objects o on o.bucket_id = 'bid-files' and o.name = f.path
     where b.solicitation_id = p_solicitation_id
       and not app.is_withdrawn(b.id, v.version)
     order by b.reference, f.slot;
end;
$$;

revoke all on function public.opened_bids(uuid), public.opened_bid_files(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.opened_bids(uuid), public.opened_bid_files(uuid) to authenticated;
