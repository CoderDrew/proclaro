# Addenda, Acknowledgments and the Q&A Board (Slice 2c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a published solicitation change before close, through numbered addenda that the agency drafts and the office reviews, checks and publishes. Each addendum produces a new version with new PDFs. Bidders acknowledge every addendum online. A change to the bid schedule makes earlier bids "resubmit required". Bidders ask questions anonymously, and the answers are published in the next addendum.

**Architecture:** Same model as slices 1–2b.
- Every guarantee lives in Postgres, in security-definer functions: lock → role check → state check → guarded write → one audit row.
- An addendum is a draft of the **next snapshot**:
  - an `addenda` row holds the full proposed data;
  - `publish_addendum` appends a `solicitation_versions` row and advances the current pointer columns on `solicitations`, so every 2a/2b reader keeps working unchanged.
- **"Schedule changed", "resubmit required" and "missing acknowledgments" are derived in SQL** and never stored on the bid. The one stored flag, `schedule_changed`, sits on the version row, and only `publish_addendum` writes it.
- The published-freeze trigger is relaxed narrowly. It allows changes only to the pointer columns, only inside `publish_addendum`, and only for that row.

**Tech Stack:** Unchanged: Next.js 15, React 19, TypeScript, Supabase (Postgres, Auth, Storage; `@supabase/ssr`), Zod 4, date-fns 4 + `@date-fns/tz`, Vitest, pgTAP, `playwright-core` + Chromium.

**Spec:** `docs/superpowers/specs/2026-11-20-addenda-qa-design.md` (approved, binding; its *(my call)* items are binding). Read it before any task. Earlier rulings are in `docs/decisions.md` ("Solicitation setup slice, as built", "Slice 2a, as built", "Slice 2b, as built").

## Global Constraints

- **No real data.** Use the fictional State of Calder only. Never open or copy anything under `source-docs/`.
- **Published versions are never edited.**
  - `solicitation_versions` is append-only, by trigger (`app.reject_change`) and by revoke.
  - Files under `solicitations/{id}/v{n}/` are never overwritten or deleted.
- **Deadlines use the database clock.**
  - Reads judge with `now()`.
  - Writers re-check `clock_timestamp()` after taking their row lock (Ruling 8).
  - "Closed" is `app.bids_closed` (`now() >= bid_due_at`). There is no override.
- **5-day rule (Drew):** every addendum's resulting `bid_due_at` must be `>= clock_timestamp() + interval '5 days'` at publish, or publish raises `too_close`.
- **Anonymity:**
  - `questions.body`, `asked_by` and `org_id` are readable only by the asker's organization (body and status) and office staff (everything).
  - The agency author reads questions through `public.agency_questions`, which returns no identity columns.
  - The public sees only `addendum_answers.published_question` and `answer`, and only for published addenda.
- **Sealed bids are unchanged.** Acknowledgments are not prices. A bidder reads its own acknowledgments; office staff read them only at or after close. The agency and the public never read them.
- **Append-only, by trigger (`app.reject_change`, update/delete/truncate) and by revoke:** `solicitation_versions`, `solicitation_funding_changes`, `addendum_comments`, `bid_acknowledgments`. `addenda`, `addendum_answers` and `questions` are mutable only through definer functions, with no API write grants.
- **Two-person check on addenda:**
  - The reviewer can't also be the checker, round-scoped as in slice 1 (`same_person`).
  - The fallback, `approve_addendum_alone`, stamps `single_reviewer = true` and writes `'fallback', 'no second reviewer available'` to the audit detail.
- **New SQL only in new migrations, 0026 and up.** Never edit 0001–0025; use `create or replace`, or drop and create, in a new file.
- **pgTAP for every function and policy.**
  - Every new `app.*` helper, `public` function and policy gets at least one assertion.
  - Count assertions are scoped to the test's own fixtures.
  - Every file passes against a database that already holds the seed.
- **Definer functions:**
  - `security definer`, `set search_path = ''`, fully qualified names;
  - `revoke all … from public, anon, authenticated, service_role`;
  - then `grant execute … to authenticated` only for `public` functions (and to `anon` only for `public.published_answers` and `public.solicitation_version_list`).
- **Errors** are `raise exception '<code>' using errcode = 'P0001'`.
  - New codes: `addendum_in_progress`, `locked_field`, `narrative_required`, `too_close`, `stale_draft`, `ack_missing`, `questions_closed`, `question_not_open`, `question_in_addendum`, `invalid_question`.
  - Reused codes: `not_authorized`, `not_found`, `invalid_state`, `invalid_data`, `invalid_paths`, `bid_due_mismatch`, `snapshot_mismatch`, `same_person`, `reason_required`, `comment_required`, `bids_closed`.
