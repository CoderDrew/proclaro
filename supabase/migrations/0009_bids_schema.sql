-- 0009_bids_schema: bid tables, sealing privileges and the sealed `bid-files` bucket.
--
-- Sealing model (spec "Approaches considered", option 1):
--   * Submitted versions, their files and withdrawals have NO privileges for any API role (anon, authenticated,
--     service_role). Reads after close go through security-definer functions (Task 9). service_role has BYPASSRLS,
--     so only a revoke stops it; these tables are owned by `postgres`, so the revoke holds.
--   * Bidders read and edit their own draft through RLS while bidding is open.
--   * `bid-files` storage objects are readable by the owning bidder only while draft-only, and by office staff only
--     at or after close and only for the latest, non-withdrawn version.
--   * ACCEPTED LIMIT (Ruling 3): storage.objects and storage.buckets are owned by supabase_storage_admin, which grants
--     service_role full access (arwdDxtm); a migration (run as `postgres`) cannot revoke that grant. The service-role
--     key can therefore read, replace or delete sealed bid files in Storage before close, and can update the
--     `bid-files` bucket row (for example make it public), like a database superuser. It can also read each
--     object's metadata, including storage.objects.owner and created_at: which bidder user uploaded a file for which
--     bid, and when. Prices in tables stay sealed from it, and app code never touches bid files with the admin
--     client. Tamper evidence (Ruling 5, 0010/0012) compares the storage.objects row recorded at submit with the
--     current one, so it catches replacements and deletions made through the Storage API; a write made directly to
--     the backing object store that leaves storage.objects unchanged is not detected.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.bid_bond_choice as enum ('electronic', 'paper');
create type public.bid_upload_slot as enum ('insurance', 'qualifications', 'references', 'current_work', 'bid_bond');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.bids (
  id              uuid primary key default gen_random_uuid(),
  solicitation_id uuid not null references public.solicitations (id),
  bidder_org_id   uuid not null references public.organizations (id),
  reference       text not null unique
                    constraint bids_reference_format check (reference ~ '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$'),
  created_by      uuid not null references public.profiles (user_id),
  created_at      timestamptz not null default now(),
  unique (solicitation_id, bidder_org_id)
);
create index bids_bidder_org_id_idx on public.bids (bidder_org_id);

-- The draft for the version it will become. Nulls are allowed while drafting.
create table public.bid_drafts (
  bid_id          uuid primary key references public.bids (id) on delete cascade,
  version         int not null check (version > 0),
  item_cents      bigint[] not null default '{}',
  alternate_cents bigint[] not null default '{}',
  bid_bond_choice public.bid_bond_choice,
  updated_at      timestamptz not null default now(),
  constraint bid_drafts_item_cents_range check (0 <= all (item_cents) and 999999999999 >= all (item_cents)),
  constraint bid_drafts_alternate_cents_range
    check (0 <= all (alternate_cents) and 999999999999 >= all (alternate_cents))
);

create table public.bid_draft_files (
  bid_id    uuid not null references public.bid_drafts (bid_id) on delete cascade,
  slot      public.bid_upload_slot not null,
  path      text not null unique,
  file_name text not null,
  primary key (bid_id, slot)
);

create table public.bid_versions (
  id              uuid primary key default gen_random_uuid(),
  bid_id          uuid not null references public.bids (id),
  version         int not null check (version > 0),
  submitted_at    timestamptz not null default now(),
  submitted_by    uuid not null references public.profiles (user_id),
  item_cents      bigint[] not null,
  alternate_cents bigint[] not null,
  bid_bond_choice public.bid_bond_choice,
  -- The bidder's legal name (organizations.name) as it stood at submit. The tabulation shows this, never the live
  -- organization name, so a later rename cannot change what the office reads.
  bidder_legal_name text not null check (btrim(bidder_legal_name) <> ''),
  unique (bid_id, version),
  constraint bid_versions_item_cents_range check (
    0 <= all (item_cents) and 999999999999 >= all (item_cents) and array_position(item_cents, null) is null),
  constraint bid_versions_alternate_cents_range check (
    0 <= all (alternate_cents) and 999999999999 >= all (alternate_cents)
    and array_position(alternate_cents, null) is null)
);

create table public.bid_version_files (
  version_id uuid not null references public.bid_versions (id),
  slot       public.bid_upload_slot not null,
  path       text not null unique,
  file_name  text not null,
  primary key (version_id, slot)
);

