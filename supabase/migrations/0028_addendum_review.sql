-- 0028_addendum_review: office review and the two-person check for addenda (slice 2c, Task 3).
--
-- Each function is the addendum twin of a slice 1 review function (0002, as amended by 0006), with the same check
-- order and errors, applied to public.addenda:
--   start_addendum_review     <- start_review       office, submitted -> in_review, reviewer = caller
--   reassign_addendum_review  <- reassign_review    office, in_review, reviewer = p_user
--   return_addendum           <- return_to_agency   reviewer, in_review -> draft, `return` comments
--   send_addendum_to_check    <- send_to_check      reviewer, in_review -> in_check
--   approve_addendum_check    <- approve_check      office non-round-reviewer, in_check -> approved, checker = caller
--   disagree_addendum         <- disagree           office non-round-reviewer, in_check -> in_review, `disagree` comment
--   approve_addendum_alone    <- approve_alone      reviewer, in_review -> approved, single_reviewer = true (fallback)
--   reopen_addendum_review    <- reopen_review      reviewer or checker, approved -> in_review, with a reason
--
-- Differences from the twins, all deliberate:
--   * Every function also refuses once bidding has closed (bids_closed): app.require_addendum_window (0027) is called
--     after the row lock, so the close is re-judged on clock_timestamp() (Ruling 8).
--   * Check order: office -> row exists (lock) -> state -> per-row role (reviewer / same_person) -> window -> input.
--   * Addenda have no clause locks (clauses are never re-locked) and no warning acks, so nothing is locked or cleared.
--   * disagree_addendum takes no field argument.
--   * Audit rows go to the solicitation's audit_log; every detail carries addendum_id and number.
--
-- app.was_addendum_round_reviewer mirrors app.was_round_reviewer (0006): the round starts at the latest
-- submit_addendum or reopen_addendum_review row for this addendum; the round's reviewers are the current reviewer plus
-- everyone start_addendum_review, reassign_addendum_review (old and new) or reopen_addendum_review named after it.
--
-- Reused error strings (errcode P0001): not_authorized, not_found, invalid_state, invalid_comments, comment_required,
-- reason_required, same_person, bids_closed.

-- ---------------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------------
create function app.was_addendum_round_reviewer(p_row public.addenda, p_user uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  with round_start as (
    select coalesce(max(a.id), 0) as id
      from public.audit_log a
     where a.solicitation_id = p_row.solicitation_id
       and a.action in ('submit_addendum', 'reopen_addendum_review')
       and a.detail ->> 'addendum_id' = p_row.id::text
  )
  select p_user is not null and (
    p_row.reviewer_id = p_user
    or exists (
      select 1
        from public.audit_log a, round_start r
       where a.solicitation_id = p_row.solicitation_id
         and a.detail ->> 'addendum_id' = p_row.id::text
         and a.id >= r.id
         and (
           (a.action = 'start_addendum_review'     and a.detail ->> 'reviewer_id' = p_user::text)
           or (a.action = 'reassign_addendum_review' and (a.detail ->> 'old_reviewer_id' = p_user::text
                                                      or a.detail ->> 'new_reviewer_id' = p_user::text))
           or (a.action = 'reopen_addendum_review'   and a.detail ->> 'reviewer_id' = p_user::text)
         )
    )
  );
$$;

revoke all on function app.was_addendum_round_reviewer(public.addenda, uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- start_addendum_review: office staff, submitted -> in_review, reviewer = caller.
-- ---------------------------------------------------------------------------
create function public.start_addendum_review(p_addendum_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  perform app.require_office();
  v_row := app.lock_addendum(p_addendum_id);
  if v_row.state <> 'submitted' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);

  update public.addenda a
     set state = 'in_review', reviewer_id = auth.uid(), checker_id = null
   where a.id = p_addendum_id and a.state = 'submitted';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(v_row.solicitation_id, 'start_addendum_review', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number, 'from', 'submitted', 'to', 'in_review',
    'reviewer_id', auth.uid()));
end;
$$;

-- ---------------------------------------------------------------------------
-- reassign_addendum_review: office staff, in_review -> in_review, reviewer = p_user (an office user, not the checker).
-- ---------------------------------------------------------------------------
create function public.reassign_addendum_review(p_addendum_id uuid, p_user uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  perform app.require_office();
  v_row := app.lock_addendum(p_addendum_id);
  if v_row.state <> 'in_review' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);
  if p_user is null or not app.is_office_user(p_user) then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if p_user = v_row.checker_id then
    raise exception 'same_person' using errcode = 'P0001';
  end if;

  update public.addenda a
     set reviewer_id = p_user
   where a.id = p_addendum_id and a.state = 'in_review';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(v_row.solicitation_id, 'reassign_addendum_review', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number,
    'old_reviewer_id', v_row.reviewer_id, 'new_reviewer_id', p_user));
end;
$$;

-- ---------------------------------------------------------------------------
-- return_addendum: reviewer, in_review -> draft.
-- p_comments: [{field: text|null, body: text}, ...], at least one, bodies non-blank.
-- ---------------------------------------------------------------------------
create function public.return_addendum(p_addendum_id uuid, p_comments jsonb)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  perform app.require_office();
  v_row := app.lock_addendum(p_addendum_id);
  if v_row.state <> 'in_review' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if v_row.reviewer_id is distinct from auth.uid() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);
  if p_comments is null or jsonb_typeof(p_comments) <> 'array'
     or jsonb_array_length(p_comments) = 0
     or exists (select 1 from jsonb_array_elements(p_comments) e
                where jsonb_typeof(e) <> 'object'
                   or coalesce(btrim(e ->> 'body'), '') = '') then
    raise exception 'invalid_comments' using errcode = 'P0001';
  end if;

  update public.addenda a
     set state = 'draft'
   where a.id = p_addendum_id and a.state = 'in_review';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.addendum_comments (addendum_id, field, body, kind, author_id)
  select p_addendum_id, nullif(btrim(e ->> 'field'), ''), btrim(e ->> 'body'), 'return', auth.uid()
    from jsonb_array_elements(p_comments) e;

  perform app.audit(v_row.solicitation_id, 'return_addendum', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number, 'from', 'in_review', 'to', 'draft',
    'comments', p_comments));
