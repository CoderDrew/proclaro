-- 0001_core: core schema, row-level security, append-only tables and storage.
--
-- Security model (enforced here, not in the UI):
--   * Agency members see only their own agency's solicitations; office staff see all.
--   * anon sees only published solicitations whose release_date <= app.today().
--   * comments / warning_acks / audit_log / clause locks follow staff visibility of
--     their solicitation; anon sees none of them.
--   * authenticated may INSERT a draft for their own agency and UPDATE only `data`
--     on their own agency's drafts. Every other write goes through security-definer
--     workflow functions (Task 6).
--   * audit_log and clauses are append-only for every role; a published
--     solicitation can never be updated or deleted.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.solicitation_state as enum
  ('draft', 'submitted', 'in_review', 'in_check', 'approved', 'published');
create type public.org_kind as enum ('agency', 'office');
create type public.comment_kind as enum ('return', 'disagree', 'note');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.settings (
  id                      int primary key default 1 check (id = 1),
  state_name              text not null,
  office_name             text not null,
  timezone                text not null default 'America/Denver',
  fiscal_year_start_month int  not null default 7 check (fiscal_year_start_month between 1 and 12)
);

create table public.holidays (
  day  date primary key,
  name text not null
);

create table public.organizations (
  id   uuid primary key default gen_random_uuid(),
  name text not null unique,
  kind public.org_kind not null
);

create table public.profiles (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  org_id       uuid not null references public.organizations (id),
  display_name text not null,
  is_admin     boolean not null default false
);
create index profiles_org_id_idx on public.profiles (org_id);

create table public.solicitations (
  id                  uuid primary key default gen_random_uuid(),
  agency_id           uuid not null references public.organizations (id),
  created_by          uuid not null references public.profiles (user_id),
  state               public.solicitation_state not null default 'draft',
  number              text unique,
  fiscal_year         int,
  data                jsonb not null default '{}'::jsonb,
  latest_submitted_at timestamptz,
  reviewer_id         uuid references public.profiles (user_id),
  checker_id          uuid references public.profiles (user_id),
  fallback_approved   boolean not null default false,
  version             int,
  published_at        timestamptz,
  release_date        date,
  bid_due_at          timestamptz,
  rfb_path            text,
  bid_form_path       text,
  published_snapshot  jsonb,
  created_at          timestamptz not null default now(),
  -- Same-person rule: the reviewer can never be the checker on the same solicitation.
  constraint solicitations_reviewer_not_checker
    check (reviewer_id is null or checker_id is null or reviewer_id <> checker_id)
);
create index solicitations_agency_id_idx on public.solicitations (agency_id);
create index solicitations_public_idx on public.solicitations (release_date) where state = 'published';

create table public.number_sequences (
  fiscal_year int primary key,
  last_seq    int not null default 0
);

create table public.clauses (
  key        text not null,
  version    int  not null check (version > 0),
  body       text not null,
  created_by uuid references public.profiles (user_id),
  created_at timestamptz not null default now(),
  primary key (key, version)
);

create table public.solicitation_clause_locks (
  solicitation_id uuid not null references public.solicitations (id),
  clause_key      text not null,
  clause_version  int  not null,
  primary key (solicitation_id, clause_key),
  foreign key (clause_key, clause_version) references public.clauses (key, version)
);

create table public.comments (
  id              uuid primary key default gen_random_uuid(),
  solicitation_id uuid not null references public.solicitations (id),
  field           text,
  body            text not null,
  kind            public.comment_kind not null,
  author_id       uuid not null references public.profiles (user_id),
  created_at      timestamptz not null default now()
);
create index comments_solicitation_id_idx on public.comments (solicitation_id);

create table public.warning_acks (
  solicitation_id uuid not null references public.solicitations (id),
  code            text not null,
  field           text,
  acked_by        uuid not null references public.profiles (user_id),
  acked_at        timestamptz not null default now(),
  constraint warning_acks_unique unique nulls not distinct (solicitation_id, code, field)
);

