-- 0016_bond_cure: the bid-bond cure period (slice 2b, Task 3).
--
-- Bonds are required when the estimate is at least $150,000 (app.bonds_required). After close, a bid's bond is
-- MISSING when its latest, non-withdrawn version chose
--   * 'electronic' and that sealed version holds no bid_bond file, or
--   * 'paper' and no paper bond original was counted by the bid due time (app.bond_original_received, 0012),
-- A missing bond opens a cure period ending at the CURE DEADLINE: 17:00 in
-- settings.timezone on the next business day (not Saturday, Sunday or a public.holidays day) after the local date
-- of bid_due_at.
--
-- Cured by either of:
--   * the bidder's electronic upload (submit_cure_bond -> bid_cure_files) with uploaded_at < deadline. The upload
--     is refused at or after the deadline, judged on clock_timestamp() after the bid row lock (Ruling 8);
--   * the office logging the paper bond through the 2a originals log (log_bid_original, item 'bid_bond', which
--     already allows logging after close), counted with the 2a rule and the cure deadline as the cutoff:
--     received_at <= deadline and logged_at <= deadline, not voided. logged_at is the database clock after the
--     bid lock, so an entry cannot be back-dated into the cure period.
--
-- Status (app.bond_cure): not_required | ok | cured | pending | failed. 'failed' is DERIVED, never stored: the bid is
-- non-responsive with the reason 'bid bond not received by the cure deadline' once now() >= deadline and it was
-- not cured. No scheduler and no override. The failure is audited (bid_cure_determination) on the first cure read
-- after the deadline, and again only when the derived result changes (app.audit_cure_determination, the 0012
-- pattern with an advisory lock). Task 4's review_bids reuses it.
--
-- RULING 3 (deadline frozen at close): the deadline is stored once in public.cure_deadlines, computed from
-- bid_due_at, the time zone and the holiday table as they stand at close:
--   * the first cure read or write after close stores it (app.freeze_cure_due: my_bid_cure, submit_cure_bond;
--     Task 4's lock_evaluation should call it too);
--   * a statement trigger on public.holidays (insert/update/delete/truncate) and on settings.timezone runs BEFORE
--     the change and freezes every closed, still-unfrozen solicitation with the table as it was. So no holiday
--     or time-zone edit made after close can reach a closed solicitation's deadline, even if nobody read it yet.
--   Until close nothing is stored and the deadline follows the live table (app.cure_due_at). app.cure_deadline
--   reads the frozen row when its bid_due_at matches the solicitation's (published rows are frozen, so it always
--   does outside test fixtures), else the live computation.
--   Residual gap: a holiday edit whose statement runs just before a due time but commits just after it is not
--   frozen (milliseconds; the same window every clock_timestamp() check has).
--
-- Sealing: before close nothing changes (my_bid_cure answers not_required/null; storage uploads use the 0009 rule).
-- A cure upload is new data after close: only the owning bidder and the office can read it.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.cure_deadlines (
  solicitation_id uuid primary key references public.solicitations (id),
  bid_due_at      timestamptz not null,
  cure_due_at     timestamptz not null,
  frozen_at       timestamptz not null default clock_timestamp()
);

create table public.bid_cure_files (
  id          uuid primary key default gen_random_uuid(),
  bid_id      uuid not null references public.bids (id),
  version     int not null,
  path        text not null unique,
  file_name   text not null check (btrim(file_name) <> ''),
  object_id   uuid,
  object_size bigint,
  object_etag text,
  uploaded_by uuid not null references public.profiles (user_id),
  uploaded_at timestamptz not null,
  foreign key (bid_id, version) references public.bid_versions (bid_id, version)
);
create index bid_cure_files_bid_version_idx on public.bid_cure_files (bid_id, version);

create trigger cure_deadlines_append_only
  before update or delete on public.cure_deadlines for each row execute function app.reject_change();
create trigger cure_deadlines_no_truncate
  before truncate on public.cure_deadlines for each statement execute function app.reject_change();
create trigger bid_cure_files_append_only
  before update or delete on public.bid_cure_files for each row execute function app.reject_change();
