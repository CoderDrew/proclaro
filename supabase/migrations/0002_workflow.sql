-- 0002_workflow: the only way a solicitation changes state.
--
-- Every function here:
--   * is SECURITY DEFINER with an empty search_path and fully qualified names;
--   * checks the caller's org kind and role (raises 'not_authorized');
--   * locks the row, checks the expected state (raises 'invalid_state'), then
--     updates with `where id = p_id and state = <expected>` and raises
--     'invalid_state' again if no row changed;
--   * inserts exactly one audit_log row whose action is the function name.
--
-- Check order: org kind -> row exists -> owning agency -> state -> per-row role
-- (reviewer / same person). A published row therefore always yields
-- 'invalid_state' for a caller of the right org kind, and the published-freeze
-- trigger from 0001 is never reached except by publish_solicitation itself,
-- which sets state = 'published' and every published column in one update.
--
-- Error strings (all errcode P0001): not_authorized, not_found, invalid_state,
-- same_person, reason_required, comment_required, invalid_comments,
-- invalid_release_date, number_sequence_exhausted.

-- ---------------------------------------------------------------------------
-- Internal helpers (schema `app`, not exposed to API roles)
-- ---------------------------------------------------------------------------

-- Is the given user a member of the office org?
create function app.is_office_user(p_user uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.organizations o on o.id = p.org_id
    where p.user_id = p_user and o.kind = 'office'
  );
$$;

create function app.require_office()
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not app.is_office() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
end;
$$;

-- Lock and return the solicitation row, or raise not_found.
create function app.lock_solicitation(p_id uuid)
returns public.solicitations
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  select * into v_row from public.solicitations s where s.id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  return v_row;
end;
$$;

create function app.require_state(p_row public.solicitations, p_state public.solicitation_state)
returns void
language plpgsql immutable
set search_path = ''
as $$
begin
  if p_row.state is distinct from p_state then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
end;
$$;

create function app.require_reviewer(p_row public.solicitations)
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if p_row.reviewer_id is distinct from auth.uid() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
end;
$$;

create function app.audit(p_id uuid, p_action text, p_detail jsonb default '{}'::jsonb)
returns void
language sql security definer
set search_path = ''
as $$
  insert into public.audit_log (solicitation_id, actor_id, action, detail)
  values (p_id, auth.uid(), p_action, coalesce(p_detail, '{}'::jsonb));
$$;

-- Replace the solicitation's clause locks with the latest version of every key.
create function app.lock_clauses(p_id uuid)
returns void
language sql security definer
set search_path = ''
as $$
  delete from public.solicitation_clause_locks l where l.solicitation_id = p_id;
  insert into public.solicitation_clause_locks (solicitation_id, clause_key, clause_version)
  select p_id, c.key, max(c.version) from public.clauses c group by c.key;
$$;

-- ---------------------------------------------------------------------------
-- submit_solicitation: agency member, draft -> submitted.
-- First submission assigns number/fiscal_year from app.today() and
-- settings.fiscal_year_start_month (fiscal year = calendar year it ends in).
-- ---------------------------------------------------------------------------
create function public.submit_solicitation(p_id uuid)
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

    -- Atomic: the upsert takes a row lock on the fiscal year's sequence row.
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
-- start_review: office staff, submitted -> in_review, reviewer = caller.
-- ---------------------------------------------------------------------------
create function public.start_review(p_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'submitted');

  update public.solicitations s
     set state = 'in_review', reviewer_id = auth.uid(), checker_id = null
   where s.id = p_id and s.state = 'submitted';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(p_id, 'start_review', jsonb_build_object(
    'from', 'submitted', 'to', 'in_review', 'reviewer_id', auth.uid()));
end;
$$;

-- ---------------------------------------------------------------------------
-- reassign_review: office staff, in_review -> in_review, reviewer = p_user.
-- ---------------------------------------------------------------------------
create function public.reassign_review(p_id uuid, p_user uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'in_review');
  if p_user is null or not app.is_office_user(p_user) then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if p_user = v_row.checker_id then
    raise exception 'same_person' using errcode = 'P0001';
  end if;

  update public.solicitations s
     set reviewer_id = p_user
   where s.id = p_id and s.state = 'in_review';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(p_id, 'reassign_review', jsonb_build_object(
    'old_reviewer_id', v_row.reviewer_id, 'new_reviewer_id', p_user));
