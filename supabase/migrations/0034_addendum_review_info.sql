-- 0034_addendum_review_info: what the signed-in office user may do with one addendum (slice 2c, Task 10; R20).
--
-- The office review page reads its buttons from here instead of re-deriving the 0028/0029/0027 rules in TypeScript.
-- Each can_* flag mirrors the guard of the database function it stands for, judged on the effective state
-- (app.addendum_effective_state: after close every unpublished addendum counts as withdrawn, so no flag is true,
-- including can_withdraw):
--   can_start          start_addendum_review     submitted
--   can_return         return_addendum           in_review, caller is the reviewer
--   can_send           send_addendum_to_check    in_review, caller is the reviewer
--   can_approve_alone  approve_addendum_alone    in_review, caller is the reviewer
--   can_approve        approve_addendum_check    in_check, caller did not review in this round
--   can_disagree       disagree_addendum         in_check, caller did not review in this round
--   can_reopen         reopen_addendum_review    approved, caller is the reviewer or checker
--   can_publish        publish_addendum          approved, caller is the reviewer or checker ("bids not closed"
--                                                comes through the effective state: approved is never effective
--                                                after close)
--   can_withdraw       withdraw_addendum         effective state draft..approved (office). Judged on the effective
--                                                state, so it is false after close even though withdraw_addendum
--                                                would still let the office withdraw a stored-unpublished row
--                                                (which already counts as withdrawn)
-- The 0028 review functions also call app.require_addendum_window, so their flags also need app.bidding_open
-- (published, released, before the due time). publish_addendum and withdraw_addendum do not check the release date.
--
-- after_answers_due: now() is past the answers-due time in force before a publish (the current published snapshot's
-- data, read in settings.timezone by app.local_deadline), as publish_addendum's audit detail records it. The
-- snapshot's data and solicitations.data carry the same answersDue (publish_addendum writes both from one value).
--
-- Office staff only (not_authorized); an unknown addendum is not_found.

create function public.addendum_review_info(p_addendum_id uuid)
returns table (state public.addendum_state, effective_state public.addendum_state, reviewer_id uuid,
               checker_id uuid, can_start boolean, can_return boolean, can_send boolean, can_approve boolean,
               can_disagree boolean, can_approve_alone boolean, can_reopen boolean, can_publish boolean,
               can_withdraw boolean, after_answers_due boolean)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_row        public.addenda;
  v_eff        public.addendum_state;
  v_open       boolean;
  v_me         uuid := auth.uid();
  v_reviewer   boolean;
  v_rev_or_chk boolean;
  v_round      boolean;
  v_due        timestamptz;
begin
  perform app.require_office();
  select * into v_row from public.addenda a where a.id = p_addendum_id;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  v_eff := app.addendum_effective_state(v_row);
  v_open := app.bidding_open(v_row.solicitation_id);
  v_reviewer := v_row.reviewer_id is not distinct from v_me;
  v_rev_or_chk := v_reviewer or v_row.checker_id is not distinct from v_me;
  v_round := app.was_addendum_round_reviewer(v_row, v_me);
  v_due := app.local_deadline(
    (select s.published_snapshot -> 'data' -> 'answersDue' from public.solicitations s
      where s.id = v_row.solicitation_id));

  return query select
    v_row.state, v_eff, v_row.reviewer_id, v_row.checker_id,
    v_open and v_eff = 'submitted',
    v_open and v_eff = 'in_review' and v_reviewer,
    v_open and v_eff = 'in_review' and v_reviewer,
    v_open and v_eff = 'in_check' and not v_round,
    v_open and v_eff = 'in_check' and not v_round,
    v_open and v_eff = 'in_review' and v_reviewer,
    v_open and v_eff = 'approved' and v_rev_or_chk,
    v_eff = 'approved' and v_rev_or_chk,
    v_eff in ('draft', 'submitted', 'in_review', 'in_check', 'approved'),
    coalesce(now() > v_due, false);
end;
$$;

revoke all on function public.addendum_review_info(uuid) from public, anon, authenticated, service_role;
grant execute on function public.addendum_review_info(uuid) to authenticated;