create trigger bid_cure_files_no_truncate
  before truncate on public.bid_cure_files for each statement execute function app.reject_change();

revoke all on public.cure_deadlines, public.bid_cure_files from anon, authenticated, service_role;
alter table public.cure_deadlines enable row level security;
alter table public.bid_cure_files enable row level security;
-- No policies and no privileges: read only through the definer functions below.

-- ---------------------------------------------------------------------------
-- app.cure_due_at: the live computation (Review Focus 1). 17:00 local on the next business day.
-- ---------------------------------------------------------------------------
create function app.cure_due_at(p_bid_due_at timestamptz)
returns timestamptz
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_tz  text := coalesce((select s.timezone from public.settings s where s.id = 1), 'America/Denver');
  v_day date;
begin
  if p_bid_due_at is null then
    return null;
  end if;
  v_day := (p_bid_due_at at time zone v_tz)::date;
  for i in 1..366 loop
    v_day := v_day + 1;
    if extract(isodow from v_day) < 6
       and not exists (select 1 from public.holidays h where h.day = v_day) then
      return (v_day + time '17:00') at time zone v_tz;
    end if;
  end loop;
  raise exception 'invalid_data' using errcode = 'P0001';  -- a year of holidays: misconfigured
end;
$$;

-- The solicitation's deadline: the frozen value (Ruling 3) or, before anything is frozen, the live computation.
create function app.cure_deadline(p_solicitation_id uuid)
returns timestamptz
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    (select c.cure_due_at from public.cure_deadlines c
      where c.solicitation_id = s.id and c.bid_due_at = s.bid_due_at),
    app.cure_due_at(s.bid_due_at))
    from public.solicitations s where s.id = p_solicitation_id;
$$;

-- Freeze one solicitation's deadline if it is closed (idempotent). Returns the deadline.
create function app.freeze_cure_due(p_solicitation_id uuid)
returns timestamptz
language plpgsql volatile security definer
set search_path = ''
as $$
begin
  insert into public.cure_deadlines (solicitation_id, bid_due_at, cure_due_at)
  select s.id, s.bid_due_at, app.cure_due_at(s.bid_due_at)
    from public.solicitations s
   where s.id = p_solicitation_id and s.state = 'published' and s.bid_due_at <= clock_timestamp()
  on conflict (solicitation_id) do nothing;
  return app.cure_deadline(p_solicitation_id);
end;
$$;

-- Statement trigger: before a holiday or time-zone edit, freeze every closed solicitation not yet frozen, using the
-- table as it stands before the edit.
create function app.freeze_closed_cure_deadlines()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.cure_deadlines (solicitation_id, bid_due_at, cure_due_at)
  select s.id, s.bid_due_at, app.cure_due_at(s.bid_due_at)
    from public.solicitations s
   where s.state = 'published' and s.bid_due_at <= clock_timestamp()
     and not exists (select 1 from public.cure_deadlines c where c.solicitation_id = s.id)
  on conflict (solicitation_id) do nothing;
  return null;
end;
$$;

create trigger holidays_freeze_cure_deadlines
  before insert or update or delete or truncate on public.holidays
  for each statement execute function app.freeze_closed_cure_deadlines();
create trigger settings_timezone_freeze_cure_deadlines
  before update of timezone on public.settings
  for each statement execute function app.freeze_closed_cure_deadlines();

