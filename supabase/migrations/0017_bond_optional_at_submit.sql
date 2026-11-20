-- 0017_bond_optional_at_submit: the bid bond may be cured after submit (slice 2b, Task 3b, Ruling 7).
--
-- A bidder may submit a bid whose bond choice is "electronic" with NO bid_bond file. At close, app.bond_cure (0016)
-- already treats an electronic choice with no sealed bid_bond file as missing, so that bid enters the cure and the
-- bidder has until the cure deadline to upload it (submit_cure_bond) or the bid is non-responsive.
--   * The bond CHOICE stays required where bonds are required: bond_choice_missing is unchanged.
--   * Print-for-signature stays gated on the choice and the apprentice answer (Ruling 6, unchanged).
--   * app.required_bid_slots is unchanged: it still describes which slots the bid offers (the form still shows
--     the bid_bond slot). Only the submit check changes: upload_missing ignores the bid_bond slot.
-- bid_draft_problems: the 0015 body, except the upload_missing check skips the bid_bond slot. Code order is kept.

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

  -- The bond file is curable after submit (Ruling 7), so its absence never blocks submitting.
  if exists (select 1 from unnest(app.required_bid_slots(v_snap, v_draft.bid_bond_choice)) r(slot)
              where r.slot <> 'bid_bond'
                and not exists (select 1 from public.bid_draft_files f where f.bid_id = p_bid_id and f.slot = r.slot)) then
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

revoke all on function app.bid_draft_problems(uuid) from public, anon, authenticated, service_role;
