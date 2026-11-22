-- 0029_addendum_publish: publishing an approved addendum as a new solicitation version (slice 2c, Task 4).
--
-- * app.schedule_changed: the SQL twin of scheduleChanged in src/domain/addendum/diff.ts. Positional: items compared
--   as {name, description}, alternates as {kind, description}, element order significant. diff.test.ts and
--   addendum_publish.test.sql pin the same six cases.
-- * app.local_deadline: a {date, time} data value (questionsDue, answersDue) as an instant in settings.timezone.
-- * app.addendum_too_close: the 5-day rule (Drew). A resulting due time of exactly p_now + 5 days is allowed.
-- * public.publish_addendum: the reviewer or checker publishes addendum n - 1 as version n. Lock order is addendum,
--   then solicitation; nothing in 0027/0028 locks the other way (start_addendum locks only the solicitation; the
--   review functions lock only the addendum). The pointer UPDATE uses the app.reject_published_change exception
--   (0026) and resets app.publishing_addendum right after it, so no later statement in the transaction can reuse it
--   (mirrors app.registering in 0008).
-- * app.can_write_published_file (replaces 0006): office uploads to v1 while the solicitation is approved (as
--   before, now v1 only, the only folder publish_solicitation accepts), and to v{n} only for n = version + 1, while
--   the solicitation is published and still open and has an addendum numbered n - 1 whose effective state is
--   approved.
-- * app.can_access_attachment (replaces 0001): the owning agency may also upload and read while an addendum is a
--   draft (revised drawings go in as new attachments; Ruling R12).
-- * app.can_read_published_file (replaces 0001): a v{n} folder (n > 1) is readable by non-office users only once
--   solicitation_versions has (sid, n), so addendum files uploaded before publish_addendum are never public.
-- * app.can_delete_unpublished_file (replaces 0004, Ruling R11): office may also delete a v{n} (n > 1) object that
--   no published version owns, so a failed publish_addendum can clean up and retry.
-- * app.path_version: the v{n} folder number of a published-bucket name.
--
-- Errors (P0001): not_authorized, not_found, invalid_state, invalid_data, bids_closed, invalid_paths,
-- bid_due_mismatch, too_close, snapshot_mismatch, locked_field.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create function app.schedule_changed(p_old jsonb, p_new jsonb)
returns boolean
language sql immutable
set search_path = ''
as $$
  with lists as (
    select
      (select coalesce(jsonb_agg(jsonb_build_object('name', e -> 'name', 'description', e -> 'description')
                                 order by o), '[]'::jsonb)
         from jsonb_array_elements(case when jsonb_typeof(p_old -> 'schedule' -> 'items') = 'array'
                                        then p_old -> 'schedule' -> 'items' else '[]'::jsonb end)
              with ordinality as t(e, o)) as old_items,
      (select coalesce(jsonb_agg(jsonb_build_object('name', e -> 'name', 'description', e -> 'description')
                                 order by o), '[]'::jsonb)
         from jsonb_array_elements(case when jsonb_typeof(p_new -> 'schedule' -> 'items') = 'array'
                                        then p_new -> 'schedule' -> 'items' else '[]'::jsonb end)
              with ordinality as t(e, o)) as new_items,
      (select coalesce(jsonb_agg(jsonb_build_object('kind', e -> 'kind', 'description', e -> 'description')
                                 order by o), '[]'::jsonb)
         from jsonb_array_elements(case when jsonb_typeof(p_old -> 'schedule' -> 'alternates') = 'array'
                                        then p_old -> 'schedule' -> 'alternates' else '[]'::jsonb end)
              with ordinality as t(e, o)) as old_alts,
      (select coalesce(jsonb_agg(jsonb_build_object('kind', e -> 'kind', 'description', e -> 'description')
                                 order by o), '[]'::jsonb)
         from jsonb_array_elements(case when jsonb_typeof(p_new -> 'schedule' -> 'alternates') = 'array'
                                        then p_new -> 'schedule' -> 'alternates' else '[]'::jsonb end)
              with ordinality as t(e, o)) as new_alts
  )
  select old_items is distinct from new_items or old_alts is distinct from new_alts from lists;
$$;

create function app.local_deadline(p_value jsonb)
returns timestamptz
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_tz text := coalesce((select s.timezone from public.settings s where s.id = 1), 'America/Denver');
begin
  if p_value ->> 'date' is null or p_value ->> 'time' is null
     or p_value ->> 'time' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    return null;
  end if;
  return ((p_value ->> 'date')::date + (p_value ->> 'time')::time) at time zone v_tz;
exception when others then
  return null;
end;
$$;

-- Stable, not immutable: timestamptz + interval '5 days' follows the session time zone's calendar.
create function app.addendum_too_close(p_due timestamptz, p_now timestamptz)
returns boolean
language sql stable
set search_path = ''
as $$
  select p_due < p_now + interval '5 days';
$$;