create table public.audit_log (
  id              bigserial primary key,
  solicitation_id uuid references public.solicitations (id),
  actor_id        uuid references public.profiles (user_id),
  action          text not null,
  detail          jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
create index audit_log_solicitation_id_idx on public.audit_log (solicitation_id);

-- ---------------------------------------------------------------------------
-- Helper functions (schema `app`)
-- ---------------------------------------------------------------------------
create schema app;
grant usage on schema app to anon, authenticated, service_role;

create function app.my_org()
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select p.org_id from public.profiles p where p.user_id = auth.uid();
$$;

create function app.is_office()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.organizations o on o.id = p.org_id
    where p.user_id = auth.uid() and o.kind = 'office'
  );
$$;

create function app.is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce((select p.is_admin from public.profiles p where p.user_id = auth.uid()), false);
$$;

-- Calendar "today" in the configured time zone, never the server's.
create function app.today()
returns date
language sql stable security definer
set search_path = ''
as $$
  select (now() at time zone coalesce(
            (select s.timezone from public.settings s where s.id = 1),
            'America/Denver'))::date;
$$;

-- Staff visibility of one solicitation: office sees all, agency sees its own.
create function app.can_see_solicitation(p_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.solicitations s
    where s.id = p_id
      and (app.is_office() or s.agency_id = app.my_org())
  );
$$;

-- Solicitation id from an object path `solicitations/{uuid}/...`, or null.
-- Path conventions (both buckets key on the solicitation uuid, never the number):
--   attachments: solicitations/{solicitation_id}/{file}
--   published:   solicitations/{solicitation_id}/v{version}/{file}
create function app.path_solicitation_id(p_name text)
returns uuid
language sql immutable
set search_path = ''
as $$
  select case
    when p_name ~ '^solicitations/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+$'
    then split_part(p_name, '/', 2)::uuid
  end;
$$;

-- Attachment access for the caller. p_write: upload (agency, not yet published);
-- otherwise read (office always; agency while not published).
create function app.can_access_attachment(p_name text, p_write boolean)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.solicitations s
    where s.id = app.path_solicitation_id(p_name)
      and (
        (not p_write and app.is_office())
        or (s.agency_id = app.my_org() and s.state <> 'published')
      )
  );
$$;

-- Published-file read: same rule as the row (published and released), or office staff.
create function app.can_read_published_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.solicitations s
    where s.id = app.path_solicitation_id(p_name)
      and (
        (s.state = 'published' and s.release_date <= app.today())
        or app.is_office()
      )
  );
$$;

create function app.can_delete_attachment(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.solicitations s
    where s.id = app.path_solicitation_id(p_name)
      and s.agency_id = app.my_org()
      and s.state = 'draft'
  );
$$;

-- Trigger: reject every update/delete (append-only tables).
create function app.reject_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only: % is not allowed', tg_table_name, tg_op
    using errcode = 'P0001';
end;
$$;

-- Trigger: a published solicitation is frozen forever.
create function app.reject_published_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.state = 'published' then
    raise exception 'solicitation % is published and read-only', old.id
      using errcode = 'P0001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on all functions in schema app from public;
grant execute on function app.my_org(), app.is_office(), app.is_admin(), app.today(),
  app.can_see_solicitation(uuid), app.path_solicitation_id(text),
  app.can_access_attachment(text, boolean), app.can_delete_attachment(text),
  app.can_read_published_file(text)
  to anon, authenticated, service_role;

create trigger audit_log_append_only
  before update or delete on public.audit_log
  for each row execute function app.reject_change();
create trigger audit_log_no_truncate
  before truncate on public.audit_log
  for each statement execute function app.reject_change();
create trigger clauses_append_only
  before update or delete on public.clauses
  for each row execute function app.reject_change();
create trigger solicitations_published_frozen
  before update or delete on public.solicitations
  for each row execute function app.reject_published_change();