- **Locked fields** (an addendum can't change them): `releaseDate`, `adStart`, `adEnd`, `newspapers`, `category`. Clause locks are never re-locked.
- **Copy, verbatim:**
  - Resubmit banner: `Resubmit required: Addendum {n} changed the bid schedule.`
  - Acknowledge banner: `Addendum {n} published. Acknowledge it before bids close.`
  - Submit warning: `Bids that don't acknowledge every addendum are flagged for the agency at close.`
  - Prices-cleared notice: `Addendum {n} changed the bid schedule, so your prices were cleared. Enter them again.`
  - Fixed review note: `Did not acknowledge Addendum {n}[, {m}…].` (numbers ascending, comma-space separated)
- **Design system:**
  - No inline `style` attributes.
  - Every control comes from `src/components/ui`.
  - Irreversible posts (publish addendum, withdraw addendum, close question, acknowledge addendum) use `ConfirmAction`.
  - Use `onSubmit` + `startTransition` (not form actions), a polite live region for success, `role=alert` for errors, row-specific `aria-label`s, and `aria-describedby` on the button.
- **Gates for every task:** `npm run lint && npm test && npm run db:reset && npm run db:test`; plus `npm run db:types` after any migration and `npm run build` for UI tasks (stop the dev server first).

## Review Focus

1. **An addendum published at the edge of close.**
   - Publishing when `clock_timestamp() >= bid_due_at` (after taking the lock) raises `bids_closed`.
   - A resulting due time of exactly `clock_timestamp() + 5 days` is allowed, and one second less raises `too_close`.
   - Pinned in Task 4 with a fixture whose `bid_due_at` is set relative to `clock_timestamp()`.
2. **A draft submitted against a schedule that changed under it.**
   - Draft at `solicitation_version = 1`, then an addendum with `schedule_changed` is published, then `submit_bid` raises `stale_draft`.
   - After the reset, the draft's arrays are empty and it submits normally at version 2.
   - Pinned in Task 5.
3. **Who counts at close after a schedule change.**
   - Bidder A submitted at v1 only: excluded from `opened_bids`, `bid_review_status` returns no row, and A's v1 original doesn't count.
   - Bidder B resubmitted at v2: counted, with only its v2 original counting.
   - Bidder C submitted at v1 when the addendum didn't change the schedule: still counted.
   - Pinned in Task 5.
4. **Question identity can't leak.**
   - Another bidder reads 0 rows from `questions`, and `anon` has no grant.
   - `agency_questions` has no `asked_by`, `org_id` or `org_name` column (pgTAP `columns_are` on the function's result).
   - `published_answers` returns no `body`.
   - Pinned in Task 7.
5. **Missing acknowledgment at review.**
   - A bid missing Addendum 2 gets `ack_missing` from `set_bid_outcome(..., 'accepted', ...)`.
   - Flagging it stores a note that starts with `Did not acknowledge Addendum 2.`.
   - Non-responsive for a listed ground still works.
   - An acknowledgment recorded before close counts, and `acknowledge_addendum` at close raises `bids_closed`.
   - Pinned in Task 6.
6. **The questions deadline moves with an addendum.**
   - `ask_question` after `questionsDue` (judged in `settings.timezone` from the current `published_snapshot`) raises `questions_closed`.
   - After an addendum moves `questionsDue` later, the same call succeeds.
   - Pinned in Task 7.

---

## Names decided here (spec "Left to the builder")

- **Enum `public.addendum_state`:** `draft`, `submitted`, `in_review`, `in_check`, `approved`, `published`, `withdrawn`.
  - "Returned" means back to `draft` with a `return` comment, as in slice 1.
  - After close, an unpublished addendum is shown as withdrawn by `app.addendum_effective_state`, and the one-at-a-time guard ignores it.
- **Enum `public.question_status`:** `open`, `answered`, `closed`.
- **Enum `public.question_close_reason`:** `duplicate`, `out_of_scope`.
- **Version history:** version n = addendum number n − 1.
- **Storage paths:** `solicitations/{id}/v{n}/{rfb.pdf, bid-form.pdf, addendum.pdf, attachments/…}`.
- **Office editing.** The office does **not** edit addendum data during review (no `office_update_data` twin). It returns the addendum to the agency with comments. *(controller ruling: keeps the slice small; slice 1's office edit was for typos, and an addendum is short)*
- **Resubmit-required bids at close.** They write a `bid_close_determination` row to `bid_audit_log` with detail `{"version": v, "reason": "resubmit_required"}` (same once-per-change rule as 2a). They are listed to the office by `public.stale_bids`.
- **Missing acknowledgment at review.** It is enforced in `set_bid_outcome`: `accepted` is refused, and `flagged` gets the fixed note prepended when absent. The UI preselects `flagged` with the note. No outcome row is written automatically, because `flagged_decisions` needs a real `bid_outcomes` row.
- **Addendum numbers.** A withdrawn addendum's number is reused, so published numbers have no gaps (partial unique index).
- **Funding changes.** A new append-only table, `solicitation_funding_changes`, keyed by `(solicitation_id, version)`. `app.funding_cents` prefers its highest version, falling back to the 0014 behaviour.
- **Draft reset happens at publish**, not on read: `publish_addendum` resets every `bid_drafts` row of the solicitation when the schedule changed. `replace_bid` starts empty arrays when the latest version is stale.

## File map

- **Migrations:**
  - `0026_versions.sql`
  - `0027_addenda.sql`
  - `0028_addendum_review.sql`
  - `0029_addendum_publish.sql`
  - `0030_bid_versions_addenda.sql`
  - `0031_acknowledgments.sql`
  - `0032_questions.sql`
- **Tests:** one pgTAP file per migration, with the same stem (`supabase/tests/versions.test.sql`, …).
- **Domain:**
  - `src/domain/addendum/` (`lockedFields.ts`, `diff.ts`, `ack.ts`, with tests);
  - `src/domain/solicitation/validate.ts` gains an addendum mode.
- **Documents:**
  - `src/documents/templates/AddendumDocument.tsx`;
  - `renderAddendumHtml` in `renderHtml.ts`;
  - `bidFill.ts` and `BidFormSections.tsx` print the acknowledged addenda.
- **Routes:**
  - Agency: `src/app/agency/solicitations/[id]/addenda/[addendumId]/` (page, actions, logic).
  - Office: `src/app/office/solicitations/[id]/addenda/[addendumId]/` (page, `AddendumReviewPanel.tsx`, actions, logic, `publish.ts`).
  - Panels: `src/app/{agency,office,bidder}/solicitations/[id]/QuestionsPanel.tsx`, `src/app/bidder/solicitations/[id]/AddendaPanel.tsx`.
  - Public: `src/app/solicitations/[number]/page.tsx`.
- **Shared:** `src/app/agency/solicitations/[id]/SolicitationForm.tsx` is generalized; see Task 9.

---

### Task 1: Version history, funding changes, and the narrow freeze exception

**Files:**
- Create: `supabase/migrations/0026_versions.sql`
- Create: `supabase/tests/versions.test.sql`

**Interfaces:**
- Produces:
  - Table `public.solicitation_versions`: `solicitation_id uuid`, `version int`, `snapshot jsonb not null`, `rfb_path text not null`, `bid_form_path text not null`, `addendum_path text` (null iff version = 1), `bid_due_at timestamptz not null`, `published_at timestamptz not null default now()`, `published_by uuid references profiles`, `schedule_changed boolean not null default false`. Primary key `(solicitation_id, version)`.
    - Read: `anon` and `authenticated` select through RLS, where the solicitation is publicly readable (same predicate as the `solicitations` public read) or `app.can_see_solicitation`.
  - Table `public.solicitation_funding_changes(solicitation_id, version, funding_cents bigint >= 0, frozen_at)`, primary key `(solicitation_id, version)`, with the same read policy as `solicitation_funding`.
  - `app.funding_cents(p_id uuid) returns bigint`, replaced: the highest-version `solicitation_funding_changes` row first, else the 0014 behaviour.
  - `app.last_schedule_change(p_solicitation_id uuid) returns int`: the max `version` with `schedule_changed`, else 1.
  - `app.reject_published_change()`, replaced. When `old.state = 'published'` it raises as before **unless both** hold:
    - `current_setting('app.publishing_addendum', true) = old.id::text`;
    - every column other than `version`, `published_snapshot`, `data`, `bid_due_at`, `rfb_path`, `bid_form_path` is unchanged (`id`, `agency_id`, `state`, `number`, `release_date`, `published_at`, `reviewer_id`, `checker_id`, …).
  - `public.publish_solicitation` (6-argument), replaced: the 0014 body, plus it inserts the version-1 `solicitation_versions` row (`published_by = auth.uid()`).
  - `public.solicitation_version_list(p_solicitation_id uuid) returns table(version int, published_at timestamptz, rfb_path text, bid_form_path text, addendum_path text, is_current boolean)`. Granted to anon and authenticated, with the same visibility as the row.
  - A backfill inserts version 1 for every already-published solicitation from its current columns (`published_by` null).

- [ ] **Step 1: Write the failing pgTAP tests** in `versions.test.sql`:
  - `has_table('public','solicitation_versions')`, `col_is_pk(... array['solicitation_id','version'])`.
  - Publishing a fixture solicitation creates exactly one version row: version 1, `addendum_path` null, `schedule_changed` false, `published_by` = the publisher.
  - `update`/`delete` on `solicitation_versions` throws, as office and as postgres.
  - Updating a published solicitation's `bid_due_at` without the setting throws `solicitation % is published and read-only`.
  - With `set_config('app.publishing_addendum', <id>, true)` the same update succeeds.
  - With the setting, changing `state` or `number` throws.
  - With the setting for a different id, the update throws.
  - `app.funding_cents` returns the `solicitation_funding` value, then the funding-change value after inserting a version-2 change.
  - `app.last_schedule_change` returns 1 with no flagged rows, and 3 after inserting a version-3 row with `schedule_changed`.
  - Seeded 27-0003 has exactly one version row (backfill).
  - `anon` sees a released published solicitation's versions and none of a draft's.
- [ ] **Step 2:** `npm run db:reset && npm run db:test`. Expected: the new file fails.
- [ ] **Step 3:** Write `0026_versions.sql` implementing the Interfaces above.
- [ ] **Step 4:** `npm run db:reset && npm run db:test && npm run db:types`. Expected: all pass.
- [ ] **Step 5:** `npm run lint && npm test`, then commit `feat(db): solicitation version history and the addendum freeze exception`.

---

### Task 2: Addenda table, drafting and the locked-field rule

**Files:**
- Create: `supabase/migrations/0027_addenda.sql`, `supabase/tests/addenda.test.sql`
- Create: `src/domain/addendum/lockedFields.ts`, `src/domain/addendum/lockedFields.test.ts`
- Modify: `src/domain/solicitation/validate.ts` (+ test)

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - Enum `public.addendum_state` (see Names).
  - Table `public.addenda`: `id uuid pk`, `solicitation_id`, `number int not null`, `state addendum_state not null default 'draft'`, `data jsonb not null` (full solicitation data **including** `fundingAmountCents`), `narrative text not null default ''`, `created_by`, `created_at`, `latest_submitted_at`, `reviewer_id`, `checker_id`, `single_reviewer boolean not null default false`, `published_version int`, `withdrawn_reason text`.
    - Partial unique index on `(solicitation_id, number) where state <> 'withdrawn'`, so a withdrawn number is reused.
    - Check: reviewer ≠ checker.
    - Select through RLS for `app.can_see_solicitation(solicitation_id)` only, so bidders and anon get nothing. No API write grants.
  - Table `public.addendum_comments(id, addendum_id, field text, body text not null, kind public.comment_kind, author_id, created_at)`. Append-only. Same read predicate as `addenda`.
  - `app.lock_addendum(p_id uuid) returns public.addenda` (`for update`, `not_found`).
  - `app.addendum_effective_state(p_row public.addenda) returns public.addendum_state`: `withdrawn` when the row is unpublished and `app.bids_closed(solicitation_id)`, else `p_row.state`.
  - `app.locked_fields() returns text[]` = `{releaseDate,adStart,adEnd,newspapers,category}`, kept in sync with TS by a marker-comment parity test, as `required_data_keys` is.
  - `public.start_addendum(p_solicitation_id uuid) returns uuid`. Callable by an agency user of the owning agency.
    - Requires: solicitation `published`, `bidding open`, and no other addendum whose effective state is unpublished and not withdrawn (`addendum_in_progress`).
    - Sets `number` = (count of `published` addenda for the solicitation) + 1. A withdrawn addendum's number is reused, so published numbers never have gaps.
    - `data` = `solicitations.data` with `fundingAmountCents` = `app.funding_cents(id)`.
    - Audit `start_addendum`.
  - `public.save_addendum(p_addendum_id uuid, p_data jsonb, p_narrative text) returns void`.
    - Callable by the owning agency, in state `draft`, while bidding is open.
    - Raises `locked_field` when any locked key differs from the current `solicitations.data`.
    - Raises `invalid_data` when `p_data` lacks a required key (`app.required_data_keys()`).
    - Not audited (autosave, like `solicitations.data`).
  - `public.submit_addendum(p_addendum_id uuid) returns void`: owning agency, `draft` → `submitted`; `narrative_required` when the trimmed narrative is empty; sets `latest_submitted_at`; audited.
  - `public.withdraw_addendum(p_addendum_id uuid, p_reason text) returns void`: agency from `draft`; office from any unpublished state; `reason_required`; `→ withdrawn`; audited. (Questions picked into it go back to open: Task 7 wires the effect, since `addendum_answers` doesn't exist yet.)
  - TS: `LOCKED_FIELDS: readonly (keyof SolicitationData)[]` and `lockedFieldChanges(base: SolicitationData, next: SolicitationData): (keyof SolicitationData)[]` in `lockedFields.ts`.
  - TS: `validate(data, opts)` accepts `opts.mode?: "setup" | "addendum"`. In addendum mode it skips every rule whose field is in `LOCKED_FIELDS` and the release-date-vs-submission rules. It adds the error `{code: "too_close", field: "bidDueDate", message: "Bids must stay open at least 5 days after this addendum is published."}` when the bid due instant is earlier than `opts.now + 5 days`.
  - Audit rows use `app.audit(solicitation_id, '<function name>', detail)`, and the detail always carries `'addendum_id'` and `'number'`.

- [ ] **Step 1: Write failing tests.**
  - pgTAP:
    - start (agency of owner OK; other agency `not_authorized`; bidder `not_authorized`);
    - a second start → `addendum_in_progress`;
    - start after withdrawing Addendum 1 → number 1 again;
    - start on a closed solicitation → `bids_closed`;
    - save changing `releaseDate` → `locked_field`;
    - save in `submitted` → `invalid_state`;
    - submit with blank narrative → `narrative_required`;
    - withdraw by agency from `submitted` → `invalid_state`, by office → ok;
    - after the solicitation closes, an addendum left `in_review` has effective state `withdrawn` and a new `start_addendum` raises `bids_closed` (not `addendum_in_progress`);
    - a bidder selects 0 rows from `addenda`;
    - `app.locked_fields()` matches the TS list (parity file, as for required keys).
  - Vitest:
    - `lockedFieldChanges` reports exactly the changed locked keys;
    - addendum-mode validation ignores a past `releaseDate` and still reports `date_order` between `questionsDue` and `bidDueDate`;
    - `too_close` at now + 5 days − 1 minute but not at now + 5 days.
- [ ] **Step 2:** Run the tests. Expected: they fail.
- [ ] **Step 3:** Implement `0027_addenda.sql`, `lockedFields.ts` and the validate mode.
- [ ] **Step 4:** Run all gates plus `db:types`. Expected: pass.
- [ ] **Step 5:** Commit `feat: addenda drafting with locked fields`.

---

### Task 3: Addendum review and two-person check

**Files:**
- Create: `supabase/migrations/0028_addendum_review.sql`, `supabase/tests/addendum_review.test.sql`

**Interfaces:**
- Consumes: Task 2 (`app.lock_addendum`, `addenda`, `addendum_comments`).
- Produces. Each function has the slice 1 twin's behaviour, check order and errors, applied to an addendum. Each one also raises `bids_closed` when the solicitation is closed (re-judged with `clock_timestamp()` after the lock):
  - `public.start_addendum_review(p_addendum_id uuid)`: office, `submitted → in_review`, reviewer = caller.
  - `public.reassign_addendum_review(p_addendum_id uuid, p_user uuid)`: office, `in_review`.
  - `public.return_addendum(p_addendum_id uuid, p_comments jsonb)`: reviewer, `in_review → draft`. Inserts `return` comments; `invalid_comments` for anything that isn't a non-empty array of `{field, body}`.
  - `public.send_addendum_to_check(p_addendum_id uuid)`: reviewer, `in_review → in_check`.
  - `public.approve_addendum_check(p_addendum_id uuid)`: office, `in_check → approved`, checker = caller. Raises `same_person` when the caller was a reviewer in the current round (`app.was_addendum_round_reviewer`).
  - `public.disagree_addendum(p_addendum_id uuid, p_comment text)`: office non-reviewer, `in_check → in_review`; `comment_required`; inserts a `disagree` comment.
  - `public.approve_addendum_alone(p_addendum_id uuid)`: reviewer, `in_check → approved`, `single_reviewer = true`, audit fallback detail.
  - `public.reopen_addendum_review(p_addendum_id uuid, p_reason text)`: office, `approved → in_review`; `reason_required`.
  - `app.was_addendum_round_reviewer(p_row public.addenda, p_user uuid) returns boolean`: the round starts at the latest `submit_addendum` or `reopen_addendum_review` audit row for this addendum id. Reviewers are the current reviewer plus every actor of `start_addendum_review`/`reassign_addendum_review` in the round (same shape as `app.was_round_reviewer`).

- [ ] **Step 1: Write failing pgTAP:**
  - the happy path draft → approved with two office users (reviewer1, reviewer2);
  - `approve_addendum_check` by the reviewer → `same_person`;
  - after reassignment from reviewer1 to reviewer2, reviewer1 approving → `same_person`;
  - `approve_addendum_alone` stamps `single_reviewer` and the fallback audit detail;
  - return → draft with a comment row of kind `return`;
  - agency calling any of these → `not_authorized`;
  - every transition after close → `bids_closed`;
  - each function writes exactly one `audit_log` row (scoped by `detail->>'addendum_id'`).
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement `0028_addendum_review.sql`.
- [ ] **Step 4:** Run all gates plus `db:types`. Expected: pass.
- [ ] **Step 5:** Commit `feat(db): addendum review and two-person check`.

---

### Task 4: Schedule diff and `publish_addendum`

**Files:**
- Create: `supabase/migrations/0029_addendum_publish.sql`, `supabase/tests/addendum_publish.test.sql`
- Create: `src/domain/addendum/diff.ts`, `src/domain/addendum/diff.test.ts`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `app.schedule_changed(p_old jsonb, p_new jsonb) returns boolean` (immutable). The arguments are snapshot `data` objects. Returns true iff `p_old->'schedule'->'items'` and `p_new->'schedule'->'items'` differ, or the two `alternates` arrays differ. Compared as jsonb arrays of `{name, description}` and `{kind, description}`, with element order significant.
  - `public.publish_addendum(p_addendum_id uuid, p_rfb_path text, p_bid_form_path text, p_addendum_path text, p_snapshot jsonb, p_bid_due_at timestamptz, p_funding_cents bigint) returns int` (the new version). Order:
    1. `require_office`, then lock the addendum, then lock the solicitation.
    2. State `approved`, and the caller is the reviewer or checker.
    3. `bids_closed` when `clock_timestamp() >= solicitations.bid_due_at`.
    4. Paths pinned to `solicitations/{sid}/v{n}/rfb.pdf`, `/bid-form.pdf` and `/addendum.pdf`, with n = current version + 1 (`invalid_paths`).
    5. `bid_due_at` recomputed from `addenda.data` by `app.bid_due_at` (`bid_due_mismatch`).
    6. `too_close` when the recomputed value is `< clock_timestamp() + interval '5 days'`.
    7. Funding equals `addenda.data->fundingAmountCents`, and the snapshot carries no `fundingAmountCents` at any depth (`snapshot_mismatch`).
    8. `locked_field` re-checked against `solicitations.data`.
    9. `schedule_changed` computed from the old and new `data`.
    10. Insert `solicitation_versions` and `solicitation_funding_changes`.
    11. `set_config('app.publishing_addendum', sid, true)`, then update the pointer columns. `data` is set to the addendum data without `fundingAmountCents`. Then reset the setting.
    12. When the schedule changed, reset every `bid_drafts` row of that solicitation's bids: `item_cents = '{}'`, `alternate_cents = '{}'`, `solicitation_version = n`. The column comes from Task 5, so this step lands there; leave a `-- Task 5` marker.
    13. The addendum becomes `published`, `published_version = n`.
    14. Audit `publish_addendum` with `version`, `schedule_changed`, `bid_due_at` and `after_answers_due` (now later than `answersDue` read in the timezone).
  - `app.can_write_published_file(p_name text)`, replaced. It also allows `v{n}` paths when the solicitation is `published` and has an `approved` addendum whose number = n − 1 (and keeps the `approved`-solicitation case for v1).
  - `app.can_access_attachment(p_name text, p_write boolean)`, replaced. The owning agency may also write while the solicitation has an addendum in `draft`.
  - TS: `type ScheduleChange = {kind: "item" | "alternate"; change: "added" | "removed" | "changed"; position: number; before?: string; after?: string}` and `diffSchedule(oldSchedule, newSchedule): ScheduleChange[]` (positional, 1-based), plus `scheduleChanged(old, new): boolean` = `diffSchedule(...).length > 0`.
- **Parity:** `diff.test.ts` and `addendum_publish.test.sql` use the same six cases: identical; item added at end; item removed; item renamed; alternate kind flipped; two items swapped. SQL's boolean must equal `diffSchedule(...).length > 0` for each.

- [ ] **Step 1: Write failing tests.**
  - Vitest: the six diff cases, with exact `ScheduleChange[]` expectations.
  - pgTAP:
    - the six `app.schedule_changed` cases;
    - a happy publish (version 2, pointers moved, v1 row unchanged, the addendum published);
    - wrong path → `invalid_paths`;
    - due mismatch → `bid_due_mismatch`;
    - due at `clock_timestamp() + 5 days − 1 second` → `too_close`;
    - closed → `bids_closed`;
    - funding in the snapshot → `snapshot_mismatch`;
    - not reviewer or checker → `not_authorized`;
    - `app.funding_cents` returns the new funding afterwards;
    - an office upload to `v2/rfb.pdf` is allowed only while an approved addendum 1 exists.
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement `diff.ts` and `0029_addendum_publish.sql`.
- [ ] **Step 4:** Run all gates plus `db:types`. Expected: pass.
- [ ] **Step 5:** Commit `feat: publish addenda as new solicitation versions`.

---

### Task 5: Bids priced against a version, and resubmit required

**Files:**
- Create: `supabase/migrations/0030_bid_versions_addenda.sql`, `supabase/tests/bid_versions_addenda.test.sql`

**Interfaces:**
- Consumes: Tasks 1 and 4 (`app.last_schedule_change`, `publish_addendum`).
- Produces:
  - Column `bid_drafts.solicitation_version int not null default 1` and column `bid_versions.solicitation_version int not null default 1`, backfilled to 1.
  - `publish_addendum`, replaced, with step 12 (the draft reset) implemented.
  - `public.start_bid`, replaced: the draft's `solicitation_version` = the solicitation's current `version`.
  - `public.replace_bid`, replaced: when the latest version is stale, the new draft gets empty arrays and the current version; otherwise it behaves as before.
  - `public.submit_bid`, replaced: after the existing checks and lock, raises `stale_draft` when `draft.solicitation_version < app.last_schedule_change(sid)`. It copies `solicitation_version` into `bid_versions`.
  - `app.bid_stale(p_bid_id uuid, p_version int) returns boolean`: that version's `solicitation_version < app.last_schedule_change`.
  - `app.bid_excluded(p_bid_id uuid, p_version int) returns boolean` = `app.is_withdrawn(...) or app.bid_stale(...)`.
  - **Every post-close reader** whose latest definition calls `app.is_withdrawn(` is replaced to call `app.bid_excluded(`. Known sites:
    - `public.opened_bids` and `public.opened_bid_files` (0012);
    - `app.bond_cure` and `app.can_read_bid_file` (0016; latest definitions);
    - `app.bid_review_status` (0018);
    - `app.recap_bids` (0022), if it does not already go through `bid_review_status`.

    Grep `is_withdrawn(` across 0010–0025 and list every replaced function in the migration header. Bidder-facing functions (`withdraw_bid`, `my_bid_receipts`, `bidding_state`) keep `is_withdrawn`.
  - `public.opened_bids` also writes, for each stale bid, a `bid_close_determination` row with detail `{"version": v, "reason": "resubmit_required"}`, once per change, as 2a does.
  - `public.stale_bids(p_solicitation_id uuid) returns table(bid_id uuid, reference text, bidder_legal_name text, version int, solicitation_version int)`: office only, at or after close (`sealed` before). No prices.
  - `public.my_bid_status_addenda(p_bid_id uuid) returns table(resubmit_required boolean, schedule_changed_in int, draft_cleared_by int)`: owning bidder only.
    - `schedule_changed_in` is the addendum number of the latest schedule change after the bid's latest submitted version, else null.
    - `draft_cleared_by` is set when all of these hold, else null:
      - `app.last_schedule_change(sid)` = v > 1;
      - the draft's `solicitation_version` = v;
      - both price arrays are empty;
      - the bid's `created_at` is before that version's `published_at`.

      Its value is v − 1.
    - Pinned in the same pgTAP file.

- [ ] **Step 1: Write failing pgTAP**, covering Review Focus 2 and 3 exactly:
  - stale submit → `stale_draft`;
  - after the reset, the arrays are empty and `solicitation_version` = 2;
  - bidders A, B and C at close: `opened_bids` lists B and C, not A;
  - A's v1 original doesn't count, and `bid_review_status(A)` returns no row;
  - `stale_bids` lists A;
  - a determination row for A has reason `resubmit_required`;
  - `my_bid_status_addenda(A)` = `(true, 1, …)`;
  - a schedule-neutral addendum leaves C counted.
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement `0030_bid_versions_addenda.sql`.
- [ ] **Step 4:** Run all gates plus `db:types`. The existing 2a/2b suites must still pass unchanged.
- [ ] **Step 5:** Commit `feat(db): resubmit required after a schedule change`.

---

### Task 6: Acknowledgments

**Files:**
- Create: `supabase/migrations/0031_acknowledgments.sql`, `supabase/tests/acknowledgments.test.sql`
- Create: `src/domain/addendum/ack.ts`, `src/domain/addendum/ack.test.ts`

**Interfaces:**
- Consumes: Tasks 4–5.
- Produces:
  - Table `public.bid_acknowledgments(bid_id uuid references bids, addendum_number int, acknowledged_at timestamptz not null default now(), acknowledged_by uuid not null)`, primary key `(bid_id, addendum_number)`. Append-only. No direct grants: read through functions only.
  - `public.acknowledge_addendum(p_bid_id uuid, p_addendum_number int) returns void`.
    - Callable by the owning bidder.
    - The addendum must be published (`not_found` otherwise).
    - `bids_closed` is re-judged with `clock_timestamp()` after `app.lock_bid`.
    - Idempotent: a second call is a no-op with no second row.
    - Audit `acknowledge_addendum` in `bid_audit_log`.
  - `public.my_bid_acknowledgments(p_bid_id uuid) returns table(addendum_number int, published_at timestamptz, acknowledged_at timestamptz)`: owning bidder. Every published addendum, with `acknowledged_at` null when not acknowledged.
  - `app.missing_acknowledgments(p_bid_id uuid) returns int[]`: published addendum numbers (ascending) without an acknowledgment.
  - `app.ack_note(p_missing int[]) returns text` = `'Did not acknowledge Addendum ' || array_to_string(p_missing, ', ') || '.'`
  - `public.set_bid_outcome`, replaced. When `app.missing_acknowledgments(bid)` is non-empty:
    - `accepted` raises `ack_missing`;
    - `flagged` stores `ack_note(...)` followed by a space and the reviewer's note, unless the note already starts with it;
    - `non_responsive` is unchanged.
  - `public.review_bids` (0018), replaced: adds column `missing_addenda int[]`. Office only, after close, as today.
  - TS `ackNote(missing: number[]): string` (same text) and `missingAcknowledgments(published: number[], acknowledged: number[]): number[]`.

- [ ] **Step 1: Write failing tests.**
  - pgTAP:
    - acknowledge OK, then again with still one row;
    - another bidder → `not_authorized`;
    - unpublished number → `not_found`;
    - at close → `bids_closed`;
    - Review Focus 5 exactly;
    - `review_bids` shows `{2}` for the bid missing Addendum 2;
    - an office user before close calling `my_bid_acknowledgments` → `not_authorized`;
    - the agency can't select `bid_acknowledgments`.
  - Vitest:
    - `ackNote([1,3])` = `Did not acknowledge Addendum 1, 3.`;
    - `missingAcknowledgments([1,2,3],[2])` = `[1,3]`.
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement the migration and `ack.ts`.
- [ ] **Step 4:** Run all gates plus `db:types`. Expected: pass.
- [ ] **Step 5:** Commit `feat: addendum acknowledgments and the missing-acknowledgment flag`.

---

### Task 7: Questions and answers

**Files:**
- Create: `supabase/migrations/0032_questions.sql`, `supabase/tests/questions.test.sql`

**Interfaces:**
- Consumes: Tasks 2 and 4.
- Produces:
  - Enums `public.question_status`, `public.question_close_reason`.
  - Table `public.questions`: `id`, `solicitation_id`, `asked_by uuid not null`, `org_id uuid not null`, `body text not null check (char_length(btrim(body)) between 1 and 4000)`, `reference text not null default ''` (≤ 200), `asked_at timestamptz not null default now()`, `status question_status not null default 'open'`, `answered_in uuid references addenda`, `close_reason question_close_reason`, `closed_by`, `closed_at`.
    - RLS select for the asker's org (`org_id = app.my_org()`) or office.
    - `grant select on public.questions to authenticated`, with RLS limiting rows to the asker's org or the office. The agency matches neither predicate and reads only through `agency_questions`.
    - No API write grants.
  - Table `public.addendum_answers(addendum_id uuid references addenda, question_id uuid references questions, published_question text not null, answer text not null, primary key (addendum_id, question_id))`, with `unique (question_id)` among published addenda enforced in the writer. No direct grants.
  - `public.ask_question(p_solicitation_id uuid, p_body text, p_reference text) returns uuid`.
    - Callable by a bidder (`app.require_bidder`), on a published, released solicitation.
    - `questions_closed` when `clock_timestamp()` ≥ the `questionsDue` instant from `published_snapshot->'data'`, read in `settings.timezone`, or when bidding has closed.
    - `invalid_question` for a body or reference outside its limits.
    - Audited.
  - `public.my_questions(p_solicitation_id uuid) returns table(id, body, reference, asked_at, status, answered_in_number int, close_reason)`: the caller's org.
  - `public.office_questions(p_solicitation_id uuid) returns table(id, body, reference, asked_at, status, answered_in_number int, close_reason, org_name text, asker_name text)`: office.
  - `public.agency_questions(p_solicitation_id uuid) returns table(id, body, reference, asked_at, status, answered_in_number int, in_draft boolean)`: the owning agency. **No identity columns.**
  - `public.close_question(p_question_id uuid, p_reason question_close_reason) returns void`: office; `question_not_open` unless open; `question_in_addendum` when the question is in an unpublished, non-withdrawn addendum's answers; audited.
  - `public.save_addendum_answer(p_addendum_id uuid, p_question_id uuid, p_published_question text, p_answer text) returns void`.
    - Callable by the owning agency, with the addendum in `draft`.
    - The question belongs to the same solicitation and is `open` (`question_not_open`).
    - Both texts are 1–4000 characters after trimming (`invalid_data`).
    - Upsert.
  - `public.remove_addendum_answer(p_addendum_id uuid, p_question_id uuid) returns void`: owning agency, `draft`.
  - `public.addendum_answers_draft(p_addendum_id uuid) returns table(question_id, published_question, answer)`: agency owner and office.
  - `publish_addendum`, replaced: also sets each answered question to `answered`, `answered_in = addendum id`. The `submit_addendum` and `withdraw_addendum` bodies are unchanged. Withdrawn answers are simply ignored, since the questions stay `open`.
  - `public.published_answers(p_solicitation_id uuid) returns table(addendum_number int, published_question text, answer text)`: anon and authenticated; only published addenda of a publicly readable solicitation; ordered by addendum number, then `asked_at`.

- [ ] **Step 1: Write failing pgTAP**, covering Review Focus 4 and 6 exactly, plus:
  - an agency user calling `ask_question` → `not_authorized`;
  - an empty body → `invalid_question`;
  - closing an answered question → `question_not_open`;
  - closing a question in a draft → `question_in_addendum`;
  - after publish, the question is `answered` and `my_questions` shows the addendum number;
  - after withdraw, the question is still `open` and can be answered in the next addendum;
  - `published_answers` shows only the published question text, never `body`.
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement `0032_questions.sql`.
- [ ] **Step 4:** Run all gates plus `db:types`. Expected: pass.
- [ ] **Step 5:** Commit `feat(db): anonymous Q&A answered through addenda`.

---

### Task 8: Documents and the publish pipeline

**Files:**
- Create: `src/documents/templates/AddendumDocument.tsx`
- Modify: `src/documents/renderHtml.ts`, `src/documents/bidFill.ts`, `src/documents/templates/BidFormSections.tsx` (+ tests and snapshots)
- Create: `src/app/office/solicitations/[id]/addenda/[addendumId]/publish.ts` and `publish.test.ts`

**Interfaces:**
- Consumes: Task 4 (`publish_addendum`, `diffSchedule`), Task 6 (bidder acknowledgments), Task 7 (answers).
- Produces:
  - `interface AddendumDocContext { number: number; version: number; solicitationNumber: string; title: string; publishedOn: string /* local date */; narrative: string; changes: ScheduleChange[]; dateChanges: {field: string; before: string; after: string}[]; answers: {publishedQuestion: string; answer: string}[] }`
  - `renderAddendumHtml(ctx: AddendumDocContext): string`. It uses `Layout` with the footer `{solicitationNumber} · Version {version} · Page X of Y`, the same footer mechanism as the bid form.
  - `BidFill` gains `acknowledgedAddenda: number[]`. The "Addenda acknowledged (list numbers)" cell prints them joined by `, `, or the blank line when the list is empty or the form is blank.
  - `publishAddendum(addendumId: string, d: PublishAddendumDeps): Promise<PublishResult>`. It mirrors `publishSolicitation` (injected deps, cleanup of uploaded objects on failure, `messageFor` errors):
    1. Load the addendum and its solicitation.
    2. Validate in addendum mode.
    3. Render the RFB and bid form with `version: n` and the addendum PDF.
    4. Upload to `v{n}`, and copy the attachments to `v{n}/attachments/`.
    5. Build the snapshot without funding.
    6. Call `publish_addendum`.

    It returns `{ok: true, number}`.
  - `messageFor` (office logic) gains messages for `too_close`, `locked_field`, `stale_draft`, `ack_missing`, `questions_closed`, `question_not_open`, `question_in_addendum`, `addendum_in_progress`, `narrative_required`, `invalid_question`.

- [ ] **Step 1: Write failing Vitest tests:**
  - `renderAddendumHtml` snapshot, plus asserting it contains the narrative, `Item 3 added`, the published question and `Version 2`;
  - the bid form prints `1, 2` when the draft has acknowledged addenda 1 and 2;
  - a blank form prints the blank line;
  - `publishAddendum`:
    - happy path: calls `put` for the three v2 paths, then the RPC with `p_funding_cents` and a snapshot with no `fundingAmountCents`;
    - an RPC error `too_close` removes the uploaded objects and returns its message;
    - a locked-field change returns errors without uploading.
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `npm run lint && npm test`. Expected: pass. The slow PDF test (`npm run test:slow`) renders a real addendum PDF.
- [ ] **Step 5:** Commit `feat(documents): addendum PDF and acknowledged addenda on the bid form`.

---

### Task 9: Agency screens: addenda and questions

**Files:**
- Modify: `src/app/agency/solicitations/[id]/SolicitationForm.tsx`, `page.tsx`
- Create: `src/app/agency/solicitations/[id]/addenda/[addendumId]/{page.tsx, AddendumEditor.tsx, actions.ts, logic.ts, logic.test.ts}`
- Create: `src/app/agency/solicitations/[id]/QuestionsPanel.tsx`

**Interfaces:**
- Consumes: Tasks 2, 3, 4 (`diffSchedule`), 7.
- Produces:
  - `SolicitationForm` takes an optional `mode: "setup" | "addendum"` (default `"setup"`) and an injected `actions: {save(data): Promise<void>; upload(fileName): Promise<{path; token}>; acknowledgeWarning?; submit(): Promise<SubmitResult>}`.
    - The existing page passes the current server actions unchanged.
    - In addendum mode, locked fields render read-only (disabled look, `not-allowed`), validation runs in addendum mode, and `editable` = `addendum.state === "draft"`.
  - `AddendumEditor` composes:
    - the narrative textarea (required);
    - `SolicitationForm` in addendum mode;
    - a "Changes to the bid schedule" list from `diffSchedule(currentSnapshot.schedule, data.schedule)`;
    - an Answers section: the open questions from `agency_questions`, each with "Answer in this addendum", which opens published-question and answer fields (`save_addendum_answer` / `remove_addendum_answer`);
    - return comments, as the setup form shows them;
    - Submit;
    - Withdraw (ConfirmAction with reason).
  - The agency solicitation page, when published, shows:
    - an **Addenda** card listing every addendum (number, state badge using `addendum_effective_state`, published date), with "Start addendum" while bidding is open and none is in progress;
    - **Questions** (`agency_questions`, no names).
  - `logic.ts` exports pure helpers with tests: `canStartAddendum(state, closed, inProgress): boolean` and `answerDraftProblems(answers): Issue[]`.

- [ ] **Step 1:** Write failing Vitest tests for the logic helpers and the actions' error mapping (pattern: `src/app/agency/solicitations/[id]/actions.test.ts`).
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run all gates plus `npm run build`. Expected: pass.
- [ ] **Step 5:** Commit `feat(agency): draft addenda and answer questions`.

---

### Task 10: Office screens: addendum review, publish, and questions

**Files:**
- Create: `src/app/office/solicitations/[id]/addenda/[addendumId]/{page.tsx, AddendumReviewPanel.tsx, actions.ts, logic.ts, logic.test.ts}`
- Create: `src/app/office/solicitations/[id]/QuestionsPanel.tsx`
- Modify: `src/app/office/solicitations/[id]/page.tsx`

**Interfaces:**
- Consumes: Tasks 3, 7 and 8 (`publishAddendum`).
- Produces:
  - The review page shows the addendum read-only:
    - the narrative;
    - the schedule diff;
    - date changes;
    - the answers;
    - the history (audit rows for this addendum id);
    - every action from Task 3, permitted per the canX flags returned by `public.addendum_review_info(p_addendum_id uuid) returns table(state, effective_state, reviewer_id, checker_id, can_start, can_return, can_send, can_approve, can_disagree, can_approve_alone, can_reopen, can_publish, can_withdraw, after_answers_due boolean)`. Add that function to `0028` via a new migration `0033_addendum_review_info.sql` with pgTAP in `addendum_review.test.sql`.
  - Publish is a `ConfirmAction`. When `after_answers_due` is set, its body includes `The answers-due date has passed. Publish anyway?`.
  - The office solicitation page lists addenda (with links) and the **Questions** panel from `office_questions`: organization, asker and status, plus a Close action (ConfirmAction with a reason choice).

- [ ] **Step 1:** Write failing tests: pgTAP for `addendum_review_info` flags per role and state; Vitest for the logic and action error mapping.
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run all gates plus `db:types` and `npm run build`. Expected: pass.
- [ ] **Step 5:** Commit `feat(office): review, check and publish addenda; close questions`.

---

### Task 11: Bidder screens: questions, acknowledgments and resubmit required

**Files:**
- Create: `src/app/bidder/solicitations/[id]/{AddendaPanel.tsx, QuestionsPanel.tsx}`
- Modify: `src/app/bidder/solicitations/[id]/{page.tsx, actions.ts, logic.ts, logic.test.ts, BidDraftForm.tsx}`

**Interfaces:**
- Consumes: Tasks 5, 6, 7.
- Produces:
  - **`AddendaPanel`** (`my_bid_acknowledgments`): one row per published addendum, with a link to its PDF, and either "Acknowledged {date}" or an Acknowledge `ConfirmAction` (row-specific `aria-label` `Acknowledge Addendum {n}`).
    - Shown whenever the bidder has a bid, drafted or submitted.
    - The acknowledge banner (Global Constraints copy) appears above the bid form while any addendum is unacknowledged and bidding is open.
  - **Resubmit required** (`my_bid_status_addenda`): when `resubmit_required`, the resubmit banner shows, and the receipt panel marks the old submission "Not counted".
  - **Prices cleared:** when `draft_cleared_by` is set, the prices-cleared notice shows above the price inputs.
  - **Submit warning:** the submit area shows the warning text whenever `missingAcknowledgments(...)` is non-empty. It does not block.
  - **`QuestionsPanel`:**
    - "Ask a question" form (body textarea, optional reference), shown until `questionsDue`;
    - after that: `Questions closed {date time}`;
    - "Your questions" from `my_questions`, with status badges `Open`, `Answered in Addendum {n}` and `Closed: duplicate` / `Closed: out of scope`.
    - Shown on the bidder solicitation page even before a bid is started.
  - `logic.ts`: `addendaBanners(acks, status, open): Banner[]` (tested), returning the exact copy strings.

- [ ] **Step 1:** Write failing Vitest tests for `addendaBanners` (each copy string verbatim, and no banner after close) and for the action error mapping (`stale_draft`, `questions_closed`, `bids_closed`).
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run all gates plus `npm run build`. Expected: pass.
- [ ] **Step 5:** Commit `feat(bidder): acknowledge addenda, ask questions, resubmit after schedule changes`.

---

### Task 12: Public page and the office bid review

**Files:**
- Modify: `src/app/solicitations/[number]/page.tsx`
- Modify: `src/app/office/solicitations/[id]/review/{ReviewTable.tsx, page.tsx, logic.ts, logic.test.ts}`
- Modify: `src/app/office/solicitations/[id]/bids/page.tsx`

**Interfaces:**
- Consumes: Tasks 1, 5, 6, 7.
- Produces:
  - **The public page:**
    - a **Versions** section (`solicitation_version_list`) with the current version marked and the RFB, bid form and addendum PDF links per version;
    - **Questions and answers** grouped by addendum (`published_answers`), with no names.
  - **The office review table:**
    - shows `missing_addenda` per bid;
    - for such a bid, preselects **Accepted, flagged for the agency** with the `ackNote` prefilled;
    - hides "Accepted" (the database would refuse it with `ack_missing`, which is mapped to a message).
  - **The office bids page:** lists `stale_bids` under "Not counted: resubmit required", with reference, legal name and the version it was priced against. No prices.

- [ ] **Step 1:** Write failing Vitest tests for the review logic (the preselected outcome and note for missing addenda) and the public grouping helper.
- [ ] **Step 2:** Run. Expected: fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run all gates plus `npm run build`. Expected: pass.
- [ ] **Step 5:** Commit `feat: public versions and Q&A; missing acknowledgments in review`.

---

### Task 13: Seeds, docs and the browser walk

**Files:**
- Modify: `supabase/seed.sql`, `README.md`, `docs/decisions.md`

**Interfaces:**
- Consumes: everything.
- Produces:
  - **Seed 27-0004 (open, $1.5M):**
    - a published Addendum 1 that adds an item (version 2, `schedule_changed`, version rows 1 and 2, no PDFs);
    - questions: one answered by Addendum 1 (with `addendum_answers`), one open, one closed `duplicate`, asked by Ridgeback and Granite;
    - Granite's bid submitted at v1 (so resubmit required);
    - Ridgeback's draft at v2 with Addendum 1 unacknowledged.
  - **Seed 27-0001:** an Addendum 1 in `draft` by the owning agency's author (check `seed.sql` for which seeded author that is), which moves the bid due date 7 days later, with a narrative.
  - **README:** the seed list updated for both.
  - **`docs/decisions.md`:** a new section "Slice 2c, as built", with every controller ruling from this plan's "Names decided here" and any made during execution.

- [ ] **Step 1:** Add seeds. `npm run db:reset && npm run db:test`. Expected: pass, since seed-independent tests still pass.
- [ ] **Step 2:** Browser walk on the dev server, with the seeded users (dev email login, local only):
  1. The 27-0001 agency author opens the draft addendum, edits the narrative and submits.
  2. `reviewer1` starts the review and sends it to check; `reviewer2` approves and publishes.
  3. The public page shows versions 1 and 2.
  4. On 27-0004, `bidder.granite` sees the resubmit banner.
  5. `bidder.ridgeback` acknowledges Addendum 1 and asks a question.
  6. The 27-0004 agency author sees the question without a name.
  7. `admin`/office closes one question.

  Record any defect and fix it in this task.
- [ ] **Step 3:** Run all gates plus `npm run build`. Expected: pass.
- [ ] **Step 4:** Commit `chore: 2c seeds, README and decisions`.