end;
$$;

-- ---------------------------------------------------------------------------
-- office_update_data: reviewer, in_review. p_data is the full new `data`
-- (replace, like the agency's own column update). Audit detail:
-- {reason, changes: [{key, old, new}]} for every changed top-level key.
-- ---------------------------------------------------------------------------
create function public.office_update_data(p_id uuid, p_data jsonb, p_reason text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row     public.solicitations;
  v_changes jsonb;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'in_review');
  perform app.require_reviewer(v_row);
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'key', k.key,
           'old', v_row.data -> k.key,
           'new', p_data -> k.key) order by k.key), '[]'::jsonb)
    into v_changes
    from (select jsonb_object_keys(v_row.data) as key
          union
          select jsonb_object_keys(p_data)) k
   where (v_row.data -> k.key) is distinct from (p_data -> k.key);

  update public.solicitations s
     set data = p_data
   where s.id = p_id and s.state = 'in_review';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(p_id, 'office_update_data', jsonb_build_object(
    'reason', btrim(p_reason), 'changes', v_changes));
end;
$$;

-- ---------------------------------------------------------------------------
-- return_to_agency: reviewer, in_review -> draft.
-- p_comments: [{field: text|null, body: text}, ...], at least one, bodies non-blank.
-- ---------------------------------------------------------------------------
create function public.return_to_agency(p_id uuid, p_comments jsonb)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'in_review');
  perform app.require_reviewer(v_row);
  if p_comments is null or jsonb_typeof(p_comments) <> 'array'
     or jsonb_array_length(p_comments) = 0
     or exists (select 1 from jsonb_array_elements(p_comments) e
                where jsonb_typeof(e) <> 'object'
                   or coalesce(btrim(e ->> 'body'), '') = '') then
    raise exception 'invalid_comments' using errcode = 'P0001';
  end if;

  update public.solicitations s
     set state = 'draft'
   where s.id = p_id and s.state = 'in_review';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.comments (solicitation_id, field, body, kind, author_id)
  select p_id, nullif(btrim(e ->> 'field'), ''), btrim(e ->> 'body'), 'return', auth.uid()
    from jsonb_array_elements(p_comments) e;

  delete from public.warning_acks w where w.solicitation_id = p_id;

  perform app.audit(p_id, 'return_to_agency', jsonb_build_object(
    'from', 'in_review', 'to', 'draft', 'comments', p_comments));
end;
$$;

