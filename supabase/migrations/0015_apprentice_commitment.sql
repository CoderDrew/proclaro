-- 0015_apprentice_commitment: the apprentice commitment on $1M+ bids (slice 2b, Task 2).
--
-- On a solicitation whose estimate is at least $1,000,000.00 (APPRENTICE_CREDIT_AT = 100,000,000 cents) the bid
-- form asks whether the bidder commits apprentices to at least 10% of the labor hours. The answer is SEALED exactly
-- like the prices:
--   * bid_drafts.apprentice_commitment is the bidder's draft answer. The 0009 update policy (own bid, bidding open)
--     covers it; authenticated gets a column grant for it, nothing else changes. submit_bid deletes the draft.
--   * bid_versions.apprentice_commitment is the sealed answer. bid_versions has no privileges for any API role
--     (0009), and the new column gets none either, so no role, service_role included, can read it.
-- bid_draft_problems gains two codes after the bond codes (TypeScript validateBidDraft, kept in step by the parity
-- fixtures): apprentice_missing (required and unanswered) and apprentice_not_required (answered when not asked).
-- apprentice_credit clause version 2 states the 1% evaluation credit; version 1 said participation only breaks
-- ties. Clauses are insert-only: solicitations already locked to version 1 keep it.

-- ---------------------------------------------------------------------------
-- Columns and privileges
-- ---------------------------------------------------------------------------
alter table public.bid_drafts   add column apprentice_commitment boolean;
alter table public.bid_versions add column apprentice_commitment boolean;

grant update (apprentice_commitment) on public.bid_drafts to authenticated;

-- ---------------------------------------------------------------------------
-- app.apprentice_required: p_snapshot is solicitations.published_snapshot ({data, clauses, settings}).
-- An unknown estimate counts as below the threshold, as for bonds.
-- ---------------------------------------------------------------------------
create function app.apprentice_required(p_snapshot jsonb)
returns boolean
language sql immutable security definer
set search_path = ''
as $$
  select coalesce((p_snapshot->'data'->>'estimateCents')::bigint >= 100000000, false);
$$;

revoke all on function app.apprentice_required(jsonb) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- bid_draft_problems: the 0010 body, then the apprentice codes after the bond codes.
--   apprentice_missing: the solicitation asks for the commitment and the draft has no answer.
--   apprentice_not_required: the solicitation does not ask, and the draft has an answer.
-- ---------------------------------------------------------------------------
create or replace function app.bid_draft_problems(p_bid_id uuid)
returns text[]
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_draft      public.bid_drafts;
  v_snap       jsonb;
  v_bonds      boolean;
  v_apprentice boolean;
  v_n_items    int;
  v_n_alts     int;
  v_problems   text[] := '{}';
  v_count      boolean := false;
  v_missing    boolean := false;
begin
  select * into v_draft from public.bid_drafts d where d.bid_id = p_bid_id;
  if not found then
    return v_problems;
  end if;
  select s.published_snapshot into v_snap
    from public.bids b join public.solicitations s on s.id = b.solicitation_id
   where b.id = p_bid_id;
  v_bonds      := app.bonds_required(v_snap);
  v_apprentice := app.apprentice_required(v_snap);
  v_n_items    := coalesce(jsonb_array_length(v_snap->'data'->'schedule'->'items'), 0);
  v_n_alts     := coalesce(jsonb_array_length(v_snap->'data'->'schedule'->'alternates'), 0);

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

  if v_apprentice and v_draft.apprentice_commitment is null then
    v_problems := array_append(v_problems, 'apprentice_missing');
  elsif not v_apprentice and v_draft.apprentice_commitment is not null then
    v_problems := array_append(v_problems, 'apprentice_not_required');
  end if;

  return v_problems;
end;
$$;

-- ---------------------------------------------------------------------------
-- submit_bid: the 0010 body, copying apprentice_commitment into the sealed version row.
-- ---------------------------------------------------------------------------
create or replace function public.submit_bid(p_bid_id uuid)
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
                                   apprentice_commitment, bidder_legal_name)
  select v_bid.id, v_draft.version, auth.uid(), v_draft.item_cents, v_draft.alternate_cents, v_draft.bid_bond_choice,
         v_draft.apprentice_commitment, o.name
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

-- create or replace keeps the 0010 privileges; restate them so this file stands on its own.
revoke all on function app.bid_draft_problems(uuid) from public, anon, authenticated, service_role;
revoke all on function public.submit_bid(uuid) from public, anon, authenticated, service_role;
grant execute on function public.submit_bid(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- apprentice_credit clause version 2 (insert-only; version 1 stays for existing locks).
-- ---------------------------------------------------------------------------
insert into public.clauses (key, version, body, created_by) values
('apprentice_credit', 2, $clause$# Apprenticeship Program Credit

Because of the size of this project, the bid form asks whether the bidder commits apprentices to at least ten percent of the labor hours on this project. A bid that makes this commitment is evaluated as if its price were one percent lower. The credit is used only to compare bids; the contract amount is the price bid.

A bidder that commits must be able to show, on request, that apprentices from an approved program will work those hours. Answering no does not make a bid ineligible.$clause$, null);