-- ---------------------------------------------------------------------------
-- Privileges. Supabase grants ALL on new public tables to anon/authenticated by
-- default; start from nothing and grant back exactly what is needed.
-- ---------------------------------------------------------------------------
revoke all on public.settings, public.holidays, public.organizations, public.profiles,
  public.solicitations, public.number_sequences, public.clauses,
  public.solicitation_clause_locks, public.comments, public.warning_acks, public.audit_log
  from anon, authenticated;
revoke all on sequence public.audit_log_id_seq from anon, authenticated;

grant select on public.settings, public.holidays, public.organizations, public.clauses
  to anon, authenticated;
grant select on public.profiles, public.solicitation_clause_locks, public.comments,
  public.warning_acks, public.audit_log
  to authenticated;
grant select on public.solicitations to anon, authenticated;
grant insert (agency_id, created_by, data) on public.solicitations to authenticated;
grant update (data) on public.solicitations to authenticated;

-- Append-only for every role, including service_role.
revoke update, delete, truncate on public.audit_log, public.clauses
  from anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.settings                  enable row level security;
alter table public.holidays                  enable row level security;
alter table public.organizations             enable row level security;
alter table public.profiles                  enable row level security;
alter table public.solicitations             enable row level security;
alter table public.number_sequences          enable row level security;
alter table public.clauses                   enable row level security;
alter table public.solicitation_clause_locks enable row level security;
alter table public.comments                  enable row level security;
alter table public.warning_acks              enable row level security;
alter table public.audit_log                 enable row level security;

create policy settings_read      on public.settings      for select to anon, authenticated using (true);
create policy holidays_read      on public.holidays      for select to anon, authenticated using (true);
create policy organizations_read on public.organizations for select to anon, authenticated using (true);
create policy clauses_read       on public.clauses       for select to anon, authenticated using (true);

-- Profiles: yourself, your own org, office staff (names on comments), or anyone if you are office.
create policy profiles_read on public.profiles for select to authenticated
  using (
    user_id = (select auth.uid())
    or org_id = (select app.my_org())
    or (select app.is_office())
    or exists (select 1 from public.organizations o where o.id = org_id and o.kind = 'office')
  );

create policy solicitations_read_staff on public.solicitations for select to authenticated
  using ((select app.is_office()) or agency_id = (select app.my_org()));

create policy solicitations_read_public on public.solicitations for select to anon, authenticated
  using (state = 'published' and release_date <= (select app.today()));

create policy solicitations_insert_draft on public.solicitations for insert to authenticated
  with check (
    state = 'draft'
    and agency_id = (select app.my_org())
    and created_by = (select auth.uid())
    and not (select app.is_office())
  );

create policy solicitations_update_draft on public.solicitations for update to authenticated
  using (
    state = 'draft'
    and agency_id = (select app.my_org())
    and not (select app.is_office())
  )
  with check (state = 'draft' and agency_id = (select app.my_org()));

create policy clause_locks_read on public.solicitation_clause_locks for select to authenticated
  using (app.can_see_solicitation(solicitation_id));
create policy comments_read on public.comments for select to authenticated
  using (app.can_see_solicitation(solicitation_id));
create policy warning_acks_read on public.warning_acks for select to authenticated
  using (app.can_see_solicitation(solicitation_id));
create policy audit_log_read on public.audit_log for select to authenticated
  using (app.can_see_solicitation(solicitation_id));

-- number_sequences: RLS on, no policies, no grants. Workflow functions only.

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values
  ('attachments', 'attachments', false, 104857600),  -- 100 MB
  -- Private: a published row is hidden until its release_date, so its files must be too.
  ('published',   'published',   false, null)
on conflict (id) do nothing;

create policy attachments_read on storage.objects for select to authenticated
  using (bucket_id = 'attachments' and app.can_access_attachment(name, false));

create policy attachments_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'attachments' and app.can_access_attachment(name, true));

create policy attachments_delete on storage.objects for delete to authenticated
  using (bucket_id = 'attachments' and app.can_delete_attachment(name));

create policy published_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'published' and app.can_read_published_file(name));

create policy published_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'published' and (select app.is_office()));

-- No update/delete policies on `published`: published files are frozen like their rows.
