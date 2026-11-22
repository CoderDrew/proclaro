-- 0032_questions: the Q&A board, answered through addenda (slice 2c, Task 7).
--
-- Anonymity is the core requirement (spec §6):
-- * public.questions is read through RLS by the asker's organization and by office staff only. The agency matches
--   neither predicate; it reads questions only through public.agency_questions, which returns no identity columns.
-- * The original body is never public. The public reads only addendum_answers.published_question and answer, and
--   only for published addenda of a publicly readable solicitation (public.published_answers).
-- * audit_log is readable by the owning agency (0001 audit_log_read), and app.audit stamps actor_id = auth.uid().
--   So ask_question writes its audit row with actor_id null and only the question id in the detail: the office
--   still knows the asker from questions.asked_by. Staff actions (close, save/remove answer) use app.audit.
--
-- * public.addendum_answers: the agency's published question and answer for each question picked into an addendum.
--   No grants; written only by save_addendum_answer / remove_addendum_answer while the addendum is a draft. A
--   question is answered in at most one published addendum: publish_addendum marks each answered question and
--   refuses (question_not_open) if one is no longer open. A withdrawn addendum's rows are ignored, since its
--   questions were never marked (they stay open and can be picked into the next addendum).
-- * Lock order: addendum, then solicitation (publish_addendum only), then question. close_question locks only the
--   question, then reads the answers, so it serializes with save_addendum_answer (which locks the question too).
-- * ask_question takes FOR SHARE on the solicitation (as start_bid), so publish_addendum (FOR UPDATE) cannot move
--   questionsDue under it, then judges the deadline on clock_timestamp() (Ruling 8).
--
-- New error strings (errcode P0001): questions_closed, question_not_open, question_in_addendum, invalid_question.
-- Reused: not_authorized, not_found, not_open, invalid_state, invalid_data, reason_required.

-- ---------------------------------------------------------------------------
-- Types and tables
-- ---------------------------------------------------------------------------
create type public.question_status as enum ('open', 'answered', 'closed');
create type public.question_close_reason as enum ('duplicate', 'out_of_scope');

create table public.questions (
  id              uuid primary key default gen_random_uuid(),
  solicitation_id uuid not null references public.solicitations (id),
  asked_by        uuid not null references public.profiles (user_id),
  org_id          uuid not null references public.organizations (id),
  body            text not null check (char_length(btrim(body)) between 1 and 4000),
  reference       text not null default '' check (char_length(reference) <= 200),
  asked_at        timestamptz not null default now(),
  status          public.question_status not null default 'open',
  answered_in     uuid references public.addenda (id),
  close_reason    public.question_close_reason,
  closed_by       uuid references public.profiles (user_id),
  closed_at       timestamptz,
  constraint questions_answered_shape check ((status = 'answered') = (answered_in is not null)),
  constraint questions_closed_shape check (
    (status = 'closed') = (close_reason is not null)
    and (status = 'closed') = (closed_by is not null)
    and (status = 'closed') = (closed_at is not null))
);
create index questions_solicitation_id_idx on public.questions (solicitation_id);
create index questions_org_id_idx on public.questions (org_id);

create table public.addendum_answers (
  addendum_id        uuid not null references public.addenda (id),
  question_id        uuid not null references public.questions (id),
  published_question text not null check (char_length(btrim(published_question)) between 1 and 4000),
  answer             text not null check (char_length(btrim(answer)) between 1 and 4000),
  primary key (addendum_id, question_id)
);
create index addendum_answers_question_id_idx on public.addendum_answers (question_id);

revoke all on public.questions, public.addendum_answers from public, anon, authenticated, service_role;
grant select on public.questions to authenticated;

alter table public.questions enable row level security;
alter table public.addendum_answers enable row level security;

-- The asker's organization, or office staff. The agency matches neither (it uses agency_questions).
create policy questions_read on public.questions for select to authenticated
  using (org_id = (select app.my_org()) or (select app.is_office()));

