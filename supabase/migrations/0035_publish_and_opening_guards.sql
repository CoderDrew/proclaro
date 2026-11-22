-- 0035_publish_and_opening_guards: three guards from the slice 2c final review.
--
-- 1. Opening against an in-flight addendum publish. publish_addendum checks the bid due time and then runs its
--    remaining steps before it commits, and it can move the due time at least five days out. app.open_bids_gate and
--    app.lock_evaluation read bid_due_at without a lock, so a call landing just after the old due time, while the
--    publish was still in flight, judged bids closed: prices shown, the evaluation row created and the cure deadline
--    frozen, and then bidding reopened. Both now take FOR SHARE on the solicitation row before judging. They wait for
--    the publish (which holds FOR UPDATE), and the next statement reads the committed bid_due_at, so they raise
--    `sealed`. SHARE conflicts with nothing the other writers hold on that row (bid writers take SHARE, foreign keys
--    take KEY SHARE), so no lock cycle is added.
--
-- 2. A published version with missing files. Two publishes of one addendum (reviewer and checker at once) could
--    interleave so that one attempt's leftover sweep deletes the other's uploads just before the other commits,
--    leaving version n published and unwritable without its files. publish_addendum now requires the three PDFs and
--    every attachment in the snapshot to exist in the `published` bucket (`invalid_paths` otherwise), and it holds
--    FOR SHARE on those storage rows until it commits, so a concurrent delete waits and is then refused by the
--    delete rule (the version is published). The check runs after every other validation, so earlier errors keep
--    their codes. Body: the 0032 definition (its latest) with step 9b added; nothing else changes.
--
-- 3. Stale originals in the originals log (spec §4). office_bid_index reported a stale latest version as `current`
--    before close, so the clerk could log its original as if it counted. It now reports `resubmit_required` when the
--    version was priced against a bid schedule an addendum changed (app.bid_stale); `withdrawn` still wins.
--    Body: the 0010 definition (its latest) with that case added.

-- ---------------------------------------------------------------------------
-- 1. Opening and evaluation wait for an in-flight publish.
-- ---------------------------------------------------------------------------
create or replace function app.open_bids_gate(p_solicitation_id uuid)
returns timestamptz
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_due timestamptz;
begin
  perform app.require_office();
  perform 1 from public.solicitations s where s.id = p_solicitation_id for share;
  select s.bid_due_at into v_due from public.solicitations s where s.id = p_solicitation_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if not app.bids_closed(p_solicitation_id) then
    raise exception 'sealed' using errcode = 'P0001';
  end if;
  perform 1 from public.bids b where b.solicitation_id = p_solicitation_id for share;
  return v_due;
end;
$$;

create or replace function app.lock_evaluation(p_solicitation_id uuid)
returns public.evaluations
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_row public.evaluations;
begin
  perform 1 from public.solicitations s where s.id = p_solicitation_id for share;
  if not app.bids_closed(p_solicitation_id) then
    raise exception 'sealed' using errcode = 'P0001';
  end if;
  perform app.freeze_cure_due(p_solicitation_id);
  insert into public.evaluations (solicitation_id) values (p_solicitation_id)
  on conflict (solicitation_id) do nothing;
  select e.* into v_row from public.evaluations e where e.solicitation_id = p_solicitation_id for update;
  return v_row;
end;
$$;

revoke all on function app.open_bids_gate(uuid), app.lock_evaluation(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. publish_addendum: the files must exist, and stay put until commit.
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
  v_paths       text[];
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

  -- 9b (runs before 9, after every other validation). Every file of the new version is in the published bucket, and stays there until this commits.
  v_paths := array[p_rfb_path, p_bid_form_path, p_addendum_path]
             || coalesce((select array_agg(x ->> 'storagePath')
                            from jsonb_array_elements(
                                   case when jsonb_typeof(p_snapshot -> 'data' -> 'attachments') = 'array'
                                        then p_snapshot -> 'data' -> 'attachments' else '[]'::jsonb end) x),
                         '{}'::text[]);
  if exists (select 1 from unnest(v_paths) p where p is null) then
    raise exception 'invalid_paths' using errcode = 'P0001';
  end if;
  perform 1 from storage.objects o
   where o.bucket_id = 'published' and o.name = any (v_paths)
   for share;
  if (select count(distinct o.name) from storage.objects o
       where o.bucket_id = 'published' and o.name = any (v_paths))
     <> (select count(distinct p) from unnest(v_paths) p) then
    raise exception 'invalid_paths' using errcode = 'P0001';
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
-- 3. office_bid_index: stale versions are flagged.
-- ---------------------------------------------------------------------------
create or replace function public.office_bid_index(p_solicitation_id uuid)
returns table (reference text, version int, status text)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform app.require_office();
  return query
    select b.reference, v.version,
           case when w.bid_id is not null then 'withdrawn'
                when v.version = max(v.version) over (partition by v.bid_id)
                     and app.bid_stale(b.id, v.version) then 'resubmit_required'
                when v.version = max(v.version) over (partition by v.bid_id) then 'current'
                else 'superseded' end
      from public.bids b
      join public.bid_versions v on v.bid_id = b.id
      left join public.bid_withdrawals w on w.bid_id = v.bid_id and w.version = v.version
     where b.solicitation_id = p_solicitation_id
     order by b.reference, v.version;
end;
$$;
