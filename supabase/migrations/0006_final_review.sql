-- 0006_final_review: fixes from the final whole-branch review of the solicitation-setup slice.
--
--   (a) reopen_review: approved -> in_review so a passed release date can be corrected (design 7.1). The reviewer
--       or checker may reopen with a reason; the checker, fallback flag and clause locks are cleared, so the next
--       send_to_check or approve_alone re-locks the clauses and a fresh check is needed.
--   (b) Same-person rule across reassignment: nobody who was a reviewer in the current review round may act as
--       checker (approve_check, disagree). A round starts at the latest submit_solicitation or reopen_review; the
--       round's reviewers are read from the append-only audit log, which no role can alter.
--   (c) submit_solicitation refuses data that is not a JSON object or lacks a top-level key the Zod schema requires
--       (src/domain/solicitation/schema.ts). Full server-side validation stays in the app (logged follow-up).
--   (d) publish_solicitation pins the file paths to solicitations/{id}/v1/{rfb,bid-form}.pdf and recomputes
--       bid_due_at from data (bidDueDate + bidDueTime in the settings time zone); a caller value that differs is
--       rejected (bid_due_mismatch) rather than silently replaced, so an app/database disagreement surfaces.
--   (e) The `published` insert policy only accepts solicitations/{uuid}/v{n}/... names whose solicitation is
--       approved, and only from office staff.
--
-- New error strings (errcode P0001): invalid_paths, bid_due_mismatch. Existing ones are reused elsewhere.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Top-level keys of SolicitationData that the Zod schema requires. Kept in sync with schema.ts by a unit test
-- (src/domain/solicitation/requiredKeys.test.ts), which parses this list out of this file.
create function app.required_data_keys()
returns text[]
language sql immutable
set search_path = ''
as $$
  select array[
    -- required-data-keys:start
    'shortTitle', 'longTitle', 'category', 'summary', 'projectDescription', 'scopeNotes', 'specialProvisions',
    'location', 'requester', 'projectManager', 'estimateCents', 'fundingSource', 'fundingOther', 'federalFunds',
    'releaseDate', 'adStart', 'adEnd', 'newspapers', 'questionsDue', 'answersDue', 'bidDueDate', 'bidDueTime',
    'tentativeAwardDate', 'estimatedStartDate', 'estimatedCompletionDate', 'bidValidityDays', 'preBid',
    'backgroundCheck', 'schedule', 'optionalSections', 'pageLimits', 'attachments'
    -- required-data-keys:end
  ]::text[];
$$;

-- Bid due instant from data: bidDueDate + bidDueTime, read as wall-clock time in the configured zone.
-- Null when either part is missing or unparseable.
create function app.bid_due_at(p_data jsonb)
returns timestamptz
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_tz text := coalesce((select s.timezone from public.settings s where s.id = 1), 'America/Denver');
begin
  if p_data ->> 'bidDueDate' is null or p_data ->> 'bidDueTime' is null
     or p_data ->> 'bidDueTime' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    return null;
  end if;
  return ((p_data ->> 'bidDueDate')::date + (p_data ->> 'bidDueTime')::time) at time zone v_tz;
exception when others then
  return null;
end;
$$;