-- ---------------------------------------------------------------------------
-- ask_question: a bidder, on a published, released solicitation, before questionsDue (from the current
-- published_snapshot, in settings.timezone) and before bids close.
-- ---------------------------------------------------------------------------
create function public.ask_question(p_solicitation_id uuid, p_body text, p_reference text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  v_sol       public.solicitations;
  v_body      text := btrim(p_body);
  v_reference text := btrim(coalesce(p_reference, ''));
  v_due       timestamptz;
  v_id        uuid;
begin
  perform app.require_bidder();
  if v_body is null or char_length(v_body) not between 1 and 4000 or char_length(v_reference) > 200 then
    raise exception 'invalid_question' using errcode = 'P0001';
  end if;

  -- Shared lock: publish_addendum cannot move questionsDue or the due time under us. Unknown, unpublished and
  -- unreleased ids all read as not_open, so the error does not reveal which ids exist (as start_bid).
  select * into v_sol from public.solicitations s where s.id = p_solicitation_id for share;
  if not found or v_sol.state <> 'published' or v_sol.release_date > app.today() then
    raise exception 'not_open' using errcode = 'P0001';
  end if;

  -- Judged on the wall clock after the lock (Ruling 8). A missing questionsDue fails closed.
  v_due := app.local_deadline(v_sol.published_snapshot -> 'data' -> 'questionsDue');
  if clock_timestamp() >= v_sol.bid_due_at or v_due is null or clock_timestamp() >= v_due then
    raise exception 'questions_closed' using errcode = 'P0001';
  end if;

  insert into public.questions (solicitation_id, asked_by, org_id, body, reference)
  values (p_solicitation_id, auth.uid(), app.my_org(), v_body, v_reference)
  returning id into v_id;

  -- No actor and no body: the owning agency reads audit_log.
  insert into public.audit_log (solicitation_id, actor_id, action, detail)
  values (p_solicitation_id, null, 'ask_question', jsonb_build_object('question_id', v_id));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

-- The caller's organization's questions.
create function public.my_questions(p_solicitation_id uuid)
returns table (id uuid, body text, reference text, asked_at timestamptz, status public.question_status,
               answered_in_number int, close_reason public.question_close_reason)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform app.require_bidder();
  return query
    select q.id, q.body, q.reference, q.asked_at, q.status, a.number, q.close_reason
      from public.questions q
      left join public.addenda a on a.id = q.answered_in
     where q.solicitation_id = p_solicitation_id and q.org_id = app.my_org()
     order by q.asked_at, q.id;
end;
$$;

-- Office staff: every question, with the asker's organization and name.
create function public.office_questions(p_solicitation_id uuid)
returns table (id uuid, body text, reference text, asked_at timestamptz, status public.question_status,
               answered_in_number int, close_reason public.question_close_reason, org_name text, asker_name text)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform app.require_office();
  return query
    select q.id, q.body, q.reference, q.asked_at, q.status, a.number, q.close_reason, o.name, p.display_name
      from public.questions q
      join public.organizations o on o.id = q.org_id
      join public.profiles p on p.user_id = q.asked_by
      left join public.addenda a on a.id = q.answered_in
     where q.solicitation_id = p_solicitation_id
     order by q.asked_at, q.id;
end;
$$;

-- The owning agency: every question, WITHOUT identity columns (no asked_by, org_id, org name or asker name).
-- in_draft: the question is picked into an addendum that is neither published nor (effectively) withdrawn.
create function public.agency_questions(p_solicitation_id uuid)
returns table (id uuid, body text, reference text, asked_at timestamptz, status public.question_status,
               answered_in_number int, in_draft boolean)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not app.is_agency() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  perform app.require_owning_agency(p_solicitation_id);
  return query
    select q.id, q.body, q.reference, q.asked_at, q.status, a.number,
           exists (select 1 from public.addendum_answers x
                     join public.addenda d on d.id = x.addendum_id
                    where x.question_id = q.id
                      and app.addendum_effective_state(d) not in ('published', 'withdrawn'))
      from public.questions q
      left join public.addenda a on a.id = q.answered_in
     where q.solicitation_id = p_solicitation_id
     order by q.asked_at, q.id;
end;
$$;

-- The draft answers of an addendum: its owning agency, or office staff.
create function public.addendum_answers_draft(p_addendum_id uuid)
returns table (question_id uuid, published_question text, answer text)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_sid uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  select a.solicitation_id into v_sid from public.addenda a where a.id = p_addendum_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if not app.is_office() then
    if not app.is_agency() then
      raise exception 'not_authorized' using errcode = 'P0001';
    end if;
    perform app.require_owning_agency(v_sid);
  end if;
  return query
    select x.question_id, x.published_question, x.answer
      from public.addendum_answers x
      join public.questions q on q.id = x.question_id
     where x.addendum_id = p_addendum_id
     order by q.asked_at, q.id;
end;
$$;

-- Anyone: the published questions and answers of a publicly readable solicitation. Never the original body.
create function public.published_answers(p_solicitation_id uuid)
returns table (addendum_number int, published_question text, answer text)
language sql stable security definer
set search_path = ''
as $$
  select a.number, x.published_question, x.answer
    from public.addendum_answers x
    join public.addenda a on a.id = x.addendum_id
    join public.questions q on q.id = x.question_id
    join public.solicitations s on s.id = a.solicitation_id
   where a.solicitation_id = p_solicitation_id
     and a.state = 'published'
     and s.state = 'published' and s.release_date <= app.today()
   order by a.number, q.asked_at, q.id;
$$;

-- ---------------------------------------------------------------------------
-- close_question: office staff, an open question not picked into a live (unpublished, non-withdrawn) addendum.
-- ---------------------------------------------------------------------------
create function public.close_question(p_question_id uuid, p_reason public.question_close_reason)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_q public.questions;
begin
  perform app.require_office();
  select * into v_q from public.questions q where q.id = p_question_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if v_q.status <> 'open' then
    raise exception 'question_not_open' using errcode = 'P0001';
  end if;
  if p_reason is null then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.addendum_answers x
               join public.addenda d on d.id = x.addendum_id
              where x.question_id = p_question_id
                and app.addendum_effective_state(d) not in ('published', 'withdrawn')) then
    raise exception 'question_in_addendum' using errcode = 'P0001';
  end if;

  update public.questions q
     set status = 'closed', close_reason = p_reason, closed_by = auth.uid(), closed_at = now()
   where q.id = p_question_id;

  perform app.audit(v_q.solicitation_id, 'close_question', jsonb_build_object(
    'question_id', v_q.id, 'reason', p_reason));