revoke all on function app.schedule_changed(jsonb, jsonb), app.local_deadline(jsonb),
  app.addendum_too_close(timestamptz, timestamptz)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- publish_addendum
-- ---------------------------------------------------------------------------
create function public.publish_addendum(
  p_addendum_id uuid,
  p_rfb_path text,
  p_bid_form_path text,
  p_addendum_path text,
  p_snapshot jsonb,
  p_bid_due_at timestamptz,
  p_funding_cents bigint)
returns int
language plpgsql security definer
set search_path = ''
as $$
declare
  v_add         public.addenda;
  v_sol         public.solicitations;
  v_version     int;
  v_bid_due     timestamptz;
  v_funding_raw jsonb;
  v_funding_num numeric;
  v_funding     bigint;
  v_new_data    jsonb;
  v_changed     boolean;
  v_answers_due timestamptz;
begin
  -- 1. Office, then the addendum lock, then the solicitation lock.
  perform app.require_office();
  v_add := app.lock_addendum(p_addendum_id);
  v_sol := app.lock_solicitation(v_add.solicitation_id);

  -- 2. Approved, and the caller is its reviewer or checker.
  if v_add.state <> 'approved' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if auth.uid() is distinct from v_add.reviewer_id and auth.uid() is distinct from v_add.checker_id then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  perform app.require_state(v_sol, 'published');

  -- 3. Closed on the wall clock, judged after the locks (Ruling 8).
  if clock_timestamp() >= v_sol.bid_due_at then
    raise exception 'bids_closed' using errcode = 'P0001';
  end if;

  if p_rfb_path is null or p_bid_form_path is null or p_addendum_path is null
     or p_snapshot is null or p_snapshot in ('null'::jsonb, '{}'::jsonb)
     or p_bid_due_at is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  -- 4. Version n = current + 1, which is addendum number + 1; the paths are pinned to v{n}.
  v_version := v_sol.version + 1;
  if v_add.number <> v_version - 1 then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if p_rfb_path <> format('solicitations/%s/v%s/rfb.pdf', v_sol.id, v_version)
     or p_bid_form_path <> format('solicitations/%s/v%s/bid-form.pdf', v_sol.id, v_version)
     or p_addendum_path <> format('solicitations/%s/v%s/addendum.pdf', v_sol.id, v_version) then
    raise exception 'invalid_paths' using errcode = 'P0001';
  end if;

  -- 5. The due time is recomputed from the addendum's data.
  v_bid_due := app.bid_due_at(v_add.data);
  if v_bid_due is null then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  if p_bid_due_at <> v_bid_due then
    raise exception 'bid_due_mismatch' using errcode = 'P0001';
  end if;

  -- 6. The 5-day rule applies to every addendum.
  if app.addendum_too_close(v_bid_due, clock_timestamp()) then
    raise exception 'too_close' using errcode = 'P0001';
  end if;

  -- 7. Funding: a non-negative whole number of cents, validated by the caller and kept out of the public snapshot.
  v_funding_raw := v_add.data -> 'fundingAmountCents';
  if jsonb_typeof(v_funding_raw) is distinct from 'number' then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  v_funding_num := v_funding_raw::numeric;
  if v_funding_num < 0 or v_funding_num <> trunc(v_funding_num) or v_funding_num > 9223372036854775807 then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;
  v_funding := v_funding_num::bigint;
  if p_funding_cents is distinct from v_funding
     or jsonb_path_exists(p_snapshot, '$.**.fundingAmountCents') then
    raise exception 'snapshot_mismatch' using errcode = 'P0001';
  end if;

  -- 8. Locked fields, re-checked against the current data.
  if exists (select 1 from unnest(app.locked_fields()) k
              where (v_add.data -> k) is distinct from (v_sol.data -> k)) then
    raise exception 'locked_field' using errcode = 'P0001';
  end if;

  -- 9. Did the bid schedule change?
  v_new_data := v_add.data - 'fundingAmountCents';
  v_changed := app.schedule_changed(v_sol.data, v_new_data);

  -- 10. Version history (the version row first: the funding change references it).
  insert into public.solicitation_versions (solicitation_id, version, snapshot, rfb_path, bid_form_path,
                                            addendum_path, bid_due_at, published_at, published_by, schedule_changed)
  values (v_sol.id, v_version, p_snapshot, p_rfb_path, p_bid_form_path, p_addendum_path, v_bid_due, now(),
          auth.uid(), v_changed);
  insert into public.solicitation_funding_changes (solicitation_id, version, funding_cents)
  values (v_sol.id, v_version, v_funding);

  -- 11. Move the current pointer under the freeze exception, then close the exception at once.
  perform set_config('app.publishing_addendum', v_sol.id::text, true);
  update public.solicitations s
     set version = v_version,
         published_snapshot = p_snapshot,
         data = v_new_data,
         bid_due_at = v_bid_due,
         rfb_path = p_rfb_path,
         bid_form_path = p_bid_form_path
   where s.id = v_sol.id and s.state = 'published';
  perform set_config('app.publishing_addendum', '', true);

  -- 12. -- Task 5: when v_changed, reset every bid_drafts row of this solicitation's bids (item_cents = '{}',
  --     alternate_cents = '{}', solicitation_version = v_version).

  -- 13. The addendum is published.
  update public.addenda a
     set state = 'published', published_version = v_version
   where a.id = v_add.id and a.state = 'approved';

  -- 14. Audit. after_answers_due: published after the answers-due time bidders were working to (the data before
  --     this publish), read in settings.timezone.
  v_answers_due := app.local_deadline(v_sol.data -> 'answersDue');
  perform app.audit(v_sol.id, 'publish_addendum', jsonb_build_object(
    'addendum_id', v_add.id, 'number', v_add.number, 'from', 'approved', 'to', 'published',
    'version', v_version, 'schedule_changed', v_changed, 'bid_due_at', v_bid_due,
    'after_answers_due', coalesce(now() > v_answers_due, false),
    'rfb_path', p_rfb_path, 'bid_form_path', p_bid_form_path, 'addendum_path', p_addendum_path,
    'funding_cents', v_funding));
  return v_version;
