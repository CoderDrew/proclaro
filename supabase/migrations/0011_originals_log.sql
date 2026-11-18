-- 0011_originals_log: the office's append-only log of mailed originals (signed bid forms and paper bid bonds),
-- with voids, and the helper Task 9 uses to decide whether a bid's signed original arrived in time.
--
-- Sealing: before close the office already sees every bid's reference, version and status (office_bid_index).
-- Logging reveals nothing beyond that:
--   * log_bid_original returns only the new entry's id. Every miss (unknown or malformed reference, unknown
--     version, another solicitation's reference, unknown solicitation) is the same `unknown_bid`.
--   * Office staff read the log through RLS, but not bid_id (column grant): the reference identifies the bid.
--   * The audit rows go to bid_audit_log, which the office reads only after close (0009 policy).
--
-- Timing: logged_at is the database's clock_timestamp() taken after log_bid_original holds the bid row lock
-- (FOR UPDATE, which conflicts with opening's FOR SHARE), and no API role can set it (no insert privilege; only the
-- functions write it). received_at is what the office says (default: the logged_at instant, never after it). An
-- original counts only when both are at or before bid_due_at (app.original_received), so a receipt back-dated
-- after close never counts, and neither does one whose transaction started before the due time but logged after
-- it. Logging after close is still allowed: it records the mail, it just does not count.
--
-- Correction: a void row (voids_entry_id + reason) that copies the target's bid, reference, version and item.
-- Voids are allowed at any time; a void made at any time cancels the receipt.

create type public.original_item as enum ('signed_form', 'bid_bond');

create table public.bid_original_log (
  id              uuid primary key default gen_random_uuid(),
  solicitation_id uuid not null references public.solicitations (id),
  bid_id          uuid not null references public.bids (id),
  reference       text not null,
  version         int not null,
  item            public.original_item not null,
  received_at     timestamptz,
  voids_entry_id  uuid unique references public.bid_original_log (id),
  reason          text,
  logged_by       uuid not null references public.profiles (user_id),
  logged_at       timestamptz not null default now(),
  foreign key (bid_id, version) references public.bid_versions (bid_id, version),
  constraint bid_original_log_receipt_or_void check (
    (voids_entry_id is null and received_at is not null and reason is null)
    or (voids_entry_id is not null and received_at is null and reason is not null and btrim(reason) <> '')),
  constraint bid_original_log_received_not_after_logged check (received_at is null or received_at <= logged_at)
);
create index bid_original_log_solicitation_id_idx on public.bid_original_log (solicitation_id);
create index bid_original_log_bid_version_idx on public.bid_original_log (bid_id, version);

-- Append-only, for every role (the owner included) by trigger, and by revoke for the API roles.
create trigger bid_original_log_append_only
  before update or delete on public.bid_original_log for each row execute function app.reject_change();
create trigger bid_original_log_no_truncate
  before truncate on public.bid_original_log for each statement execute function app.reject_change();

revoke all on public.bid_original_log from anon, authenticated, service_role;
-- Every column but bid_id. Writes go through the functions below only.
grant select (id, solicitation_id, reference, version, item, received_at, voids_entry_id, reason, logged_by, logged_at)
  on public.bid_original_log to authenticated;

alter table public.bid_original_log enable row level security;
create policy bid_original_log_read_office on public.bid_original_log for select to authenticated
  using ((select app.is_office()));

-- ---------------------------------------------------------------------------
-- app.original_received: a signed_form receipt for exactly this version, received and logged at or before the
-- due time, with no void row (a void made at any time counts). A receipt for another version never counts.
-- ---------------------------------------------------------------------------
create function app.original_received(p_bid_id uuid, p_version int, p_due timestamptz)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bid_original_log r
     where r.bid_id = p_bid_id
       and r.version = p_version
       and r.item = 'signed_form'
       and r.voids_entry_id is null
       and r.received_at <= p_due
       and r.logged_at <= p_due
       and not exists (select 1 from public.bid_original_log v where v.voids_entry_id = r.id));
