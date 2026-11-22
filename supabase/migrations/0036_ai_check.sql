-- 0036_ai_check: the advisory AI document check (slice 3, Task 1).
--
-- Postgres owns who may run a check, when, the caps, and the append-only record. TypeScript owns the checklist's
-- comparisons and the model call (src/domain/aicheck, src/server/aicheck). Nothing here writes bid_outcomes,
-- flagged_decisions, recaps or awards: the check is advisory only.
--
--   * Scans of signed originals (and paper bid bonds) are attached by office staff after close, stored in the sealed
--     bid-files bucket at bids/{bid_id}/{log_entry_id}/scan-{name}.pdf (the path shape app.path_bid_id already
--     parses). Office may upload and read them only after close.
--   * ai_check_runs: one per run of a bid; at most one `running` per bid; a running run older than 10 minutes counts as
--     failed. recorded = true marks seeded results and has no API write path.
--   * ai_check_items / ai_check_reviews: append-only.
--   * Caps live in settings (admin-editable): runs per bid (recorded runs excluded), document calls per office user per
--     day and per day overall. A document call is reserved by begin_ai_check_document BEFORE the app calls the model:
--     the reservation checks run ownership, that the document is one of the run's bid's documents, that it hasn't
--     already been checked in this run (a failed call may be retried), and the caps. record_ai_check_document then
--     only accepts items for a reserved document. A document with no file ("Scan not attached") reserves nothing and
--     costs nothing. "Today" is app.today() in settings.timezone.
--
-- Error codes: not_authorized, not_found, sealed, invalid_state, invalid_data, reason_required, ai_check_running,
-- ai_cap_reached, scan_too_large, not_scannable.

-- ---------------------------------------------------------------------------
-- Caps
-- ---------------------------------------------------------------------------
alter table public.settings
  add column ai_runs_per_bid int not null default 3 check (ai_runs_per_bid >= 0),
  add column ai_calls_per_user_day int not null default 50 check (ai_calls_per_user_day >= 0),
  add column ai_calls_per_day int not null default 200 check (ai_calls_per_day >= 0);
grant update (ai_runs_per_bid, ai_calls_per_user_day, ai_calls_per_day) on public.settings to authenticated;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.bid_original_scans (
  id            uuid primary key default gen_random_uuid(),
  log_entry_id  uuid not null references public.bid_original_log (id),
  bid_id        uuid not null references public.bids (id),
  path          text not null unique,
  attached_by   uuid not null references public.profiles (user_id),
  attached_at   timestamptz not null default now(),
  superseded_by uuid references public.bid_original_scans (id)
);
create index bid_original_scans_entry_idx on public.bid_original_scans (log_entry_id);

create table public.ai_check_runs (
  id                   uuid primary key default gen_random_uuid(),
  bid_id               uuid not null references public.bids (id),
  started_by           uuid references public.profiles (user_id),
  started_at           timestamptz not null default now(),
  finished_at          timestamptz,
  status               text not null default 'running' check (status in ('running', 'done', 'failed')),
  model                text not null,
  bid_version          int not null,
  solicitation_version int not null,
  recorded             boolean not null default false
);
create unique index ai_check_runs_one_running on public.ai_check_runs (bid_id) where status = 'running';
create index ai_check_runs_bid_idx on public.ai_check_runs (bid_id, started_at desc);

create table public.ai_check_items (
  id            uuid primary key default gen_random_uuid(),
  run_id        uuid not null references public.ai_check_runs (id),
  document_kind text not null check (document_kind in
                  ('signed_form', 'bid_bond_scan', 'insurance', 'bid_bond', 'qualifications', 'references', 'current_work')),
  document_path text,
  item_code     text not null,
  method        text not null check (method in ('ai', 'rule')),
  result        text not null check (result in ('met', 'not_met', 'unclear')),
  page          int check (page is null or page > 0),
  excerpt       text check (excerpt is null or char_length(excerpt) <= 300),
  extracted     text,
  detail        text,
  call_failed   boolean not null default false,
  created_at    timestamptz not null default now()
);
create index ai_check_items_run_idx on public.ai_check_items (run_id);