-- ---------------------------------------------------------------------------
-- send_to_check: reviewer, in_review -> in_check. Locks every clause key.
-- ---------------------------------------------------------------------------
create function public.send_to_check(p_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'in_review');
  perform app.require_reviewer(v_row);

  update public.solicitations s
     set state = 'in_check'
   where s.id = p_id and s.state = 'in_review';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.lock_clauses(p_id);

  perform app.audit(p_id, 'send_to_check', jsonb_build_object(
    'from', 'in_review', 'to', 'in_check',
    'clause_locks', (select coalesce(jsonb_object_agg(l.clause_key, l.clause_version), '{}'::jsonb)
                     from public.solicitation_clause_locks l where l.solicitation_id = p_id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- approve_check: office staff other than the reviewer, in_check -> approved.
-- ---------------------------------------------------------------------------
create function public.approve_check(p_id uuid)
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
  if v_row.reviewer_id = auth.uid() then
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

-- ---------------------------------------------------------------------------
-- disagree: office staff other than the reviewer, in_check -> in_review.
-- Inserts a disagree comment; deletes the clause locks.
-- ---------------------------------------------------------------------------
create function public.disagree(p_id uuid, p_comment text, p_field text)
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
  if v_row.reviewer_id = auth.uid() then
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
-- approve_alone: reviewer, in_review -> approved with fallback_approved.
-- ---------------------------------------------------------------------------
create function public.approve_alone(p_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'in_review');
  perform app.require_reviewer(v_row);

  update public.solicitations s
     set state = 'approved', fallback_approved = true, checker_id = null
   where s.id = p_id and s.state = 'in_review';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.lock_clauses(p_id);

  perform app.audit(p_id, 'approve_alone',
    jsonb_build_object('fallback', 'no second reviewer available'));
end;
$$;

-- ---------------------------------------------------------------------------
-- publish_solicitation: reviewer or checker, approved -> published.
-- One update sets state and every published column: after it the row is frozen
-- by the 0001 trigger. The release date must be present and not in the past
-- (design 7.1: a passed release date blocks publishing until corrected).
-- ---------------------------------------------------------------------------
create function public.publish_solicitation(
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
begin
  perform app.require_office();
  v_row := app.lock_solicitation(p_id);
  perform app.require_state(v_row, 'approved');
  if auth.uid() is distinct from v_row.reviewer_id and auth.uid() is distinct from v_row.checker_id then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  begin
    v_release := (v_row.data ->> 'releaseDate')::date;
  exception when others then
    v_release := null;
  end;
  if v_release is null or v_release < app.today() then
    raise exception 'invalid_release_date' using errcode = 'P0001';
  end if;

  update public.solicitations s
     set state = 'published',
         version = 1,
         published_at = now(),
         release_date = v_release,
         rfb_path = p_rfb_path,
         bid_form_path = p_bid_form_path,
         published_snapshot = p_snapshot,
         bid_due_at = p_bid_due_at
   where s.id = p_id and s.state = 'approved';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(p_id, 'publish_solicitation', jsonb_build_object(
    'from', 'approved', 'to', 'published', 'version', 1,
    'release_date', v_release, 'bid_due_at', p_bid_due_at,
    'rfb_path', p_rfb_path, 'bid_form_path', p_bid_form_path));
end;
$$;

-- ---------------------------------------------------------------------------
-- acknowledge_warning: author (owning agency) while draft; reviewer while
-- in_review. Upserts warning_acks. Any other state raises invalid_state.
-- ---------------------------------------------------------------------------
create function public.acknowledge_warning(p_id uuid, p_code text, p_field text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.solicitations;
begin
  if auth.uid() is null or app.my_org() is null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  v_row := app.lock_solicitation(p_id);
  if not app.is_office() and v_row.agency_id is distinct from app.my_org() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if v_row.state not in ('draft', 'in_review') then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if v_row.state = 'draft' and app.is_office() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if v_row.state = 'in_review' and v_row.reviewer_id is distinct from auth.uid() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if coalesce(btrim(p_code), '') = '' then
    raise exception 'invalid_code' using errcode = 'P0001';
  end if;

  insert into public.warning_acks (solicitation_id, code, field, acked_by, acked_at)
  values (p_id, btrim(p_code), p_field, auth.uid(), now())
  on conflict on constraint warning_acks_unique
  do update set acked_by = excluded.acked_by, acked_at = excluded.acked_at;

  perform app.audit(p_id, 'acknowledge_warning', jsonb_build_object(
    'code', btrim(p_code), 'field', p_field, 'state', v_row.state));
end;
$$;

-- ---------------------------------------------------------------------------
-- Privileges: callable by signed-in users only. Supabase's default privileges
-- grant EXECUTE on new public functions to anon/authenticated/service_role;
-- revoke everything, then grant to authenticated.
-- ---------------------------------------------------------------------------
revoke all on function
  app.is_office_user(uuid), app.require_office(), app.lock_solicitation(uuid),
  app.require_state(public.solicitations, public.solicitation_state),
  app.require_reviewer(public.solicitations), app.audit(uuid, text, jsonb),
  app.lock_clauses(uuid)
  from public, anon, authenticated, service_role;

revoke all on function
  public.submit_solicitation(uuid),
  public.start_review(uuid),
  public.reassign_review(uuid, uuid),
  public.office_update_data(uuid, jsonb, text),
  public.return_to_agency(uuid, jsonb),
  public.send_to_check(uuid),
  public.approve_check(uuid),
  public.disagree(uuid, text, text),
  public.approve_alone(uuid),
  public.publish_solicitation(uuid, text, text, jsonb, timestamptz),
  public.acknowledge_warning(uuid, text, text)
  from public, anon, authenticated, service_role;

grant execute on function
  public.submit_solicitation(uuid),
  public.start_review(uuid),
  public.reassign_review(uuid, uuid),
  public.office_update_data(uuid, jsonb, text),
  public.return_to_agency(uuid, jsonb),
  public.send_to_check(uuid),
  public.approve_check(uuid),
  public.disagree(uuid, text, text),
  public.approve_alone(uuid),
  public.publish_solicitation(uuid, text, text, jsonb, timestamptz),
  public.acknowledge_warning(uuid, text, text)
  to authenticated;