-- ---------------------------------------------------------------------------
-- app.bond_cure: the derived cure status of a bid's latest, non-withdrawn version, as of p_now (tests pass a
-- boundary instant; every caller passes now()). p_now decides only pending versus failed: cure evidence is judged
-- against the deadline (an upload cannot be stamped at or after it, and a log entry's logged_at is the clock).
-- ---------------------------------------------------------------------------
create function app.bond_cure(p_bid_id uuid, p_now timestamptz default now())
returns table (status text, due_at timestamptz)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_sol     public.solicitations;
  v_version public.bid_versions;
  v_missing boolean;
  v_due     timestamptz;
begin
  select s.* into v_sol
    from public.bids b join public.solicitations s on s.id = b.solicitation_id
   where b.id = p_bid_id;
  if not found or not app.bonds_required(v_sol.published_snapshot) then
    return query select 'not_required'::text, null::timestamptz;
    return;
  end if;
  select v.* into v_version from public.bid_versions v
   where v.bid_id = p_bid_id and v.version = app.latest_version(p_bid_id);
  if not found or app.is_withdrawn(p_bid_id, v_version.version) then
    return query select 'not_required'::text, null::timestamptz;
    return;
  end if;

  v_missing := case v_version.bid_bond_choice
    when 'electronic' then not exists (select 1 from public.bid_version_files f
                                        where f.version_id = v_version.id and f.slot = 'bid_bond')
    when 'paper' then not app.bond_original_received(p_bid_id, v_version.version, v_sol.bid_due_at)
    else false end;  -- no choice cannot be sealed (submit_bid requires one): the plan's rule names only the two
  if not v_missing then
    return query select 'ok'::text, null::timestamptz;
    return;
  end if;

  v_due := app.cure_deadline(v_sol.id);
  if exists (select 1 from public.bid_cure_files c
              where c.bid_id = p_bid_id and c.version = v_version.version
                and c.uploaded_at < v_due)
     or app.bond_original_received(p_bid_id, v_version.version, v_due) then
    return query select 'cured'::text, v_due;
  elsif p_now >= v_due then
    return query select 'failed'::text, v_due;
  else
    return query select 'pending'::text, v_due;
  end if;
end;
$$;

-- Audit the derived result once the deadline has passed: one bid_cure_determination row on the first read after
-- the deadline, another only when {version, status, reason} differs from the bid's latest such row. An advisory
-- lock per bid serializes concurrent first reads.
create function app.audit_cure_determination(p_bid public.bids, p_status text, p_due timestamptz)
returns void
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_detail jsonb;
begin
  if p_due is null or now() < p_due then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtext('cure:' || p_bid.id::text));
  v_detail := jsonb_build_object(
    'version', app.latest_version(p_bid.id), 'status', p_status, 'due_at', p_due,
    'reason', case when p_status = 'failed' then 'bid bond not received by the cure deadline' end);
  if (select a.detail from public.bid_audit_log a
       where a.bid_id = p_bid.id and a.action = 'bid_cure_determination'
       order by a.id desc limit 1) is distinct from v_detail then
    insert into public.bid_audit_log (solicitation_id, bid_id, actor_id, action, detail)
    values (p_bid.solicitation_id, p_bid.id, auth.uid(), 'bid_cure_determination', v_detail);
  end if;
end;
$$;

revoke all on function app.cure_due_at(timestamptz), app.cure_deadline(uuid), app.freeze_cure_due(uuid),
  app.freeze_closed_cure_deadlines(), app.bond_cure(uuid, timestamptz),
  app.audit_cure_determination(public.bids, text, timestamptz)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Storage rules (0009, replaced): uploads and reads of cure files.
-- ---------------------------------------------------------------------------
-- Upload: the 0009 rule (own bid, bidding open), or the caller's own bid after close while its cure is pending.
create or replace function app.can_upload_bid_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bids b
    where b.id = app.path_bid_id(p_name)
      and b.bidder_org_id = app.my_org()
      and (app.bidding_open(b.solicitation_id)
           or (app.bids_closed(b.solicitation_id)
               and (select c.status from app.bond_cure(b.id) c) = 'pending'))
  );
$$;