create table public.bid_withdrawals (
  bid_id       uuid not null,
  version      int not null,
  withdrawn_at timestamptz not null default now(),
  withdrawn_by uuid not null references public.profiles (user_id),
  primary key (bid_id, version),
  foreign key (bid_id, version) references public.bid_versions (bid_id, version)
);

create table public.bid_audit_log (
  id              bigserial primary key,
  solicitation_id uuid not null references public.solicitations (id),
  bid_id          uuid references public.bids (id),
  actor_id        uuid references public.profiles (user_id),
  action          text not null,
  detail          jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
create index bid_audit_log_solicitation_id_idx on public.bid_audit_log (solicitation_id);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- Open: published, released and before the due time. Closed: published and at or after the due time.
create function app.bidding_open(p_solicitation_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce((
    select s.state = 'published' and s.release_date <= app.today() and now() < s.bid_due_at
    from public.solicitations s where s.id = p_solicitation_id), false);
$$;

create function app.bids_closed(p_solicitation_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce((
    select s.state = 'published' and now() >= s.bid_due_at
    from public.solicitations s where s.id = p_solicitation_id), false);
$$;

create function app.latest_version(p_bid_id uuid)
returns int
language sql stable security definer
set search_path = ''
as $$
  select max(v.version) from public.bid_versions v where v.bid_id = p_bid_id;
$$;

create function app.is_withdrawn(p_bid_id uuid, p_version int)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.bid_withdrawals w where w.bid_id = p_bid_id and w.version = p_version);
$$;

-- Bid id from an object path `bids/{bid_id}/{upload_uuid}/{file}`, or null.
create function app.path_bid_id(p_name text)
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select case
    when p_name !~ '\.\.'
     and p_name ~ '^bids/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[^/]+$'
    then split_part(p_name, '/', 2)::uuid
  end;
$$;

-- Upload: the caller's own bid, while bidding is open.
create function app.can_upload_bid_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bids b
    where b.id = app.path_bid_id(p_name)
      and b.bidder_org_id = app.my_org()
      and app.bidding_open(b.solicitation_id)
  );
$$;

-- Read: (a) the owning bidder, for a file its draft references and no submitted version holds; or
-- (b) office staff, at or after close, for a file of the bid's latest version when that version is not withdrawn.
create function app.can_read_bid_file(p_name text)
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
      )
  );
$$;

-- Delete: the owning bidder, while open, never a file a submitted version holds.
create function app.can_delete_bid_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bids b
    where b.id = app.path_bid_id(p_name)
      and b.bidder_org_id = app.my_org()
      and app.bidding_open(b.solicitation_id)
      and not exists (select 1 from public.bid_version_files vf where vf.path = p_name)
  );
$$;

-- Trigger: a draft cannot reference a path one of its own bid's submitted versions already holds (it could never be
-- submitted). Raised as a unique violation, like the per-table constraint. It runs before RLS, so it acts only for
-- the caller's own bid and a path under that bid: anyone else falls through to RLS (42501), so it is not an oracle
-- for other bidders' paths, and the message never echoes the path.
create function app.bid_draft_file_path_unused()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if app.path_bid_id(new.path) = new.bid_id
     and exists (select 1 from public.bids b where b.id = new.bid_id and b.bidder_org_id = app.my_org())
     and exists (select 1 from public.bid_version_files vf
                 join public.bid_versions v on v.id = vf.version_id
                 where v.bid_id = new.bid_id and vf.path = new.path) then
    raise exception 'path_already_submitted' using errcode = '23505';
  end if;
  return new;
end;
$$;

-- Trigger: keep bid_drafts.updated_at current.
create function app.touch_bid_draft()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function app.bidding_open(uuid), app.bids_closed(uuid), app.latest_version(uuid),
  app.is_withdrawn(uuid, int), app.path_bid_id(text), app.can_upload_bid_file(text), app.can_read_bid_file(text),
  app.can_delete_bid_file(text), app.bid_draft_file_path_unused(), app.touch_bid_draft()
  from public, anon, authenticated, service_role;
-- latest_version and is_withdrawn are called only from definer functions: no API role executes them.
grant execute on function app.bidding_open(uuid), app.bids_closed(uuid), app.path_bid_id(text),
  app.can_upload_bid_file(text), app.can_read_bid_file(text), app.can_delete_bid_file(text)
  to authenticated;

create trigger bid_draft_files_path_unused
  before insert or update of path on public.bid_draft_files
  for each row execute function app.bid_draft_file_path_unused();
create trigger bid_drafts_touch
  before update on public.bid_drafts
  for each row execute function app.touch_bid_draft();