-- Did p_user act as reviewer on this solicitation in the current review round? The round starts at the latest
-- submission or reopen; reviewers are the current reviewer plus everyone start_review, reassign_review or
-- reopen_review named after that point.
create function app.was_round_reviewer(p_row public.solicitations, p_user uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  with round_start as (
    select coalesce(max(a.id), 0) as id
      from public.audit_log a
     where a.solicitation_id = p_row.id
       and a.action in ('submit_solicitation', 'reopen_review')
  )
  select p_user is not null and (
    p_row.reviewer_id = p_user
    or exists (
      select 1
        from public.audit_log a, round_start r
       where a.solicitation_id = p_row.id
         and a.id >= r.id
         and (
           (a.action = 'start_review'    and a.detail ->> 'reviewer_id'     = p_user::text)
           or (a.action = 'reassign_review' and (a.detail ->> 'old_reviewer_id' = p_user::text
                                             or a.detail ->> 'new_reviewer_id' = p_user::text))
           or (a.action = 'reopen_review'  and a.detail ->> 'reviewer_id'     = p_user::text)
         )
    )
  );
$$;

-- Storage insert check for the `published` bucket: office staff, a solicitations/{uuid}/v{n}/{file} name, and the
-- solicitation is approved (publish uploads while the row is approved, then freezes it).
create function app.can_write_published_file(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select app.is_office()
     and p_name ~ '^solicitations/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/v[1-9][0-9]*/[^/].*$'
     and position('..' in p_name) = 0
     and exists (
       select 1 from public.solicitations s
        where s.id = app.path_solicitation_id(p_name)
          and s.state = 'approved'
     );
$$;

revoke all on function app.required_data_keys(), app.bid_due_at(jsonb),
  app.was_round_reviewer(public.solicitations, uuid)
  from public, anon, authenticated, service_role;
revoke all on function app.can_write_published_file(text) from public;
grant execute on function app.can_write_published_file(text) to anon, authenticated, service_role;

drop policy published_insert on storage.objects;
create policy published_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'published' and app.can_write_published_file(name));

-- ---------------------------------------------------------------------------
-- submit_solicitation: as 0002, plus the required-keys check (invalid_data) after the state check.
-- ---------------------------------------------------------------------------
create or replace function public.submit_solicitation(p_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row         public.solicitations;
  v_today       date := app.today();
  v_start_month int;
  v_fy          int;
  v_seq         int;
  v_number      text;
  v_fy_assigned int;
begin
  if auth.uid() is null or app.is_office() or app.my_org() is null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  v_row := app.lock_solicitation(p_id);
  if v_row.agency_id is distinct from app.my_org() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  perform app.require_state(v_row, 'draft');
  if jsonb_typeof(v_row.data) is distinct from 'object' or not (v_row.data ?& app.required_data_keys()) then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  v_number := v_row.number;
  v_fy_assigned := v_row.fiscal_year;
  if v_number is null then
    select coalesce((select s.fiscal_year_start_month from public.settings s where s.id = 1), 7)
      into v_start_month;
    v_fy := case
      when v_start_month = 1 then extract(year from v_today)::int
      when extract(month from v_today)::int >= v_start_month then extract(year from v_today)::int + 1
      else extract(year from v_today)::int
    end;

    insert into public.number_sequences as ns (fiscal_year, last_seq)
    values (v_fy, 1)
    on conflict (fiscal_year) do update set last_seq = ns.last_seq + 1
    returning ns.last_seq into v_seq;

    if v_seq > 9999 then
      raise exception 'number_sequence_exhausted' using errcode = 'P0001';
    end if;
    v_number := lpad((v_fy % 100)::text, 2, '0') || '-' || lpad(v_seq::text, 4, '0');
    v_fy_assigned := v_fy;
  end if;

  update public.solicitations s
     set state = 'submitted',
         number = v_number,
         fiscal_year = v_fy_assigned,
         latest_submitted_at = now()
   where s.id = p_id and s.state = 'draft';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(p_id, 'submit_solicitation', jsonb_build_object(
    'from', 'draft', 'to', 'submitted', 'number', v_number,
    'first_submission', v_row.number is null));
end;
$$;

-- ---------------------------------------------------------------------------
-- reopen_review: reviewer or checker, approved -> in_review, with a reason.
-- ---------------------------------------------------------------------------
create function public.reopen_review(p_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'approved');
  if auth.uid() is distinct from v_row.reviewer_id and auth.uid() is distinct from v_row.checker_id then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;

  update public.solicitations s
     set state = 'in_review', checker_id = null, fallback_approved = false
   where s.id = p_id and s.state = 'approved';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  delete from public.solicitation_clause_locks l where l.solicitation_id = p_id;

  perform app.audit(p_id, 'reopen_review', jsonb_build_object(
    'from', 'approved', 'to', 'in_review', 'reason', btrim(p_reason),
    'reviewer_id', v_row.reviewer_id, 'previous_checker_id', v_row.checker_id,
    'previous_fallback_approved', v_row.fallback_approved));
end;
$$;

-- ---------------------------------------------------------------------------
-- approve_check / disagree: as 0002, but anyone who reviewed in the current round is refused (same_person).
-- ---------------------------------------------------------------------------
create or replace function public.approve_check(p_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'in_check');
  if app.was_round_reviewer(v_row, auth.uid()) then
    raise exception 'same_person' using errcode = 'P0001';
  end if;

  update public.solicitations s
     set state = 'approved', checker_id = auth.uid()
   where s.id = p_id and s.state = 'in_check';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(p_id, 'approve_check', jsonb_build_object(
    'from', 'in_check', 'to', 'approved', 'checker_id', auth.uid()));
end;
$$;

create or replace function public.disagree(p_id uuid, p_comment text, p_field text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'in_check');
  if app.was_round_reviewer(v_row, auth.uid()) then
    raise exception 'same_person' using errcode = 'P0001';
  end if;
  if coalesce(btrim(p_comment), '') = '' then
    raise exception 'comment_required' using errcode = 'P0001';
  end if;

  update public.solicitations s
     set state = 'in_review'
   where s.id = p_id and s.state = 'in_check';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.comments (solicitation_id, field, body, kind, author_id)
  values (p_id, nullif(btrim(p_field), ''), btrim(p_comment), 'disagree', auth.uid());

  delete from public.solicitation_clause_locks l where l.solicitation_id = p_id;

  perform app.audit(p_id, 'disagree', jsonb_build_object(
    'from', 'in_check', 'to', 'in_review',
    'field', nullif(btrim(p_field), ''), 'comment', btrim(p_comment)));
end;
$$;

-- ---------------------------------------------------------------------------
-- publish_solicitation: as 0004, plus pinned paths and a recomputed bid_due_at.
-- ---------------------------------------------------------------------------
create or replace function public.publish_solicitation(
  p_id uuid,
  p_rfb_path text,
  p_bid_form_path text,
  p_snapshot jsonb,
  p_bid_due_at timestamptz)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row     public.solicitations;
  v_release date;
  v_bid_due timestamptz;
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
         bid_due_at = v_bid_due
   where s.id = p_id and s.state = 'approved';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(p_id, 'publish_solicitation', jsonb_build_object(
    'from', 'approved', 'to', 'published', 'version', 1,
    'release_date', v_release, 'bid_due_at', v_bid_due,
    'rfb_path', p_rfb_path, 'bid_form_path', p_bid_form_path));
end;
$$;

-- ---------------------------------------------------------------------------
-- Privileges for the new public function (create or replace keeps the existing grants on the others).
-- ---------------------------------------------------------------------------
revoke all on function public.reopen_review(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.reopen_review(uuid, text) to authenticated;