-- Read: the 0009 rule, or a recorded cure file: the owning bidder, and office staff after close.
create or replace function app.can_read_bid_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bids b
    where b.id = app.path_bid_id(p_name)
      and (
        (b.bidder_org_id = app.my_org()
         and exists (select 1 from public.bid_draft_files df where df.bid_id = b.id and df.path = p_name)
         and not exists (select 1 from public.bid_version_files vf where vf.path = p_name))
        or
        (app.is_office()
         and app.bids_closed(b.solicitation_id)
         and exists (
           select 1 from public.bid_versions v
           join public.bid_version_files vf on vf.version_id = v.id
           where v.bid_id = b.id
             and vf.path = p_name
             and v.version = app.latest_version(b.id)
             and not app.is_withdrawn(b.id, v.version)))
        or
        ((b.bidder_org_id = app.my_org() or (app.is_office() and app.bids_closed(b.solicitation_id)))
         and exists (select 1 from public.bid_cure_files cf where cf.bid_id = b.id and cf.path = p_name))
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- submit_cure_bond: record the bidder's uploaded bond for its latest version while the cure is open.
-- Order: not_authorized -> not_found -> invalid_state (not closed) -> invalid_state (no bond to cure) ->
-- cure_closed (clock after the lock, Ruling 8) -> invalid_data (path/name) -> invalid_bid (file_missing).
-- ---------------------------------------------------------------------------
create function public.submit_cure_bond(p_bid_id uuid, p_path text, p_file_name text)
returns timestamptz
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid     public.bids;
  v_due_bid timestamptz;
  v_status  text;
  v_due     timestamptz;
  v_version int;
  v_obj     storage.objects;
  v_at      timestamptz;
begin
  perform app.require_bidder();
  v_bid := app.lock_bid(p_bid_id);
  if not app.bids_closed(v_bid.solicitation_id) then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  perform app.freeze_cure_due(v_bid.solicitation_id);
  select c.status, c.due_at into v_status, v_due from app.bond_cure(v_bid.id, now()) c;
  -- 'failed' falls through to the clock check below, which always refuses it with cure_closed.
  if v_status not in ('pending', 'failed') then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if clock_timestamp() >= v_due then
    raise exception 'cure_closed' using errcode = 'P0001';
  end if;

  select s.bid_due_at into v_due_bid from public.solicitations s where s.id = v_bid.solicitation_id;
  if p_path is null or app.path_bid_id(p_path) is distinct from v_bid.id
     or btrim(coalesce(p_file_name, '')) = ''
     or exists (select 1 from public.bid_version_files vf where vf.path = p_path)
     or exists (select 1 from public.bid_draft_files df where df.path = p_path)
     or exists (select 1 from public.bid_cure_files cf where cf.path = p_path) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  select o.* into v_obj from storage.objects o
   where o.bucket_id = 'bid-files' and o.name = p_path
     and o.metadata->>'size' ~ '^[0-9]{1,18}$' and o.metadata->>'eTag' is not null;
  if not found then
    raise exception 'invalid_bid' using errcode = 'P0001', detail = 'file_missing';
  end if;
  -- New data after close only: an object uploaded before the bid due time (a leftover draft file) is refused.
  if v_obj.created_at < v_due_bid then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  v_version := app.latest_version(v_bid.id);
  v_at := clock_timestamp();
  insert into public.bid_cure_files (bid_id, version, path, file_name, object_id, object_size, object_etag,
                                     uploaded_by, uploaded_at)
  values (v_bid.id, v_version, p_path, left(btrim(p_file_name), 200), v_obj.id, (v_obj.metadata->>'size')::bigint,
          v_obj.metadata->>'eTag', auth.uid(), v_at);
  perform app.bid_audit(v_bid, 'submit_cure_bond', jsonb_build_object('version', v_version, 'path', p_path));
  return v_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- my_bid_cure: the caller's own bid only (not_found otherwise). Before close: not_required with no due time.
-- After close it freezes the deadline (Ruling 3) and audits a past-deadline result.
-- ---------------------------------------------------------------------------
create function public.my_bid_cure(p_bid_id uuid)
returns table (status text, due_at timestamptz)
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_bid    public.bids;
  v_status text;
  v_due    timestamptz;
begin
  perform app.require_bidder();
  select b.* into v_bid from public.bids b where b.id = p_bid_id and b.bidder_org_id = app.my_org();
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if not app.bids_closed(v_bid.solicitation_id) then
    return query select 'not_required'::text, null::timestamptz;
    return;
  end if;
  perform app.freeze_cure_due(v_bid.solicitation_id);
  select c.status, c.due_at into v_status, v_due from app.bond_cure(v_bid.id, now()) c;
  perform app.audit_cure_determination(v_bid, v_status, v_due);
  return query select v_status, v_due;
end;
$$;

revoke all on function public.submit_cure_bond(uuid, text, text), public.my_bid_cure(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.submit_cure_bond(uuid, text, text), public.my_bid_cure(uuid) to authenticated;