-- ---------------------------------------------------------------------------
-- Append-only
-- ---------------------------------------------------------------------------
create trigger bid_versions_append_only
  before update or delete on public.bid_versions for each row execute function app.reject_change();
create trigger bid_versions_no_truncate
  before truncate on public.bid_versions for each statement execute function app.reject_change();
create trigger bid_version_files_append_only
  before update or delete on public.bid_version_files for each row execute function app.reject_change();
create trigger bid_version_files_no_truncate
  before truncate on public.bid_version_files for each statement execute function app.reject_change();
create trigger bid_withdrawals_append_only
  before update or delete on public.bid_withdrawals for each row execute function app.reject_change();
create trigger bid_withdrawals_no_truncate
  before truncate on public.bid_withdrawals for each statement execute function app.reject_change();
create trigger bid_audit_log_append_only
  before update or delete on public.bid_audit_log for each row execute function app.reject_change();
create trigger bid_audit_log_no_truncate
  before truncate on public.bid_audit_log for each statement execute function app.reject_change();

-- ---------------------------------------------------------------------------
-- Privileges: nothing for any API role, including service_role, then grant back to authenticated only.
-- ---------------------------------------------------------------------------
revoke all on public.bids, public.bid_drafts, public.bid_draft_files, public.bid_versions,
  public.bid_version_files, public.bid_withdrawals, public.bid_audit_log
  from anon, authenticated, service_role;
revoke all on sequence public.bid_audit_log_id_seq from anon, authenticated, service_role;

grant select on public.bids, public.bid_drafts, public.bid_draft_files, public.bid_audit_log to authenticated;
grant update (item_cents, alternate_cents, bid_bond_choice) on public.bid_drafts to authenticated;
grant insert (bid_id, slot, path, file_name), delete on public.bid_draft_files to authenticated;
-- bid_versions, bid_version_files, bid_withdrawals: no privileges for any API role.

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.bids              enable row level security;
alter table public.bid_drafts        enable row level security;
alter table public.bid_draft_files   enable row level security;
alter table public.bid_versions      enable row level security;
alter table public.bid_version_files enable row level security;
alter table public.bid_withdrawals   enable row level security;
alter table public.bid_audit_log     enable row level security;

create policy bids_read_own on public.bids for select to authenticated
  using (bidder_org_id = (select app.my_org()));

create policy bid_drafts_read_own on public.bid_drafts for select to authenticated
  using (exists (select 1 from public.bids b where b.id = bid_id and b.bidder_org_id = (select app.my_org())));

create policy bid_drafts_update_own on public.bid_drafts for update to authenticated
  using (exists (select 1 from public.bids b
                 where b.id = bid_id and b.bidder_org_id = (select app.my_org())
                   and app.bidding_open(b.solicitation_id)))
  with check (exists (select 1 from public.bids b
                      where b.id = bid_id and b.bidder_org_id = (select app.my_org())
                        and app.bidding_open(b.solicitation_id)));

create policy bid_draft_files_read_own on public.bid_draft_files for select to authenticated
  using (exists (select 1 from public.bids b where b.id = bid_id and b.bidder_org_id = (select app.my_org())));

create policy bid_draft_files_insert_own on public.bid_draft_files for insert to authenticated
  with check (
    path like 'bids/' || bid_id || '/%'
    and app.path_bid_id(path) = bid_id
    and exists (select 1 from public.bids b
                where b.id = bid_id and b.bidder_org_id = (select app.my_org())
                  and app.bidding_open(b.solicitation_id))
  );

create policy bid_draft_files_delete_own on public.bid_draft_files for delete to authenticated
  using (exists (select 1 from public.bids b
                 where b.id = bid_id and b.bidder_org_id = (select app.my_org())
                   and app.bidding_open(b.solicitation_id)));

create policy bid_audit_log_read on public.bid_audit_log for select to authenticated
  using ((select app.is_office()) and app.bids_closed(solicitation_id));

-- ---------------------------------------------------------------------------
-- Storage: private `bid-files` bucket. No update policy: objects are replaced by new uploads, never edited.
-- No anon policy: anon reads nothing.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('bid-files', 'bid-files', false, 104857600)  -- 100 MB
on conflict (id) do nothing;

create policy bid_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'bid-files' and app.can_upload_bid_file(name));

create policy bid_files_read on storage.objects for select to authenticated
  using (bucket_id = 'bid-files' and app.can_read_bid_file(name));

create policy bid_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'bid-files' and app.can_delete_bid_file(name));