$$;

revoke all on function app.original_received(uuid, int, timestamptz) from public, anon, authenticated, service_role;
-- Called only from definer functions (Task 9): no API role executes it.

-- ---------------------------------------------------------------------------
-- log_bid_original: office only. Error order: not_authorized -> invalid_data (no item) -> received_in_future ->
-- unknown_bid. The time check needs no bid data, so it comes before any lookup.
-- ---------------------------------------------------------------------------
create function public.log_bid_original(
  p_solicitation_id uuid, p_reference text, p_version int, p_item public.original_item,
  p_received_at timestamptz default null)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_logged   timestamptz;
  v_received timestamptz;
  v_bid      public.bids;
  v_id       uuid;
begin
  perform app.require_office();
  if p_item is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if p_received_at > clock_timestamp() then
    raise exception 'received_in_future' using errcode = 'P0001';
  end if;

  -- Any submitted version counts here, superseded and withdrawn included: the log records the mail.
  -- FOR UPDATE on the bid row conflicts with opening's FOR SHARE (app.open_bids_gate): an entry still in flight
  -- when the office opens is waited out, and an entry that waits behind an opening is stamped after it.
  select b.* into v_bid
    from public.bids b
   where b.solicitation_id = p_solicitation_id
     and b.reference = app.normalize_bid_reference(p_reference)
     and exists (select 1 from public.bid_versions v where v.bid_id = b.id and v.version = p_version)
     for update of b;
  if not found then
    raise exception 'unknown_bid' using errcode = 'P0001';
  end if;

  -- Stamped on the database's wall clock after the lock is held, not at transaction start: an entry whose
  -- transaction began before the due time but that commits after it is logged after it, and does not count.
  -- received_at defaults to the same instant, so received_at <= logged_at holds and neither is in the future.
  v_logged   := clock_timestamp();
  v_received := coalesce(p_received_at, v_logged);

  insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, received_at, logged_by,
                                       logged_at)
  values (v_bid.solicitation_id, v_bid.id, v_bid.reference, p_version, p_item, v_received, auth.uid(), v_logged)
  returning id into v_id;

  perform app.bid_audit(v_bid, 'log_bid_original',
                        jsonb_build_object('entry_id', v_id, 'reference', v_bid.reference, 'version', p_version,
                                           'item', p_item, 'received_at', v_received));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- void_bid_original: office only, any time. Error order: not_authorized -> reason_required -> not_found ->
-- invalid_state (the target is itself a void) -> already_voided.
-- ---------------------------------------------------------------------------
create function public.void_bid_original(p_entry_id uuid, p_reason text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_target public.bid_original_log;
  v_bid    public.bids;
  v_id     uuid;
begin
  perform app.require_office();
  if v_reason = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;

  -- Lock the target so two concurrent voids queue; the second then sees the first (unique index as backstop).
  select * into v_target from public.bid_original_log e where e.id = p_entry_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if v_target.voids_entry_id is not null then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.bid_original_log v where v.voids_entry_id = v_target.id) then
    raise exception 'already_voided' using errcode = 'P0001';
  end if;

  insert into public.bid_original_log (solicitation_id, bid_id, reference, version, item, voids_entry_id, reason,
                                       logged_by)
  values (v_target.solicitation_id, v_target.bid_id, v_target.reference, v_target.version, v_target.item,
          v_target.id, v_reason, auth.uid())
  returning id into v_id;

  select * into v_bid from public.bids b where b.id = v_target.bid_id;
  perform app.bid_audit(v_bid, 'void_bid_original',
                        jsonb_build_object('entry_id', v_id, 'voids_entry_id', v_target.id, 'reason', v_reason));
  return v_id;
end;
$$;

revoke all on function public.log_bid_original(uuid, text, int, public.original_item, timestamptz),
  public.void_bid_original(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.log_bid_original(uuid, text, int, public.original_item, timestamptz),
  public.void_bid_original(uuid, text)
  to authenticated;
