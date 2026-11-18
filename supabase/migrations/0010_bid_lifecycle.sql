-- 0010_bid_lifecycle: time-gated bid functions (start, replace, submit, withdraw), bidder receipts and the
-- office's pre-close index.
--
-- Every public function is security definer with an empty search_path, executable by `authenticated` only, and
-- follows one order: role check, lock, time/state checks, guarded write, one bid_audit_log row (start_bid writes no
-- audit row: a draft is not on the spec's audit list). "Closed" is `now() >= bid_due_at`, decided by the database
-- clock (transaction start) inside app.bids_closed, never by the client. After taking the bid row lock, every
-- bid writer also re-checks the deadline on the database's clock_timestamp() (app.require_before_due_clock,
-- Ruling 8), so a write whose transaction started before the due time cannot land after opening.
--
-- Error order for bid functions: not_authorized (not a bidder) -> not_found (unknown bid, or another org's) ->
-- bids_closed -> not_open (unpublished or unreleased) -> invalid_state -> invalid_bid.
--
-- Tamper evidence (Ruling 5): submit_bid records each moved file's storage object id, size and eTag from
-- storage.objects (no download). The ACCEPTED LIMIT in 0009 (Ruling 3) lets the service-role key replace or delete
-- bid files in Storage; opening (Task 9) compares these values against the current storage.objects row and flags
-- a missing or changed file. `postgres` (the owner of these functions) holds select on storage.objects and has
-- BYPASSRLS, so the read works inside the definer function.

-- ---------------------------------------------------------------------------
-- Tamper-evidence columns. Nullable: rows written before this migration (or test fixtures inserted directly)
-- have none; submit_bid always fills object_id and copies size/eTag from the object's metadata.
-- ---------------------------------------------------------------------------
alter table public.bid_version_files
  add column object_id   uuid,
  add column object_size bigint,
  add column object_etag text;

-- ---------------------------------------------------------------------------
-- Helpers (schema `app`, no API role executes them)
-- ---------------------------------------------------------------------------

-- Crockford base32 alphabet (no I, L, O, U), 8 characters as XXXX-XXXX: 40 random bits.
create function app.new_bid_reference()
returns text
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_bytes bytea;
  v_ref   text;
begin
  for attempt in 1..5 loop
    v_bytes := extensions.gen_random_bytes(8);
    v_ref := '';
    for i in 0..7 loop
      v_ref := v_ref || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
      if i = 3 then
        v_ref := v_ref || '-';
      end if;
    end loop;
    if not exists (select 1 from public.bids b where b.reference = v_ref) then
      return v_ref;
    end if;
  end loop;
  raise exception 'reference_exhausted' using errcode = 'P0001';
end;
$$;

-- Typed-in reference to canonical form: trims, drops spaces and dashes, uppercases, maps O->0 and I/L->1.
-- Null when the result is not 8 characters of the alphabet.
create function app.normalize_bid_reference(p_ref text)
returns text
language sql immutable security definer
set search_path = ''
as $$
  select case when v.s ~ '^[0-9A-HJKMNP-TV-Z]{8}$' then left(v.s, 4) || '-' || right(v.s, 4) end
  from (select translate(upper(regexp_replace(coalesce(p_ref, ''), '[\s-]', '', 'g')), 'OIL', '011') as s) v;
$$;

-- Lock the caller's own bid row, or raise not_found. Another org's bid is never locked and reads as not_found, so
-- the error does not reveal that it exists.
create function app.lock_bid(p_bid_id uuid)
returns public.bids
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.bids;
begin
  select * into v_row from public.bids b
   where b.id = p_bid_id and b.bidder_org_id = app.my_org()
   for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  return v_row;
end;
$$;

-- p_snapshot is solicitations.published_snapshot ({data, clauses, settings}).
create function app.bonds_required(p_snapshot jsonb)
returns boolean
language sql immutable security definer
set search_path = ''
as $$
  select coalesce((p_snapshot->'data'->>'estimateCents')::bigint >= 15000000, false);
$$;

-- insurance, then each optional section in snapshot order, then bid_bond when bonds are required and the choice
-- is electronic.
create function app.required_bid_slots(p_snapshot jsonb, p_choice public.bid_bond_choice)
returns public.bid_upload_slot[]
language sql immutable security definer
set search_path = ''
as $$
  select array['insurance']::public.bid_upload_slot[]
    || coalesce((select array_agg(s.value::public.bid_upload_slot order by s.ord)
                   from jsonb_array_elements_text(coalesce(p_snapshot->'data'->'optionalSections', '[]'::jsonb))
                        with ordinality s(value, ord)), '{}')
    || case when app.bonds_required(p_snapshot) and p_choice = 'electronic'
            then array['bid_bond']::public.bid_upload_slot[] else '{}' end;
$$;

-- Problems that block submitting the bid's draft, as codes matching TypeScript BidIssueCode (Task 5), in a fixed
-- order, each at most once. Empty when there is no draft problem (or no draft).
--   price_count: a price array has entries but not one per schedule item / alternate, or is not a 1-based,
--     one-dimensional array (a malformed shape is an invalid bid, never a raw error).
--   price_missing: a price is null, or a price array was never entered (empty) while the schedule has entries.
--   upload_missing: a required slot has no draft file row.
--   file_missing: a draft file row's path has no storage object in bid-files, or the object's metadata lacks a
--     numeric size or an eTag, so submit never seals null tamper evidence (database-only).
--   bond_choice_missing / bond_not_required: bond choice versus the estimate.
create function app.bid_draft_problems(p_bid_id uuid)
returns text[]
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_draft    public.bid_drafts;
  v_snap     jsonb;
  v_bonds    boolean;
  v_n_items  int;
  v_n_alts   int;
  v_problems text[] := '{}';
  v_count    boolean := false;
  v_missing  boolean := false;
begin
  select * into v_draft from public.bid_drafts d where d.bid_id = p_bid_id;
  if not found then
    return v_problems;
  end if;
  select s.published_snapshot into v_snap
    from public.bids b join public.solicitations s on s.id = b.solicitation_id
   where b.id = p_bid_id;
  v_bonds   := app.bonds_required(v_snap);
  v_n_items := coalesce(jsonb_array_length(v_snap->'data'->'schedule'->'items'), 0);
  v_n_alts  := coalesce(jsonb_array_length(v_snap->'data'->'schedule'->'alternates'), 0);

  -- Items
  if cardinality(v_draft.item_cents) = 0 and v_n_items > 0 then
    v_missing := true;
  elsif cardinality(v_draft.item_cents) <> v_n_items
        or array_ndims(v_draft.item_cents) <> 1 or array_lower(v_draft.item_cents, 1) <> 1 then
    v_count := true;
  elsif array_position(v_draft.item_cents, null) is not null then
    v_missing := true;
  end if;
  -- Alternates
  if cardinality(v_draft.alternate_cents) = 0 and v_n_alts > 0 then
    v_missing := true;
  elsif cardinality(v_draft.alternate_cents) <> v_n_alts
        or array_ndims(v_draft.alternate_cents) <> 1 or array_lower(v_draft.alternate_cents, 1) <> 1 then
    v_count := true;
  elsif array_position(v_draft.alternate_cents, null) is not null then
    v_missing := true;
  end if;
  if v_count then
    v_problems := array_append(v_problems, 'price_count');
  end if;
  if v_missing then
    v_problems := array_append(v_problems, 'price_missing');
  end if;

  if exists (select 1 from unnest(app.required_bid_slots(v_snap, v_draft.bid_bond_choice)) r(slot)
              where not exists (select 1 from public.bid_draft_files f where f.bid_id = p_bid_id and f.slot = r.slot)) then
    v_problems := array_append(v_problems, 'upload_missing');
  end if;

  if exists (select 1 from public.bid_draft_files f
              where f.bid_id = p_bid_id
                and not exists (select 1 from storage.objects o
                                 where o.bucket_id = 'bid-files' and o.name = f.path
                                   and o.metadata->>'size' ~ '^[0-9]{1,18}$'
                                   and o.metadata->>'eTag' is not null)) then
    v_problems := array_append(v_problems, 'file_missing');
  end if;

  if v_bonds and v_draft.bid_bond_choice is null then
    v_problems := array_append(v_problems, 'bond_choice_missing');
  elsif not v_bonds and v_draft.bid_bond_choice is not null then
    v_problems := array_append(v_problems, 'bond_not_required');
  end if;

  return v_problems;
end;
$$;

-- Time and publication gate shared by the write functions: bids_closed first, then not_open.
create function app.require_bidding_open(p_solicitation_id uuid)
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if app.bids_closed(p_solicitation_id) then
    raise exception 'bids_closed' using errcode = 'P0001';
  end if;
  if not app.bidding_open(p_solicitation_id) then
    raise exception 'not_open' using errcode = 'P0001';
  end if;
end;
$$;

-- Second deadline check (Ruling 8), made AFTER the bid row lock is held: the database's wall clock
-- (clock_timestamp()), not the transaction start. require_bidding_open judges "closed" by now(), so a transaction
-- that started before the due time could otherwise commit a submit or withdraw after the office has opened bids.
-- Opening takes FOR SHARE on the bids rows (0012); either the writer holds the row lock first and the opener waits
-- for it to commit, or the opener holds it first and the writer, once it gets the lock, sees clock_timestamp() past
-- the due time here and raises bids_closed. Both clocks are the database's.
create function app.require_before_due_clock(p_solicitation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.solicitations s
              where s.id = p_solicitation_id and clock_timestamp() >= s.bid_due_at) then
    raise exception 'bids_closed' using errcode = 'P0001';
  end if;
end;
$$;

create function app.require_bidder()
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not app.is_bidder() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
end;
$$;

create function app.bid_audit(p_bid public.bids, p_action text, p_detail jsonb)
returns void
language sql security definer
set search_path = ''
as $$
  insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
  values (p_bid.solicitation_id, p_bid.id, auth.uid(), p_action, coalesce(p_detail, '{}'::jsonb));
$$;

revoke all on function app.new_bid_reference(), app.normalize_bid_reference(text), app.lock_bid(uuid),
  app.bonds_required(jsonb), app.required_bid_slots(jsonb, public.bid_bond_choice), app.bid_draft_problems(uuid),
  app.require_bidding_open(uuid), app.require_before_due_clock(uuid), app.require_bidder(),
  app.bid_audit(public.bids, text, jsonb)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- start_bid: create the bid (new reference) and draft version 1. Idempotent while a draft exists.
-- ---------------------------------------------------------------------------
create function public.start_bid(p_solicitation_id uuid)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_bid public.bids;
begin
  perform app.require_bidder();
  v_org := app.my_org();

  -- Lock: the solicitation row (shared; published rows are frozen) so its due time cannot move under us.
  -- An unknown id and an unpublished one both read as not_open, so the error does not reveal which ids exist.
  perform 1 from public.solicitations s where s.id = p_solicitation_id for share;
  if not found then
    raise exception 'not_open' using errcode = 'P0001';
  end if;
  perform app.require_bidding_open(p_solicitation_id);

  insert into public.bids (solicitation_id, bidder_org_id, reference, created_by)
  values (p_solicitation_id, v_org, app.new_bid_reference(), auth.uid())
  on conflict (solicitation_id, bidder_org_id) do nothing;
  select b.* into v_bid from public.bids b
   where b.solicitation_id = p_solicitation_id and b.bidder_org_id = v_org;
  v_bid := app.lock_bid(v_bid.id);
  perform app.require_before_due_clock(v_bid.solicitation_id);

  if exists (select 1 from public.bid_drafts d where d.bid_id = v_bid.id) then
    return v_bid.id;
  end if;
  if app.latest_version(v_bid.id) is not null then
    raise exception 'invalid_state' using errcode = 'P0001';  -- already submitted: use replace_bid
  end if;
  insert into public.bid_drafts (bid_id, version) values (v_bid.id, 1);
  return v_bid.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- replace_bid: needs a submitted version (withdrawn is fine) and no draft. Starts an empty draft latest + 1.
-- ---------------------------------------------------------------------------
create function public.replace_bid(p_bid_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid    public.bids;
  v_latest int;
begin
  perform app.require_bidder();
  v_bid := app.lock_bid(p_bid_id);
  perform app.require_before_due_clock(v_bid.solicitation_id);
  perform app.require_bidding_open(v_bid.solicitation_id);

  v_latest := app.latest_version(v_bid.id);
  if v_latest is null or exists (select 1 from public.bid_drafts d where d.bid_id = v_bid.id) then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.bid_drafts (bid_id, version) values (v_bid.id, v_latest + 1);
  perform app.bid_audit(v_bid, 'replace_bid',
                        jsonb_build_object('from_version', v_latest, 'draft_version', v_latest + 1));
end;
$$;

-- ---------------------------------------------------------------------------
-- submit_bid: seal the draft as version latest + 1 with the bidder's legal name as it stands now, move its files
-- (with tamper evidence), delete the draft.
-- The bidder can never read the sealed prices or files back. No prices in the audit detail.
-- ---------------------------------------------------------------------------
create function public.submit_bid(p_bid_id uuid)
returns table (reference text, version int, submitted_at timestamptz)
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid      public.bids;
  v_draft    public.bid_drafts;
  v_latest   int;
  v_problems text[];
  v_version  public.bid_versions;
  v_n_files  int;
  v_copied   int;
begin
  perform app.require_bidder();
  v_bid := app.lock_bid(p_bid_id);
  perform app.require_before_due_clock(v_bid.solicitation_id);
  perform app.require_bidding_open(v_bid.solicitation_id);

  v_latest := app.latest_version(v_bid.id);
  select * into v_draft from public.bid_drafts d where d.bid_id = v_bid.id for update;
  if not found or v_draft.version <> coalesce(v_latest, 0) + 1 then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  -- Lock the draft file rows so they cannot change between validation and the copy below.
  perform 1 from public.bid_draft_files f where f.bid_id = v_bid.id for update;
  select count(*) into v_n_files from public.bid_draft_files f where f.bid_id = v_bid.id;

  v_problems := app.bid_draft_problems(v_bid.id);
  if cardinality(v_problems) > 0 then
    raise exception 'invalid_bid' using errcode = 'P0001', detail = array_to_string(v_problems, ',');
  end if;

  -- The legal name is copied as it stands now (the as-submitted name the tabulation shows).
  insert into public.bid_versions (bid_id, version, submitted_by, item_cents, alternate_cents, bid_bond_choice,
                                   bidder_legal_name)
  select v_bid.id, v_draft.version, auth.uid(), v_draft.item_cents, v_draft.alternate_cents, v_draft.bid_bond_choice,
         o.name
    from public.organizations o
   where o.id = v_bid.bidder_org_id
  returning * into v_version;

  -- Validated above, but a storage object can still be deleted by a concurrent transaction that commits before
  -- this statement's snapshot: the join would then drop that file silently. Compare counts and refuse instead.
  insert into public.bid_version_files (version_id, slot, path, file_name, object_id, object_size, object_etag)
  select v_version.id, f.slot, f.path, f.file_name, o.id, (o.metadata->>'size')::bigint, o.metadata->>'eTag'
    from public.bid_draft_files f
    join storage.objects o on o.bucket_id = 'bid-files' and o.name = f.path
   where f.bid_id = v_bid.id
     and o.metadata->>'size' ~ '^[0-9]{1,18}$' and o.metadata->>'eTag' is not null;
  get diagnostics v_copied = row_count;
  if v_copied <> v_n_files then
    raise exception 'invalid_bid' using errcode = 'P0001', detail = 'file_missing';
  end if;

  delete from public.bid_drafts d where d.bid_id = v_bid.id;  -- cascades to bid_draft_files

  perform app.bid_audit(v_bid, 'submit_bid',
                        jsonb_build_object('reference', v_bid.reference, 'version', v_version.version,
                                           'supersedes', v_latest));

  return query select v_bid.reference, v_version.version, v_version.submitted_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- withdraw_bid: withdraw the latest version (must exist, not already withdrawn). Any draft stays in place.
-- ---------------------------------------------------------------------------
create function public.withdraw_bid(p_bid_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid    public.bids;
  v_latest int;
begin
  perform app.require_bidder();
  v_bid := app.lock_bid(p_bid_id);
  perform app.require_before_due_clock(v_bid.solicitation_id);
  perform app.require_bidding_open(v_bid.solicitation_id);

  v_latest := app.latest_version(v_bid.id);
  if v_latest is null or app.is_withdrawn(v_bid.id, v_latest) then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.bid_withdrawals (bid_id, version, withdrawn_by) values (v_bid.id, v_latest, auth.uid());
  perform app.bid_audit(v_bid, 'withdraw_bid', jsonb_build_object('version', v_latest));
end;
$$;

-- ---------------------------------------------------------------------------
-- my_bid_receipts: the caller's own bid only (otherwise not_found). Time, reference, version, withdrawal and
-- whether it is the current (latest, not withdrawn) version. No prices or files. Readable before and after close.
-- ---------------------------------------------------------------------------
create function public.my_bid_receipts(p_bid_id uuid)
returns table (reference text, version int, submitted_at timestamptz, withdrawn_at timestamptz, is_current boolean)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_ref text;
begin
  perform app.require_bidder();
  select b.reference into v_ref from public.bids b where b.id = p_bid_id and b.bidder_org_id = app.my_org();
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  return query
    select v_ref, v.version, v.submitted_at, w.withdrawn_at,
           (v.version = max(v.version) over () and w.withdrawn_at is null)
      from public.bid_versions v
      left join public.bid_withdrawals w on w.bid_id = v.bid_id and w.version = v.version
     where v.bid_id = p_bid_id
     order by v.version;
end;
$$;

-- ---------------------------------------------------------------------------
-- office_bid_index: office only. Reference, version and status (current | superseded | withdrawn) for every
-- submitted version on the solicitation. No organization, time or prices: before close this is all the office sees.
-- ---------------------------------------------------------------------------
create function public.office_bid_index(p_solicitation_id uuid)
returns table (reference text, version int, status text)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform app.require_office();
  return query
    select b.reference, v.version,
           case when w.bid_id is not null then 'withdrawn'
                when v.version = max(v.version) over (partition by v.bid_id) then 'current'
                else 'superseded' end
      from public.bids b
      join public.bid_versions v on v.bid_id = b.id
      left join public.bid_withdrawals w on w.bid_id = v.bid_id and w.version = v.version
     where b.solicitation_id = p_solicitation_id
     order by b.reference, v.version;
end;
$$;

revoke all on function public.start_bid(uuid), public.replace_bid(uuid), public.submit_bid(uuid),
  public.withdraw_bid(uuid), public.my_bid_receipts(uuid), public.office_bid_index(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.start_bid(uuid), public.replace_bid(uuid), public.submit_bid(uuid),
  public.withdraw_bid(uuid), public.my_bid_receipts(uuid), public.office_bid_index(uuid)
  to authenticated;