-- One row per paid model call, reserved before the call (append-only).
create table public.ai_check_calls (
  id            uuid primary key default gen_random_uuid(),
  run_id        uuid not null references public.ai_check_runs (id),
  document_kind text not null,
  document_path text not null,
  reserved_by   uuid not null references public.profiles (user_id),
  reserved_at   timestamptz not null default now()
);
create index ai_check_calls_run_idx on public.ai_check_calls (run_id, document_path);
create index ai_check_calls_day_idx on public.ai_check_calls (reserved_at);

create table public.ai_check_reviews (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null references public.ai_check_items (id),
  decision    text not null check (decision in ('confirm', 'override')),
  reason      text,
  reviewed_by uuid not null references public.profiles (user_id),
  reviewed_at timestamptz not null default now(),
  constraint ai_check_reviews_override_reason check (decision = 'confirm' or btrim(coalesce(reason, '')) <> '')
);
create index ai_check_reviews_item_idx on public.ai_check_reviews (item_id, reviewed_at desc);

-- Append-only (bid_original_scans may only have superseded_by set, by attach_original_scan).
create trigger ai_check_items_append_only before update or delete on public.ai_check_items
  for each row execute function app.reject_change();
create trigger ai_check_items_no_truncate before truncate on public.ai_check_items
  for each statement execute function app.reject_change();
create trigger ai_check_calls_append_only before update or delete on public.ai_check_calls
  for each row execute function app.reject_change();
create trigger ai_check_calls_no_truncate before truncate on public.ai_check_calls
  for each statement execute function app.reject_change();
create trigger ai_check_reviews_append_only before update or delete on public.ai_check_reviews
  for each row execute function app.reject_change();
create trigger ai_check_reviews_no_truncate before truncate on public.ai_check_reviews
  for each statement execute function app.reject_change();

create function app.scan_superseded_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' or new.id is distinct from old.id or new.log_entry_id is distinct from old.log_entry_id
     or new.bid_id is distinct from old.bid_id or new.path is distinct from old.path
     or new.attached_by is distinct from old.attached_by or new.attached_at is distinct from old.attached_at
     or old.superseded_by is not null then
    raise exception 'bid_original_scans is append-only' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger bid_original_scans_append_only before update or delete on public.bid_original_scans
  for each row execute function app.scan_superseded_only();
create trigger bid_original_scans_no_truncate before truncate on public.bid_original_scans
  for each statement execute function app.reject_change();

revoke all on public.bid_original_scans, public.ai_check_runs, public.ai_check_items, public.ai_check_reviews,
  public.ai_check_calls
  from public, anon, authenticated, service_role;
alter table public.ai_check_calls enable row level security;
alter table public.bid_original_scans enable row level security;
alter table public.ai_check_runs enable row level security;
alter table public.ai_check_items enable row level security;
alter table public.ai_check_reviews enable row level security;

-- ---------------------------------------------------------------------------
-- The checklist codes per document kind. Kept in sync with src/domain/aicheck/checklist.ts by a parity test that
-- reads the marked block below.
-- ---------------------------------------------------------------------------
create function app.ai_check_codes(p_kind text)
returns text[]
language sql immutable
set search_path = ''
as $$
  select case p_kind
    -- aicheck-codes:start
    when 'signed_form' then array['signature_present', 'amount_in_words', 'addenda_listed', 'form_version', 'resident_certificate']
    when 'insurance' then array['insured_name', 'coverage_dates']
    when 'bid_bond' then array['principal_name', 'obligee', 'surety_signature']
    when 'bid_bond_scan' then array['principal_name', 'obligee', 'surety_signature']
    when 'qualifications' then array['document_matches_slot']
    when 'references' then array['document_matches_slot']
    when 'current_work' then array['document_matches_slot']
    -- aicheck-codes:end
  end;