end;
$$;

-- ---------------------------------------------------------------------------
-- send_addendum_to_check: reviewer, in_review -> in_check.
-- ---------------------------------------------------------------------------
create function public.send_addendum_to_check(p_addendum_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  perform app.require_office();
  v_row := app.lock_addendum(p_addendum_id);
  if v_row.state <> 'in_review' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if v_row.reviewer_id is distinct from auth.uid() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);

  update public.addenda a
     set state = 'in_check'
   where a.id = p_addendum_id and a.state = 'in_review';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(v_row.solicitation_id, 'send_addendum_to_check', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number, 'from', 'in_review', 'to', 'in_check'));
end;
$$;

-- ---------------------------------------------------------------------------
-- approve_addendum_check: office staff who did not review in this round, in_check -> approved, checker = caller.
-- ---------------------------------------------------------------------------
create function public.approve_addendum_check(p_addendum_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  perform app.require_office();
  v_row := app.lock_addendum(p_addendum_id);
  if v_row.state <> 'in_check' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if app.was_addendum_round_reviewer(v_row, auth.uid()) then
    raise exception 'same_person' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);

  update public.addenda a
     set state = 'approved', checker_id = auth.uid()
   where a.id = p_addendum_id and a.state = 'in_check';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(v_row.solicitation_id, 'approve_addendum_check', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number, 'from', 'in_check', 'to', 'approved',
    'checker_id', auth.uid()));
end;
$$;

-- ---------------------------------------------------------------------------
-- disagree_addendum: office staff who did not review in this round, in_check -> in_review, with a disagree comment.
-- ---------------------------------------------------------------------------
create function public.disagree_addendum(p_addendum_id uuid, p_comment text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  perform app.require_office();
  v_row := app.lock_addendum(p_addendum_id);
  if v_row.state <> 'in_check' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if app.was_addendum_round_reviewer(v_row, auth.uid()) then
    raise exception 'same_person' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);
  if coalesce(btrim(p_comment), '') = '' then
    raise exception 'comment_required' using errcode = 'P0001';
  end if;

  update public.addenda a
     set state = 'in_review'
   where a.id = p_addendum_id and a.state = 'in_check';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  insert into public.addendum_comments (addendum_id, field, body, kind, author_id)
  values (p_addendum_id, null, btrim(p_comment), 'disagree', auth.uid());

  perform app.audit(v_row.solicitation_id, 'disagree_addendum', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number, 'from', 'in_check', 'to', 'in_review',
    'comment', btrim(p_comment)));
end;
$$;

-- ---------------------------------------------------------------------------
-- approve_addendum_alone: reviewer, in_review -> approved with single_reviewer = true (recorded fallback).
-- ---------------------------------------------------------------------------
create function public.approve_addendum_alone(p_addendum_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  perform app.require_office();
  v_row := app.lock_addendum(p_addendum_id);
  if v_row.state <> 'in_review' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if v_row.reviewer_id is distinct from auth.uid() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);

  update public.addenda a
     set state = 'approved', single_reviewer = true, checker_id = null
   where a.id = p_addendum_id and a.state = 'in_review';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(v_row.solicitation_id, 'approve_addendum_alone', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number, 'from', 'in_review', 'to', 'approved',
    'fallback', 'no second reviewer available'));
end;
$$;

-- ---------------------------------------------------------------------------
-- reopen_addendum_review: reviewer or checker, approved -> in_review, with a reason. Starts a new review round; the
-- checker and the single-reviewer flag are cleared, so a fresh check (or a fresh fallback) is needed.
-- ---------------------------------------------------------------------------
create function public.reopen_addendum_review(p_addendum_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.addenda;
begin
  perform app.require_office();
  v_row := app.lock_addendum(p_addendum_id);
  if v_row.state <> 'approved' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  if auth.uid() is distinct from v_row.reviewer_id and auth.uid() is distinct from v_row.checker_id then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_row.solicitation_id);
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;

  update public.addenda a
     set state = 'in_review', checker_id = null, single_reviewer = false
   where a.id = p_addendum_id and a.state = 'approved';
  if not found then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;

  perform app.audit(v_row.solicitation_id, 'reopen_addendum_review', jsonb_build_object(
    'addendum_id', v_row.id, 'number', v_row.number, 'from', 'approved', 'to', 'in_review',
    'reason', btrim(p_reason), 'reviewer_id', v_row.reviewer_id, 'previous_checker_id', v_row.checker_id,
    'previous_single_reviewer', v_row.single_reviewer));
end;
$$;

revoke all on function public.start_addendum_review(uuid), public.reassign_addendum_review(uuid, uuid),
  public.return_addendum(uuid, jsonb), public.send_addendum_to_check(uuid), public.approve_addendum_check(uuid),
  public.disagree_addendum(uuid, text), public.approve_addendum_alone(uuid), public.reopen_addendum_review(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.start_addendum_review(uuid), public.reassign_addendum_review(uuid, uuid),
  public.return_addendum(uuid, jsonb), public.send_addendum_to_check(uuid), public.approve_addendum_check(uuid),
  public.disagree_addendum(uuid, text), public.approve_addendum_alone(uuid), public.reopen_addendum_review(uuid, text)
  to authenticated;