end;
$$;

revoke all on function public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Storage checks
-- ---------------------------------------------------------------------------

-- The version folder of a published-bucket name `solicitations/{uuid}/v{n}/...` as n, or null.
create function app.path_version(p_name text)
returns int
language sql immutable
set search_path = ''
as $$
  select case when split_part(p_name, '/', 3) ~ '^v[1-9][0-9]{0,8}$'
              then substring(split_part(p_name, '/', 3) from 2)::int end;
$$;
revoke all on function app.path_version(text) from public, anon, authenticated, service_role;

-- Storage insert check for the `published` bucket: office staff, a solicitations/{uuid}/v{n}/{file} name, and either
-- v1 of an approved solicitation (publish_solicitation), or the NEXT version (n = version + 1) of a published
-- solicitation that is still open and has an approved addendum n - 1 (publish_addendum). Replaces the 0006
-- definition (its only one).
create or replace function app.can_write_published_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select app.is_office()
     and p_name ~ '^solicitations/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/v[1-9][0-9]{0,8}/[^/].*$'
     and position('..' in p_name) = 0
     and exists (
       select 1 from public.solicitations s
        where s.id = app.path_solicitation_id(p_name)
          and (
            (s.state = 'approved' and app.path_version(p_name) = 1)
            or (s.state = 'published'
                and app.path_version(p_name) = s.version + 1
                and not app.bids_closed(s.id)
                and exists (select 1 from public.addenda a
                             where a.solicitation_id = s.id
                               and a.number = s.version
                               and app.addendum_effective_state(a) = 'approved'))
          )
     );
$$;

-- Published-file read: office staff always; everyone else under the row rule (published and released), and for a
-- v{n} folder with n > 1 only once that version is published (a solicitation_versions row exists). Files uploaded
-- for an addendum stay hidden until publish_addendum succeeds, and forever if it never does. v1 and names outside a
-- version folder keep the 0001 rule. Replaces the 0001 definition (its only one).
create or replace function app.can_read_published_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.solicitations s
    where s.id = app.path_solicitation_id(p_name)
      and (
        app.is_office()
        or (s.state = 'published' and s.release_date <= app.today()
            and (coalesce(app.path_version(p_name), 1) = 1
                 or exists (select 1 from public.solicitation_versions v
                             where v.solicitation_id = s.id and v.version = app.path_version(p_name))))
      )
  );
$$;

-- Published-file delete (Ruling R11): office staff, while the solicitation is not published (a failed
-- publish_solicitation, as 0004), or for a v{n} folder with n > 1 that no published version owns (a failed
-- publish_addendum cleans up and retries). A published version's files are never deleted. Replaces the 0004
-- definition (its only one).
create or replace function app.can_delete_unpublished_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select app.is_office() and exists (
    select 1 from public.solicitations s
    where s.id = app.path_solicitation_id(p_name)
      and (
        s.state <> 'published'
        or (app.path_version(p_name) > 1
            and not exists (select 1 from public.solicitation_versions v
                             where v.solicitation_id = s.id and v.version = app.path_version(p_name)))
      )
  );
$$;

-- Attachment access for the caller. p_write: upload (owning agency, not yet published, or while an addendum is a
-- draft); otherwise read (office always; owning agency while not published, or while an addendum is a draft:
-- Ruling R12). Replaces the 0001 definition (its only one).
create or replace function app.can_access_attachment(p_name text, p_write boolean)
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
        or (s.agency_id = app.my_org() and s.state = 'published'
            and exists (select 1 from public.addenda a
                         where a.solicitation_id = s.id
                           and app.addendum_effective_state(a) = 'draft'))
      )
  );
$$;
