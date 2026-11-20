-- 0014_funding_amount: the funding amount (slice 2b, Task 1), with Ruling 2 applied.
--
-- Ruling 2 (overrides the plan): the funding amount is CONFIDENTIAL until the recap is posted. Revealing a budget
-- before bids invites bidding to it. So:
--   * While the solicitation is being prepared, `fundingAmountCents` lives in `solicitations.data` like every other
--     field. Before publish that row is readable only by the owning agency and office staff (0001
--     solicitations_read_staff); anon and bidders see only published rows (solicitations_read_public).
--   * At publish the value is MOVED: publish_solicitation strips it from `data` and freezes it in
--     public.solicitation_funding, a separate append-only table readable only by the owning agency and office staff.
--     It is never written to `published_snapshot`, and a published row cannot hold it anywhere in `data` or
--     `published_snapshot` (check constraint), because the public read policy exposes those columns.
--   * The caller cannot put it in the snapshot (the snapshot is public): publish takes it as its own argument,
--     p_funding_cents, and refuses (snapshot_mismatch) a value that differs from the stored one, a missing value, or
--     a snapshot that carries a fundingAmountCents key at any depth. A missing, negative, fractional or non-numeric
--     stored value is invalid_data.
--   * Revealing it after the recap is posted is a later task's concern (the recap/award rows), not a policy here.
--
-- Rows published before this slice (seed data) have no funding row; app.funding_cents falls back to the published
-- estimate and app.funding_from_estimate says so.
--
-- New error string (errcode P0001): snapshot_mismatch.

-- ---------------------------------------------------------------------------
-- Required data keys: the 0006 list plus fundingAmountCents. Kept in sync with schema.ts by
-- src/domain/solicitation/requiredKeys.test.ts, which parses this list out of this file.
-- ---------------------------------------------------------------------------
create or replace function app.required_data_keys()
returns text[]
language sql immutable
set search_path = ''
as $$
  select array[
    -- required-data-keys:start
    'shortTitle', 'longTitle', 'category', 'summary', 'projectDescription', 'scopeNotes', 'specialProvisions',
    'location', 'requester', 'projectManager', 'estimateCents', 'fundingAmountCents', 'fundingSource',
    'fundingOther', 'federalFunds', 'releaseDate', 'adStart', 'adEnd', 'newspapers', 'questionsDue', 'answersDue',
    'bidDueDate', 'bidDueTime', 'tentativeAwardDate', 'estimatedStartDate', 'estimatedCompletionDate',
    'bidValidityDays', 'preBid', 'backgroundCheck', 'schedule', 'optionalSections', 'pageLimits', 'attachments'
    -- required-data-keys:end
  ]::text[];
$$;
revoke all on function app.required_data_keys() from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The confidential store: one frozen row per published solicitation.
-- ---------------------------------------------------------------------------
create table public.solicitation_funding (
  solicitation_id uuid primary key references public.solicitations (id),
  funding_cents   bigint not null check (funding_cents >= 0),
  frozen_at       timestamptz not null default now()
);

create trigger solicitation_funding_append_only
  before update or delete on public.solicitation_funding
  for each row execute function app.reject_change();
create trigger solicitation_funding_no_truncate
  before truncate on public.solicitation_funding
  for each statement execute function app.reject_change();

revoke all on public.solicitation_funding from public, anon, authenticated, service_role;
-- authenticated may read through RLS; nobody writes through the API (publish_solicitation is the only writer).
grant select on public.solicitation_funding to authenticated;

alter table public.solicitation_funding enable row level security;
-- Owning agency or office staff. Bidders' org is never a solicitation's agency, so they read 0 rows; anon has no
-- grant at all.
create policy solicitation_funding_read on public.solicitation_funding for select to authenticated
  using (app.can_see_solicitation(solicitation_id));

-- A published row is publicly readable (data and published_snapshot), so it must never carry the funding amount.
alter table public.solicitations add constraint solicitations_published_no_funding check (
  state <> 'published'
  or (not jsonb_path_exists(data, '$.**.fundingAmountCents')
      and not coalesce(jsonb_path_exists(published_snapshot, '$.**.fundingAmountCents'), false))
);