$$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Lock a counted bid for an office action after close. not_authorized / not_found / sealed.
create function app.ai_check_bid(p_bid_id uuid)
returns public.bids
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid public.bids;
  v_version int;
begin
  perform app.require_office();
  select b.* into v_bid from public.bids b where b.id = p_bid_id;
  v_version := app.latest_version(p_bid_id);
  if v_bid.id is null or v_version is null or app.bid_excluded(p_bid_id, v_version) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  perform 1 from public.solicitations s where s.id = v_bid.solicitation_id for share;
  if not app.bids_closed(v_bid.solicitation_id) then
    raise exception 'sealed' using errcode = 'P0001';
  end if;
  return v_bid;
end;
$$;

-- Fail a stale running run (older than 10 minutes).
create function app.ai_check_expire_stale(p_bid_id uuid)
returns void
language sql security definer
set search_path = ''
as $$
  update public.ai_check_runs r
     set status = 'failed', finished_at = now()
   where r.bid_id = p_bid_id and r.status = 'running' and r.started_at < now() - interval '10 minutes';
$$;

-- Document calls reserved today (live runs only), by one office user or overall.
create function app.ai_check_calls_today(p_user uuid)
returns int
language sql stable security definer
set search_path = ''
as $$
  select count(*)::int
    from public.ai_check_calls c
   where (p_user is null or c.reserved_by = p_user)
     and (c.reserved_at at time zone coalesce((select s.timezone from public.settings s where s.id = 1),
                                              'America/Denver'))::date = app.today();
$$;

revoke all on function app.ai_check_codes(text), app.ai_check_bid(uuid), app.ai_check_expire_stale(uuid),
  app.ai_check_calls_today(uuid), app.scan_superseded_only()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Storage: office may upload and read scans after close.
-- Scan path: bids/{bid_id}/{log_entry_id}/scan-{name}.pdf, for a non-void log entry of that bid.
-- ---------------------------------------------------------------------------
create function app.scan_path_entry(p_name text)
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select case when app.path_bid_id(p_name) is not null and split_part(p_name, '/', 4) like 'scan-%.pdf'
              then split_part(p_name, '/', 3)::uuid end;
$$;