end;
$$;

-- ---------------------------------------------------------------------------
-- save_addendum_answer / remove_addendum_answer: the owning agency, addendum in draft, while bidding is open
-- (as save_addendum).
-- ---------------------------------------------------------------------------
create function public.save_addendum_answer(p_addendum_id uuid, p_question_id uuid, p_published_question text,
                                            p_answer text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_add      public.addenda;
  v_q        public.questions;
  v_question text := btrim(p_published_question);
  v_answer   text := btrim(p_answer);
begin
  if auth.uid() is null or not app.is_agency() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  v_add := app.lock_addendum(p_addendum_id);
  perform app.require_owning_agency(v_add.solicitation_id);
  if v_add.state <> 'draft' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_add.solicitation_id);

  -- The question lock serializes with close_question.
  select * into v_q from public.questions q where q.id = p_question_id for update;
  if not found or v_q.solicitation_id <> v_add.solicitation_id then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if v_q.status <> 'open' then
    raise exception 'question_not_open' using errcode = 'P0001';
  end if;
  if v_question is null or char_length(v_question) not between 1 and 4000
     or v_answer is null or char_length(v_answer) not between 1 and 4000 then
    raise exception 'invalid_data' using errcode = 'P0001';
  end if;

  insert into public.addendum_answers (addendum_id, question_id, published_question, answer)
  values (p_addendum_id, p_question_id, v_question, v_answer)
  on conflict (addendum_id, question_id)
  do update set published_question = excluded.published_question, answer = excluded.answer;

  perform app.audit(v_add.solicitation_id, 'save_addendum_answer', jsonb_build_object(
    'addendum_id', v_add.id, 'number', v_add.number, 'question_id', p_question_id));
end;
$$;

create function public.remove_addendum_answer(p_addendum_id uuid, p_question_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_add public.addenda;
begin
  if auth.uid() is null or not app.is_agency() then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  v_add := app.lock_addendum(p_addendum_id);
  perform app.require_owning_agency(v_add.solicitation_id);
  if v_add.state <> 'draft' then
    raise exception 'invalid_state' using errcode = 'P0001';
  end if;
  perform app.require_addendum_window(v_add.solicitation_id);

  delete from public.addendum_answers x where x.addendum_id = p_addendum_id and x.question_id = p_question_id;
  if found then
    perform app.audit(v_add.solicitation_id, 'remove_addendum_answer', jsonb_build_object(
      'addendum_id', v_add.id, 'number', v_add.number, 'question_id', p_question_id));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- publish_addendum: the 0030 body (its latest), plus step 12b: the answered questions are marked.
-- ---------------------------------------------------------------------------
create or replace function public.publish_addendum(
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
  v_answers     int;
  v_marked      int;
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

  -- 12. The schedule changed: every draft of this solicitation's bids loses its prices (items have no ids, so
  --     carrying them across would guess) and is now priced against the new version. Bid writers hold FOR SHARE on
  --     the solicitation before touching a draft (see the 0030 header), so no draft write is in flight here.
  if v_changed then
    update public.bid_drafts d
       set item_cents = '{}', alternate_cents = '{}', solicitation_version = v_version
      from public.bids b
     where b.id = d.bid_id and b.solicitation_id = v_sol.id;
  end if;

  -- 12b. Every question answered in this addendum is marked answered. Each must still be open: a question is
  --      answered in at most one published addendum (close_question and save_addendum_answer keep this true; the
  --      check makes it hold regardless).
  select count(*)::int into v_answers from public.addendum_answers x where x.addendum_id = v_add.id;
  update public.questions q
     set status = 'answered', answered_in = v_add.id
    from public.addendum_answers x
   where x.addendum_id = v_add.id and q.id = x.question_id and q.status = 'open';
  get diagnostics v_marked = row_count;
  if v_marked <> v_answers then
    raise exception 'question_not_open' using errcode = 'P0001';
  end if;

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

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
revoke all on function public.ask_question(uuid, text, text), public.my_questions(uuid),
  public.office_questions(uuid), public.agency_questions(uuid), public.addendum_answers_draft(uuid),
  public.published_answers(uuid), public.close_question(uuid, public.question_close_reason),
  public.save_addendum_answer(uuid, uuid, text, text), public.remove_addendum_answer(uuid, uuid),
  public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.ask_question(uuid, text, text), public.my_questions(uuid),
  public.office_questions(uuid), public.agency_questions(uuid), public.addendum_answers_draft(uuid),
  public.published_answers(uuid), public.close_question(uuid, public.question_close_reason),
  public.save_addendum_answer(uuid, uuid, text, text), public.remove_addendum_answer(uuid, uuid),
  public.publish_addendum(uuid, text, text, text, jsonb, timestamptz, bigint)
  to authenticated;
grant execute on function public.published_answers(uuid) to anon;