-- ---------------------------------------------------------------------------
-- Helpers for later tasks (recap, alternates, all-rejected): the funding amount for a solicitation, falling back
-- to the published estimate for rows published before this slice.
-- ---------------------------------------------------------------------------
create function app.funding_cents(p_id uuid)
returns bigint
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select f.funding_cents from public.solicitation_funding f where f.solicitation_id = p_id),
    (select coalesce((s.published_snapshot -> 'data' ->> 'estimateCents')::bigint, (s.data ->> 'estimateCents')::bigint)
       from public.solicitations s where s.id = p_id)
  );
$$;

create function app.funding_from_estimate(p_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select not exists (select 1 from public.solicitation_funding f where f.solicitation_id = p_id);
$$;

revoke all on function app.funding_cents(uuid), app.funding_from_estimate(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- publish_solicitation: the 0006 body plus the funding checks (right after invalid_paths) and the move into
-- solicitation_funding. A new argument, so the five-argument version is dropped: no caller can publish without
-- stating the funding amount it validated.
-- ---------------------------------------------------------------------------
drop function public.publish_solicitation(uuid, text, text, jsonb, timestamptz);

create function public.publish_solicitation(
  p_id uuid,
  p_rfb_path text,
  p_bid_form_path text,
  p_snapshot jsonb,
  p_bid_due_at timestamptz,
  p_funding_cents bigint)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row         public.solicitations;
  v_release     date;
  v_bid_due     timestamptz;
  v_funding_raw jsonb;
  v_funding_num numeric;
  v_funding     bigint;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'approved');
  if auth.uid() is distinct from v_row.reviewer_id and auth.uid() is distinct from v_row.checker_id then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  if p_rfb_path is null or btrim(p_rfb_path) = ''
     or p_bid_form_path is null or btrim(p_bid_form_path) = ''
     or p_snapshot is null or p_snapshot in ('null'::jsonb, '{}'::jsonb)
     or p_bid_due_at is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  if p_rfb_path <> format('solicitations/%s/v1/rfb.pdf', p_id)
     or p_bid_form_path <> format('solicitations/%s/v1/bid-form.pdf', p_id) then
    raise exception 'invalid_paths' using errcode = 'P0001';
  end if;

  -- 1. The stored funding amount is a non-negative whole number of cents.
  v_funding_raw := v_row.data -> 'fundingAmountCents';
  if jsonb_typeof(v_funding_raw) is distinct from 'number' then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  v_funding_num := v_funding_raw::numeric;
  if v_funding_num < 0 or v_funding_num <> trunc(v_funding_num) or v_funding_num > 9223372036854775807 then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  v_funding := v_funding_num::bigint;

  -- 2. The caller validated the same amount, and kept it out of the public snapshot.
  if p_funding_cents is distinct from v_funding
     or jsonb_path_exists(p_snapshot, '$.**.fundingAmountCents') then
    raise exception 'snapshot_mismatch' using errcode = 'P0001';
  end if;

  begin
    v_release := (v_row.data ->> 'releaseDate')::date;
  exception when others then
    v_release := null;
  end;
  if v_release is null or v_release < app.today() then
    raise exception 'invalid_release_date' using errcode = 'P0001';
  end if;

  v_bid_due := app.bid_due_at(v_row.data);
  if v_bid_due is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if p_bid_due_at <> v_bid_due then
    raise exception 'bid_due_mismatch' using errcode = 'P0001';
  end if;

  update public.solicitations s
     set state = 'published',
         version = 1,
         published_at = now(),
         release_date = v_release,
         rfb_path = p_rfb_path,
         bid_form_path = p_bid_form_path,
         published_snapshot = p_snapshot,
         bid_due_at = v_bid_due,
         data = v_row.data - 'fundingAmountCents'
   where s.id = p_id and s.state = 'approved';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.solicitation_funding (solicitation_id, funding_cents) values (p_id, v_funding);

  -- audit_log is staff-only (agency + office), like the funding amount itself.
  perform app.audit(p_id, 'publish_solicitation', jsonb_build_object(
    'from', 'approved', 'to', 'published', 'version', 1,
    'release_date', v_release, 'bid_due_at', v_bid_due,
    'rfb_path', p_rfb_path, 'bid_form_path', p_bid_form_path,
    'funding_cents', v_funding));
end;
$$;

revoke all on function public.publish_solicitation(uuid, text, text, jsonb, timestamptz, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.publish_solicitation(uuid, text, text, jsonb, timestamptz, bigint) to authenticated;