create function app.can_upload_scan(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select app.is_office() and exists (
    select 1 from public.bid_original_log l
     where l.id = app.scan_path_entry(p_name)
       and l.bid_id = app.path_bid_id(p_name)
       and l.voids_entry_id is null
       and not exists (select 1 from public.bid_original_log v where v.voids_entry_id = l.id)
       and app.bids_closed(l.solicitation_id));
$$;

create function app.can_read_scan(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select app.is_office() and exists (
    select 1 from public.bid_original_scans sc
      join public.bids b on b.id = sc.bid_id
     where sc.path = p_name and app.bids_closed(b.solicitation_id));
$$;

revoke all on function app.scan_path_entry(text), app.can_upload_scan(text), app.can_read_scan(text)
  from public, anon, authenticated, service_role;
grant execute on function app.can_upload_scan(text), app.can_read_scan(text), app.scan_path_entry(text)
  to authenticated;

create policy bid_scans_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'bid-files' and app.can_upload_scan(name));
create policy bid_scans_read on storage.objects for select to authenticated
  using (bucket_id = 'bid-files' and app.can_read_scan(name));

-- ---------------------------------------------------------------------------
-- attach_original_scan
-- ---------------------------------------------------------------------------
create function public.attach_original_scan(p_log_entry_id uuid, p_path text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_entry public.bid_original_log;
  v_bid   public.bids;
  v_size  bigint;
  v_id    uuid;
begin
  perform app.require_office();
  select l.* into v_entry from public.bid_original_log l where l.id = p_log_entry_id;
  if v_entry.id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  v_bid := app.ai_check_bid(v_entry.bid_id);
  if v_entry.voids_entry_id is not null
     or exists (select 1 from public.bid_original_log v where v.voids_entry_id = v_entry.id) then
    raise exception 'not_scannable' using errcode = 'P0001';
  end if;
  if p_path is null or app.path_bid_id(p_path) is distinct from v_bid.id
     or app.scan_path_entry(p_path) is distinct from v_entry.id then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  select (o.metadata ->> 'size')::bigint into v_size
    from storage.objects o where o.bucket_id = 'bid-files' and o.name = p_path;
  if not found then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if v_size is not null and v_size > 20971520 then
    raise exception 'scan_too_large' using errcode = 'P0001';
  end if;

  perform 1 from public.bid_original_scans sc where sc.log_entry_id = v_entry.id for update;
  insert into public.bid_original_scans (log_entry_id, bid_id, path, attached_by)
  values (v_entry.id, v_bid.id, p_path, auth.uid()) returning id into v_id;
  update public.bid_original_scans sc set superseded_by = v_id
   where sc.log_entry_id = v_entry.id and sc.id <> v_id and sc.superseded_by is null;
  perform app.bid_audit(v_bid, 'attach_original_scan',
                        jsonb_build_object('log_entry_id', v_entry.id, 'scan_id', v_id, 'item', v_entry.item));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Run lifecycle
-- ---------------------------------------------------------------------------
create function public.start_ai_check(p_bid_id uuid, p_model text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid  public.bids;
  v_cap  int;
  v_used int;
  v_id   uuid;
  v_sol_version int;
begin
  v_bid := app.ai_check_bid(p_bid_id);
  if p_model is null or btrim(p_model) = '' then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  perform 1 from public.bids b where b.id = v_bid.id for no key update;
  perform app.ai_check_expire_stale(v_bid.id);
  if exists (select 1 from public.ai_check_runs r where r.bid_id = v_bid.id and r.status = 'running') then
    raise exception 'ai_check_running' using errcode = 'P0001';
  end if;
  select s.ai_runs_per_bid into v_cap from public.settings s where s.id = 1;
  select count(*)::int into v_used from public.ai_check_runs r where r.bid_id = v_bid.id and not r.recorded;
  if v_used >= coalesce(v_cap, 3) then
    raise exception 'ai_cap_reached' using errcode = 'P0001';
  end if;
  select v.solicitation_version into v_sol_version
    from public.bid_versions v where v.bid_id = v_bid.id and v.version = app.latest_version(v_bid.id);
  insert into public.ai_check_runs (bid_id, started_by, started_at, model, bid_version, solicitation_version)
  values (v_bid.id, auth.uid(), clock_timestamp(), btrim(p_model), app.latest_version(v_bid.id), v_sol_version)
  returning id into v_id;
  perform app.bid_audit(v_bid, 'start_ai_check', jsonb_build_object('run_id', v_id, 'model', btrim(p_model)));
  return v_id;
end;
$$;

-- Lock a run the caller started and that is still running (not stale). invalid_state otherwise.
create function app.ai_check_own_run(p_run_id uuid)
returns public.ai_check_runs
language plpgsql security definer
set search_path = ''
as $$
declare
  v_run public.ai_check_runs;
begin
  perform app.require_office();
  select r.* into v_run from public.ai_check_runs r where r.id = p_run_id for update;
  if v_run.id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  perform app.ai_check_bid(v_run.bid_id);
  if v_run.started_by is distinct from auth.uid() or v_run.status <> 'running' or v_run.recorded
     or v_run.started_at < now() - interval '10 minutes' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  return v_run;
end;
$$;
revoke all on function app.ai_check_own_run(uuid) from public, anon, authenticated, service_role;

-- Reserve one document of a running run before the model call. Returns the run's bid and solicitation, which the app
-- uses for the portal facts (never the client's ids). A null path (no scan attached) reserves nothing.
create function public.begin_ai_check_document(p_run_id uuid, p_kind text, p_path text)
returns table (bid_id uuid, solicitation_id uuid)
language plpgsql security definer
set search_path = ''
as $$
declare
  v_run       public.ai_check_runs;
  v_sol       uuid;
  v_user_cap  int;
  v_total_cap int;
begin
  v_run := app.ai_check_own_run(p_run_id);
  if not exists (select 1 from public.ai_check_documents(v_run.bid_id) d
                  where d.document_kind = p_kind and d.path is not distinct from p_path) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  select b.solicitation_id into v_sol from public.bids b where b.id = v_run.bid_id;

  if p_path is not null then
    perform pg_advisory_xact_lock(hashtext('ai_check_calls'));
    -- Not again in this run if a call for it is in flight (more reservations than recorded results) or it already has
    -- a result that wasn't a failed call. A document whose every result was a failed call may be begun again.
    if (select count(*) from public.ai_check_calls c where c.run_id = v_run.id and c.document_path = p_path)
         > (select count(distinct i.created_at) from public.ai_check_items i
             where i.run_id = v_run.id and i.document_path = p_path)
       or exists (select 1 from public.ai_check_items i
                   where i.run_id = v_run.id and i.document_path = p_path and not i.call_failed) then
      raise exception 'invalid_state' using errcode = 'P0001';
    end if;
    select s.ai_calls_per_user_day, s.ai_calls_per_day into v_user_cap, v_total_cap
      from public.settings s where s.id = 1;
    if app.ai_check_calls_today(auth.uid()) >= coalesce(v_user_cap, 50)
       or app.ai_check_calls_today(null) >= coalesce(v_total_cap, 200) then
      raise exception 'ai_cap_reached' using errcode = 'P0001';
    end if;
    insert into public.ai_check_calls (run_id, document_kind, document_path, reserved_by, reserved_at)
    values (v_run.id, p_kind, p_path, auth.uid(), clock_timestamp());
  end if;
  return query select v_run.bid_id, v_sol;
end;
$$;

-- p_items: [{document_kind, document_path, item_code, method, result, page, excerpt, extracted, detail, call_failed}]
-- for one document. A document with a file must have been begun (reserved) and not yet recorded since.
create function public.record_ai_check_document(p_run_id uuid, p_items jsonb)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_run   public.ai_check_runs;
  v_kind  text;
  v_path  text;
  v_at    timestamptz := clock_timestamp();
begin
  v_run := app.ai_check_own_run(p_run_id);
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  select min(x ->> 'document_kind'), min(x ->> 'document_path') into v_kind, v_path
    from jsonb_array_elements(p_items) x;
  if (select count(distinct x ->> 'document_kind') from jsonb_array_elements(p_items) x) <> 1
     or (select count(distinct coalesce(x ->> 'document_path', '')) from jsonb_array_elements(p_items) x) <> 1
     or app.ai_check_codes(v_kind) is null
     or exists (select 1 from jsonb_array_elements(p_items) x
                 where not ((x ->> 'item_code') = any (app.ai_check_codes(v_kind)))) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  if v_path is not null then
    perform pg_advisory_xact_lock(hashtext('ai_check_calls'));
    -- One recorded result per reserved call: more reservations than recorded results for this document.
    if (select count(*) from public.ai_check_calls c
         where c.run_id = v_run.id and c.document_path = v_path and c.document_kind = v_kind
           and c.reserved_by = auth.uid())
       <= (select count(distinct i.created_at) from public.ai_check_items i
            where i.run_id = v_run.id and i.document_path = v_path) then
      raise exception 'invalid_state' using errcode = 'P0001';
    end if;
  elsif not exists (select 1 from public.ai_check_documents(v_run.bid_id) d
                     where d.document_kind = v_kind and d.path is null) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  insert into public.ai_check_items (run_id, document_kind, document_path, item_code, method, result, page, excerpt,
                                     extracted, detail, call_failed, created_at)
  select v_run.id, x ->> 'document_kind', x ->> 'document_path', x ->> 'item_code', x ->> 'method', x ->> 'result',
         (x ->> 'page')::int, left(x ->> 'excerpt', 300), x ->> 'extracted', x ->> 'detail',
         coalesce((x ->> 'call_failed')::boolean, false), v_at
    from jsonb_array_elements(p_items) x;
exception
  when check_violation or invalid_text_representation or not_null_violation then
    raise exception 'invalid_data' using errcode = 'P0001';
end;
$$;

create function public.finish_ai_check(p_run_id uuid, p_status text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_run public.ai_check_runs;
  v_bid public.bids;
begin
  if p_status is null or p_status not in ('done', 'failed') then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  v_run := app.ai_check_own_run(p_run_id);
  update public.ai_check_runs r set status = p_status, finished_at = now() where r.id = v_run.id;
  select b.* into v_bid from public.bids b where b.id = v_run.bid_id;
  perform app.bid_audit(v_bid, 'finish_ai_check', jsonb_build_object('run_id', v_run.id, 'status', p_status));
end;
$$;

create function public.review_ai_check_item(p_item_id uuid, p_decision text, p_reason text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid_id uuid;
begin
  perform app.require_office();
  select r.bid_id into v_bid_id
    from public.ai_check_items i join public.ai_check_runs r on r.id = i.run_id where i.id = p_item_id;
  if v_bid_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  perform app.ai_check_bid(v_bid_id);
  if p_decision is null or p_decision not in ('confirm', 'override') then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if p_decision = 'override' and btrim(coalesce(p_reason, '')) = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;
  insert into public.ai_check_reviews (item_id, decision, reason, reviewed_by, reviewed_at)
  values (p_item_id, p_decision, nullif(btrim(coalesce(p_reason, '')), ''), auth.uid(), clock_timestamp());
end;
$$;

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------
create function public.bid_ai_check(p_bid_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_bid  public.bids;
  v_run  public.ai_check_runs;
  v_set  public.settings;
  v_used int;
begin
  v_bid := app.ai_check_bid(p_bid_id);
  select s.* into v_set from public.settings s where s.id = 1;
  select r.* into v_run from public.ai_check_runs r where r.bid_id = v_bid.id
   order by r.started_at desc, r.id desc limit 1;
  select count(*)::int into v_used from public.ai_check_runs r where r.bid_id = v_bid.id and not r.recorded;
  return jsonb_build_object(
    'run', case when v_run.id is null then null else jsonb_build_object(
      'id', v_run.id, 'status', case when v_run.status = 'running' and v_run.started_at < now() - interval '10 minutes'
                                     then 'failed' else v_run.status end,
      'startedAt', v_run.started_at, 'finishedAt', v_run.finished_at, 'model', v_run.model,
      'recorded', v_run.recorded, 'startedByMe', v_run.started_by = auth.uid(),
      'bidVersion', v_run.bid_version, 'solicitationVersion', v_run.solicitation_version) end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', i.id, 'documentKind', i.document_kind, 'documentPath', i.document_path, 'code', i.item_code,
               'method', i.method, 'result', i.result, 'page', i.page, 'excerpt', i.excerpt,
               'extracted', i.extracted, 'detail', i.detail, 'callFailed', i.call_failed,
               'review', (select jsonb_build_object('decision', rv.decision, 'reason', rv.reason,
                                                    'reviewedAt', rv.reviewed_at,
                                                    'reviewedBy', (select p.display_name from public.profiles p
                                                                    where p.user_id = rv.reviewed_by))
                            from public.ai_check_reviews rv where rv.item_id = i.id
                           order by rv.reviewed_at desc, rv.id desc limit 1))
             order by i.created_at, i.document_kind, i.item_code)
        from (select distinct on (x.document_kind, coalesce(x.document_path, ''), x.item_code) x.*
                from public.ai_check_items x where x.run_id = v_run.id
               order by x.document_kind, coalesce(x.document_path, ''), x.item_code, x.created_at desc, x.id desc) i),
      '[]'::jsonb),
    'runsUsed', v_used,
    'runsLeft', greatest(coalesce(v_set.ai_runs_per_bid, 3) - v_used, 0),
    'callsLeftUser', greatest(coalesce(v_set.ai_calls_per_user_day, 50) - app.ai_check_calls_today(auth.uid()), 0),
    'callsLeftTotal', greatest(coalesce(v_set.ai_calls_per_day, 200) - app.ai_check_calls_today(null), 0));
end;
$$;

create function public.ai_check_documents(p_bid_id uuid)
returns table (document_kind text, path text)
language plpgsql security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_bid public.bids;
  v_version public.bid_versions;
begin
  v_bid := app.ai_check_bid(p_bid_id);
  select v.* into v_version from public.bid_versions v
   where v.bid_id = v_bid.id and v.version = app.latest_version(v_bid.id);

  -- The signed form's current scan (null path when none).
  return query
    select 'signed_form'::text,
           (select sc.path from public.bid_original_log l
              join public.bid_original_scans sc on sc.log_entry_id = l.id and sc.superseded_by is null
             where l.bid_id = v_bid.id and l.version = v_version.version and l.item = 'signed_form'
               and l.voids_entry_id is null
               and not exists (select 1 from public.bid_original_log v where v.voids_entry_id = l.id)
             order by sc.attached_at desc limit 1);

  -- Uploaded documents of the latest version, in a fixed order.
  return query
    select vf.slot::text, vf.path
      from public.bid_version_files vf
     where vf.version_id = v_version.id
       and vf.slot in ('insurance', 'bid_bond', 'qualifications', 'references', 'current_work')
     order by array_position(array['insurance', 'bid_bond', 'qualifications', 'references', 'current_work'],
                             vf.slot::text);

  -- A paper bid bond's scan, when the bond is paper and required.
  if v_version.bid_bond_choice = 'paper' then
    return query
      select 'bid_bond_scan'::text,
             (select sc.path from public.bid_original_log l
                join public.bid_original_scans sc on sc.log_entry_id = l.id and sc.superseded_by is null
               where l.bid_id = v_bid.id and l.version = v_version.version and l.item = 'bid_bond'
                 and l.voids_entry_id is null
                 and not exists (select 1 from public.bid_original_log v where v.voids_entry_id = l.id)
               order by sc.attached_at desc limit 1);
  end if;
end;
$$;

-- Every scannable log entry of a solicitation (receipts that aren't voided), with its bid and current scan, for the
-- originals panel (office, after close). The bid id isn't otherwise readable through the API: bid_original_log grants
-- no bid_id column.
create function public.original_scans(p_solicitation_id uuid)
returns table (log_entry_id uuid, bid_id uuid, scan_id uuid, path text, attached_at timestamptz)
language plpgsql stable security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform app.require_office();
  if not app.bids_closed(p_solicitation_id) then
    raise exception 'sealed' using errcode = 'P0001';
  end if;
  return query
    select l.id, l.bid_id, sc.id, sc.path, sc.attached_at
      from public.bid_original_log l
      left join public.bid_original_scans sc on sc.log_entry_id = l.id and sc.superseded_by is null
     where l.solicitation_id = p_solicitation_id
       and l.voids_entry_id is null
       and not exists (select 1 from public.bid_original_log v where v.voids_entry_id = l.id);
end;
$$;

revoke all on function public.attach_original_scan(uuid, text), public.start_ai_check(uuid, text),
  public.record_ai_check_document(uuid, jsonb), public.begin_ai_check_document(uuid, text, text), public.finish_ai_check(uuid, text),
  public.review_ai_check_item(uuid, text, text), public.bid_ai_check(uuid), public.ai_check_documents(uuid),
  public.original_scans(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.attach_original_scan(uuid, text), public.start_ai_check(uuid, text),
  public.record_ai_check_document(uuid, jsonb), public.begin_ai_check_document(uuid, text, text), public.finish_ai_check(uuid, text),
  public.review_ai_check_item(uuid, text, text), public.bid_ai_check(uuid), public.ai_check_documents(uuid),
  public.original_scans(uuid)
  to authenticated;
