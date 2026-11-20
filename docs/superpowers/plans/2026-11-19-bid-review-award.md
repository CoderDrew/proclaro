# Bid Review, Bond Cure, Recap and Award (Slice 2b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take a closed solicitation to a posted award. The office reviews each opened bid, a missing bid bond gets its cure period, and the agency decides the flagged bids. The recap is computed in Postgres from the sealed prices, checked by a second person and posted. The agency then picks the award, and the office posts it after a second check. If every accepted bid is over the funding amount, an "all bids rejected" memo is posted instead.

**Architecture:** Same model as slices 1 and 2a.
- Every guarantee lives in Postgres:
  - outcomes and the derived rules;
  - the cure deadline;
  - the same-person rule;
  - the frozen funding amount;
  - every recap and award figure.
- Each transition is a security-definer function: lock → role/org check → stage check → guarded write → one `bid_audit_log` row.
- **The solicitation row stays `published` forever.** It is frozen by `solicitations_published_frozen`, and `app.bids_closed` requires `state = 'published'`. The post-close states therefore live in a new one-row-per-solicitation table, `evaluations`.
- **The recap has a single source of truth in SQL** (`app.rank_recap`, a pure function over JSON). It is not a TypeScript module mirrored in SQL. Why:
  - posting must freeze exactly what the database computed;
  - the anti-goal "a recap or award number that someone typed" is only enforceable if no figure crosses the API boundary inward;
  - a mirror would need a second parity suite for the most intricate rule in v1.

  Because `app.rank_recap` takes plain JSON, its exhaustive tests are literal pgTAP cases with no fixtures. TypeScript only parses and formats the frozen snapshot.
- Posted recaps, memos and awards are append-only snapshot rows that the public can read. Nothing else about bids is ever public.

**Tech Stack:** Unchanged: Next.js 15, React 19, TypeScript, Supabase (Postgres, Auth, Storage; `@supabase/ssr`), Zod 4, date-fns 4 + `@date-fns/tz`, Vitest, pgTAP, `playwright-core` + Chromium.

**Spec:** `docs/superpowers/specs/2026-11-19-bid-review-award-design.md` (approved, binding; its *(my call)* items are binding). Read it before any task. Earlier rulings are in `docs/decisions.md` under "Solicitation setup slice, as built", "Slice 2a, as built" and "Look and feel, as built".

## Global Constraints

- **No real data.** Use the fictional State of Calder only. Never open or copy anything under `source-docs/`.
- **Money:** integer cents (`Cents = number` in TypeScript, `bigint` in SQL), never floats. Every recap and award figure is computed in SQL from the stored `bid_versions` cents and never entered. Evaluated prices are compared as exact integers in hundredths of a cent (see Task 8). Rounding happens only for display.
- **Time:** shown and entered in `settings.timezone` (default `America/Denver`), stored as UTC `timestamptz`. Calendar "today" is `app.today()`.
- **Deadline decisions use the database clock.**
  - Reads judge with `now()`.
  - Writers re-check `clock_timestamp()` after taking their row lock (Ruling 8).
  - "Closed" is still `app.bids_closed` (`now() >= bid_due_at`).
  - The cure deadline is `app.cure_due_at(bid_due_at)`, and there is no override.
- **Sealed bids:** nothing about bids reaches the agency, the public or `service_role` except as follows:
  - the agency sees the flagged-bid view (Task 7: reference, reviewer's note, base total);
  - everyone sees the posted `recaps` and `awards` rows;
  - the bidder sees its own cure status and, after posting, its own outcome.

  Bid audit rows stay in `bid_audit_log` (office only, after close).
- **Non-responsive is only:** `late_upload`, `wrong_form`, `missing_signature` (office), or the two automatic reasons, verbatim:
  - `signed original not received by the bid due time` (2a);
  - `bid bond not received by the cure deadline` (new).

  No function lets anyone change an automatic outcome.
- **Append-only, by trigger (`app.reject_change`, update/delete/truncate) and by revoke:** `audit_log`, `bid_audit_log`, `bid_cure_files`, `bid_outcomes`, `resident_verifications`, `flagged_decisions`, `recaps`, `award_picks`, `awards`. `evaluations` is the only mutable new table, and it has no API write grants.
- **Two-person check:**
  - Posting the recap, the memo and the award needs a different office user.
  - The fallback (`post_*_alone`) is stamped `single_reviewer = true`, and its audit detail carries `'fallback', 'no second reviewer available'`.
  - The same-person rule is enforced in SQL (`same_person`).
- **New SQL only in new migrations, 0014 and up.** Never edit 0001–0013; use `create or replace`, or drop and create, in a new file.
- **pgTAP for every function and policy.** Each new `app.*` helper, `public` function and policy gets at least one assertion.
- **pgTAP count assertions are scoped to the test's own fixtures** (a `where solicitation_id = :'sol'` or similar). Every file must pass against a database that already holds the seed and other data (commit 71070e2).
- **Definer functions:**
  - `security definer`, `set search_path = ''`, fully qualified names;
  - `revoke all … from public, anon, authenticated, service_role`;
  - then `grant execute … to authenticated` only for `public` functions. `app` helpers get no grant unless a policy calls them.
- **Errors** are `raise exception '<code>' using errcode = 'P0001'`.
  - New codes: `snapshot_mismatch`, `cure_closed`, `outcome_locked`, `cure_pending`, `undecided_bids`, `flags_pending`, `resident_unverified`, `recap_stale`, `pick_required`, `not_in_recap`.
  - Reused codes: `not_authorized`, `not_found`, `invalid_state`, `invalid_data`, `invalid_bid`, `reason_required`, `comment_required`, `same_person`, `sealed`.
- **Design system:**
  - No inline `style` attributes.
  - Every control comes from `src/components/ui` (`Button`, `Field`, `Choice`, `MoneyInput`, `Table`, `StatusBadge`, `Notice`, `Card`, `Money`, `DateTime`, `PageHeader`/`Page`).
  - Disabled or read-only controls get the disabled look and `not-allowed`.
  - A status is never conveyed by colour alone: it always has the badge label or the database reason text.
- **Gates for every task:** `npm run lint && npm test && npm run db:reset && npm run db:test`; plus `npm run db:types` after any migration and `npm run build` for UI tasks.

## Review Focus

1. **The cure deadline lands at exactly 17:00 local on the next business day, across a weekend and a holiday.**
   - Pinned in Task 3: `app.cure_due_at` for a Wednesday, a Friday, a Thursday before a Friday holiday, and a Friday 23:30 close. Each expected value is a literal `timestamptz`.
   - At `p_now = due - 1 second` the status is `pending`; at `p_now = due` it is `failed`.
   - `submit_cure_bond` raises `cure_closed` when the database clock is past the deadline.
2. **Resident 5% boundary.** A verified resident at exactly 105% of the lowest non-resident evaluated price ranks first. One cent more, and the non-resident ranks first. An unverified resident never gets the preference. Pinned in Task 8.
3. **Apprentice credit applies only on $1M+ jobs (estimate `>= 100_000_000`) and only with the commitment.**
   - The same prices rank differently at estimates 100,000,000 and 99,999,999, and with the commitment true and false.
   - An exact evaluated tie (credited 100,000,000 against uncredited 99,000,000) is marked tied with no expected winner.

   Pinned in Task 8, with the commitment's parity in Task 2.
4. **Alternates are selected against the funding amount at its boundary.**
   - With funding 110,000,000, alternate 1 is taken when the lowest evaluated bid's running total equals exactly 110,000,000, and alternate 2 (one cent more) is not.
   - With funding 109,999,999, no alternate is taken.

   Pinned in Task 8.
5. **The same person cannot both prepare and check.**
   - The office user who set outcomes or sent the recap to check gets `same_person` from `post_recap` and `disagree_recap`.
   - The user who sent the award to check gets `same_person` from `post_award` and `disagree_award`.
   - The fallback is recorded.

   Pinned in Tasks 9 and 10.
6. **"All bids rejected" when every accepted base total exceeds funding.**
   - Bases 100,000,000 and 100,000,001 with funding 99,999,999 give `kind = 'all_rejected'`, `reason = 'over_funding'`, and no rows.
   - Funding 100,000,000 gives a recap.
   - Zero accepted bids give `reason = 'no_accepted_bids'`.
   - Posting the memo ends the evaluation at `all_rejected`.

   Pinned in Tasks 8 and 9.

---

## Names decided here (spec "Left to the builder")

- **Stages** (`public.evaluation_stage`): `bid_review`, `recap_check`, `recap_posted`, `award_check`, `awarded`, `all_rejected`.
  - The spec's "awaiting agency" is displayed, not stored: `bid_review` with `flags_released_at` set and a bid still `flagged`.
  - Its "award pending" is `recap_posted`.

  This keeps the office able to change outcomes until send-to-check (spec §1) without a back-transition from the agency's state.
- **Review statuses** (text, from `app.bid_review_status`), in precedence order:
  1. `non_responsive` (signed original, then cure failed);
  2. `pending_cure`;
  3. `undecided` (no outcome row);
  4. `non_responsive` (office ground);
  5. `accepted`;
  6. `flagged`;
  7. `flag_accepted`;
  8. `flag_rejected`.

  The recap takes `accepted` and `flag_accepted`.
- **Outcomes are append-only rows.** The latest row per bid is current, so every change is its own audited row. An agency decision belongs to one outcome row (`flagged_decisions.outcome_id`). If the office changes the outcome, the old decision no longer applies.
- **Cure rule.** A cure is due when bonds are required (`app.bonds_required`) and one of these holds:
  - the choice is `electronic` with no `bid_bond` row in `bid_version_files`;
  - the choice is `paper` and `app.bond_original_received(bid, version, bid_due_at)` is false.

  The bid is `cured` by either of these:
  - a `bid_cure_files` row for that version with `uploaded_at < cure_due` (the upload is refused at or after the deadline);
  - a counted `bid_bond` entry in `bid_original_log` for that version with `received_at <= cure_due` and `logged_at <= cure_due`, the same `<=` rule as 2a originals.

  The paper bond is logged through the existing `log_bid_original`, which already allows logging after close.
- **Cure deadline:** take the local date of `bid_due_at`. Step forward one day at a time until the date is neither a Saturday or Sunday nor a row in `public.holidays`. Return that date at 17:00 in `settings.timezone`. It is computed live from the holiday table. Holidays edited after close move the deadline; this is recorded as a known gap.
- **Agency's flagged view:** the reference, the reviewer's note, that bid's base total and the current decision. It does not show the bidder's name *(builder's call: minimal disclosure; the decision does not need it)*.
- **The bidder sees its outcome only after the recap or memo is posted** *(builder's call: outcomes can change until send-to-check)*. The cure status is shown live from close.
- **Disagreement** (`disagree_recap` / `disagree_award`) takes a comment, returns the item to `bid_review` / `recap_posted`, and is read back from `bid_audit_log`.
- **Recap snapshot JSON** (the contract between `app.rank_recap`/`app.build_recap` and `src/domain/recap/snapshot.ts`), camelCase keys:
  ```
  { kind: "recap" | "all_rejected", reason: null | "over_funding" | "no_accepted_bids",
    solicitationNumber: string, fundingCents: int, fundingFromEstimate: bool,
    alternates: [{ kind: "additive" | "deductive", description: string }],
    selectedAlternates: int[],           // 1-based, ascending; [] for all_rejected
    rows: [{ bidId, reference, bidderName, baseCents, alternateCents: int[], totalCents, evaluatedCents,
             resident: bool, apprenticeCredit: bool, residentPreferred: bool, rank: int, tied: bool }],
    expectedWinnerBidId: uuid | null, winnerOverFunding: bool }
  ```
  For `all_rejected`, `rows` is `[]`: the memo discloses no bid.
- **Award snapshot JSON:** `{ bidId, reference, bidderName, amountCents, selectedAlternates, alternates, expectedWinnerBidId, differsFromExpected }`. The pick reason stays in `award_picks`, which is not public.

## File Structure

```
supabase/migrations/0014_funding_amount.sql       required key, app.funding_cents, publish_solicitation snapshot check
supabase/migrations/0015_apprentice_commitment.sql draft/version column, bid_draft_problems, submit_bid, clause v2
supabase/migrations/0016_bond_cure.sql            cure deadline, cure status, bid_cure_files, cure upload, storage policy helpers
supabase/migrations/0017_review_outcomes.sql      evaluations, bid_outcomes, flagged_decisions (table), status, set_bid_outcome, review_bids
supabase/migrations/0018_resident_verification.sql resident_verifications, verify_resident, resident_claims
supabase/migrations/0019_flagged_decisions.sql    send_flags_to_agency, agency_flagged_bids, decide_flagged_bid
supabase/migrations/0020_recap_compute.sql        app.rank_recap, app.build_recap, app.recap_blockers, preview_recap
supabase/migrations/0021_recap_workflow.sql       recaps, send/disagree/post/post-alone, same-person helper
supabase/migrations/0022_award.sql                award_picks, awards, pick/send/disagree/post/post-alone
supabase/migrations/0023_bid_outcome_view.sql     my_bid_outcome (the bidder's outcome after posting)
supabase/tests/{funding,apprentice,cure,review_outcomes,resident,flagged,recap_compute,recap_workflow,award,bid_outcome}.test.sql
src/domain/recap/snapshot.ts (+ .test.ts)         Zod parse of the frozen recap/memo/award snapshots, display rows
src/app/office/solicitations/[id]/review/         page, ReviewTable, RecapPanel, AwardPanel, actions, logic
src/app/agency/solicitations/[id]/bids/           page, FlaggedPanel, AwardPickPanel, actions, logic
src/app/bidder/solicitations/[id]/{CurePanel,OutcomePanel}.tsx
src/components/RecapTable.tsx                      shared by office, agency and public pages
```

---

### Task 1: Funding amount: setup field, validation, frozen in the snapshot, seed fallback

**Files:**
- Create: `supabase/migrations/0014_funding_amount.sql`, `supabase/tests/funding.test.sql`
- Modify:
  - `src/domain/solicitation/{types,schema,validate}.ts` (+ `validate.test.ts`, `requiredKeys.test.ts`)
  - `src/components/SolicitationFields.tsx`, `src/components/fieldComments.ts`
  - `supabase/tests/00_helpers.sql` (`tests.solicitation_data` gains `'fundingAmountCents', 15000000`)
  - `supabase/tests/final_review.test.sql` (its two passing publishes send `jsonb_build_object('data', data)` instead of `'{"k":1}'`)
  - `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: `app.required_data_keys()`, `public.publish_solicitation(uuid, text, text, jsonb, timestamptz)` (0006 body), `MoneyInput`.
- Produces:
  - `SolicitationData.fundingAmountCents: Cents | null`. In the schema: `z.number().int().nonnegative().nullable()`. `emptySolicitation()` gives `null`.
  - `IssueCode` gains `"funding_below_estimate"`, a warning (added to `WARNING_CODES`). The required rule gains `need("fundingAmountCents", d.fundingAmountCents)`.
  - `0014` contents:
    - `create or replace function app.required_data_keys()` with the 0006 list plus `'fundingAmountCents'`, inside the same `required-data-keys:start/end` markers. `requiredKeys.test.ts` reads `0014_funding_amount.sql`.
    - `app.funding_cents(p_snapshot jsonb) returns bigint`, immutable: `coalesce(data.fundingAmountCents, data.estimateCents)`.
    - `app.funding_from_estimate(p_snapshot jsonb) returns boolean`: true when `data.fundingAmountCents` is absent or null.
    - `create or replace function public.publish_solicitation(...)`: the 0006 body plus two checks, made right after the `invalid_paths` check:
      1. `v_row.data->>'fundingAmountCents'` must be a non-negative integer, else `invalid_data`;
      2. `p_snapshot->'data'->'fundingAmountCents'` must equal `v_row.data->'fundingAmountCents'`, else `snapshot_mismatch`.

      The audit detail adds `'funding_cents'`.

- [ ] **Step 1: Write failing tests.**
  - `validate.test.ts`:
    - `fundingAmountCents: null` gives the error `{ code: "required", field: "fundingAmountCents" }`;
    - estimate `15_000_000` with funding `14_999_999` gives the warning `funding_below_estimate`, message "Funding amount is below the estimate.";
    - funding `15_000_000` gives no warning.
  - `requiredKeys.test.ts` passes against 0014 (currently fails: key missing).
  - `funding.test.sql`:
    - `app.funding_cents('{"data":{"estimateCents":15000000,"fundingAmountCents":16000000}}')` is `16000000`;
    - with no `fundingAmountCents` it is `15000000`, and `app.funding_from_estimate` is true;
    - an approved solicitation (driven there with the slice 1 functions, as `final_review.test.sql` does) whose data has funding 16,000,000:
      - publishing with snapshot data funding `16000001` raises `snapshot_mismatch`;
      - with funding `null` in the row it raises `invalid_data`;
      - with a matching snapshot it succeeds, and `published_snapshot->'data'->>'fundingAmountCents'` is `16000000`;
    - a later attempt to `update` the published row raises (frozen).
- [ ] **Step 2:** Run `npm test -- validate requiredKeys` and `npm run db:reset && npm run db:test`; expect failures.
- [ ] **Step 3:** Implement the migration, schema, validation, and a "Funding amount" `MoneyInput` directly under "Estimated cost" (hint: "The most the agency can spend. Frozen when the solicitation is published.") with field comments. Update the two `final_review.test.sql` snapshots.
- [ ] **Step 4:** Run the gates and `npm run db:types`; expect all green.
- [ ] **Step 5:** Commit: `feat: funding amount on solicitations, frozen at publish`.

---

### Task 2: Apprentice commitment on the bid

**Files:**
- Create: `supabase/migrations/0015_apprentice_commitment.sql`, `supabase/tests/apprentice.test.sql`
- Modify:
  - `src/domain/bid/{types,validate,parityFixtures}.ts` (+ `validate.test.ts`)
  - `supabase/tests/bid_parity.test.sql` (regenerated)
  - `src/documents/{bidFill.ts,templates/BidFormSections.tsx}` and the render snapshot
  - `src/app/bidder/solicitations/[id]/{actions,logic,logic.test,BidDraftForm,page}.ts(x)`
  - `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: `app.bid_draft_problems` (0010 body), `public.submit_bid` (0010 body), `APPRENTICE_CREDIT_AT = 100_000_000`.
- Produces:
  - `bid_drafts.apprentice_commitment boolean null` and `bid_versions.apprentice_commitment boolean null`, with `grant update (apprentice_commitment) on public.bid_drafts to authenticated`. The existing update policy covers it.
  - `app.apprentice_required(p_snapshot jsonb) returns boolean`: `estimateCents >= 100000000`.
  - `create or replace app.bid_draft_problems`: the 0010 body, then after the bond codes:
    - `apprentice_missing` (required and null);
    - `apprentice_not_required` (not required and not null).
  - `create or replace public.submit_bid`: the 0010 body, copying `apprentice_commitment` into `bid_versions`.
  - TypeScript:
    - `BidDraft.apprenticeCommitment: boolean | null`;
    - `BidIssueCode` gains `"apprentice_missing" | "apprentice_not_required"`, in that order after the bond issues. `field: "apprentice"`. Messages: "Answer the apprentice commitment question." and "This solicitation does not ask for an apprentice commitment.";
    - `ParityCase.draft.apprenticeCommitment: boolean | null` (default `null` in `full`), and `renderParitySql` inserts it.
  - `BidFill.apprenticeCommitment: boolean | null`.
  - Bid form: the `data-apprentice-question` paragraph is replaced by `<p data-apprentice-line>` (still only when `req.apprenticeCredit`):
    - blank form: `The bidder commits apprentices to at least 10% of the labor hours on this project: Yes {blank} No {blank}`;
    - filled: `…on this project: Yes` or `No`.
  - Clause `apprentice_credit` version 2, inserted by 0015, body exactly:
    ```
    # Apprenticeship Program Credit

    Because of the size of this project, the bid form asks whether the bidder commits apprentices to at least ten percent of the labor hours on this project. A bid that makes this commitment is evaluated as if its price were one percent lower. The credit is used only to compare bids; the contract amount is the price bid.

    A bidder that commits must be able to show, on request, that apprentices from an approved program will work those hours. Answering no does not make a bid ineligible.
    ```
    Version 1 told bidders participation only breaks ties, which contradicts the 1% rule.
  - `setApprenticeCommitment(bidId: string, value: boolean | null): Promise<BidActionResult>`, via `runSetApprenticeCommitment(bidId, value, deps)` in `logic.ts`.
  - `BidDraftForm` shows a `Choice` group "Apprentice commitment" (Yes/No) when `deriveRequirements(...).apprenticeCredit`, disabled when `readOnly`.

- [ ] **Step 1: Write failing tests.**
  - New parity cases:
    - "apprentice answer missing at $1,000,000.00": estimate `100_000_000`, null → `["apprentice_missing"]`;
    - "apprentice answered below $1,000,000.00": `99_999_999`, `true` → `["apprentice_not_required"]`;
    - "apprentice answered no at $1,000,000.00": `false` → `[]`.
  - The coverage test lists both new codes.
  - `apprentice.test.sql`:
    - with a $1M solicitation, `submit_bid` raises `invalid_bid` with detail containing `apprentice_missing`;
    - after `update bid_drafts set apprentice_commitment = true` as the bidder, submit succeeds and the version row stores `true`;
    - as the bidder, `update bid_drafts set apprentice_commitment = true` after `tests.set_bid_due(sol, now())` changes 0 rows.
  - The render snapshot test: the filled form prints "on this project: Yes"; the blank $1M form prints "Yes ____ No ____"; a $150,000 form has no `data-apprentice-line`.
  - `logic.test.ts`: `runSetApprenticeCommitment` rejects a non-uuid bid id and passes `{ apprentice_commitment: true }` to the deps update.
- [ ] **Step 2:** Run `npm test -- parity validate renderHtml logic`; expect FAIL. Implement; regenerate with `UPDATE_PARITY_SQL=1 npm test -- parity`.
- [ ] **Step 3:** Run the gates, `npm run db:types` and `npm run build`; expect all green.
- [ ] **Step 4:** Commit: `feat: sealed apprentice commitment on $1M+ bids`.

---

### Task 3: Bid-bond cure: deadline, status, bond-only upload, automatic disqualification

**Files:**
- Create: `supabase/migrations/0016_bond_cure.sql`, `supabase/tests/cure.test.sql`
- Create: `src/app/bidder/solicitations/[id]/CurePanel.tsx`
- Modify:
  - `supabase/tests/00_helpers.sql`
  - `src/app/bidder/solicitations/[id]/{actions,logic,logic.test,page}.ts(x)`
  - `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes:
  - from 2a: `app.bonds_required`, `app.bond_original_received(uuid,int,timestamptz)`, `app.latest_version`, `app.is_withdrawn`, `app.lock_bid`, `app.require_bidder`, `app.bid_audit`, `app.path_bid_id`, `app.bids_closed`;
  - the `public.holidays (day date)` table and `settings.timezone`.
- Produces:
  - `app.cure_due_at(p_bid_due_at timestamptz) returns timestamptz` (stable; algorithm under "Names decided here").
  - `app.bond_cure(p_bid_id uuid, p_now timestamptz default now()) returns table (status text, due_at timestamptz)`.
    - `status` is one of `not_required`, `ok`, `cured`, `pending` or `failed`.
    - It reads the latest non-withdrawn version.
    - `due_at` is null for `not_required` and `ok`.
    - `failed` means `p_now >= due_at` and not cured.
    - `p_now` exists so tests can stand at the boundary. Every caller passes `now()`.
  - Table `public.bid_cure_files`:
    - `id uuid pk`, `bid_id`, `version int`;
    - `path text unique not null`, `file_name text not null`;
    - `object_id uuid`, `object_size bigint`, `object_etag text`;
    - `uploaded_by`, `uploaded_at timestamptz not null`;
    - FK `(bid_id, version)` → `bid_versions`;
    - append-only, no API privileges.
  - `create or replace app.can_upload_bid_file(text)`: the 0009 rule, or the caller's own bid with `(app.bond_cure(b.id)).status = 'pending'`.
  - `create or replace app.can_read_bid_file(text)`: the 0009 rule, or office staff after close for a path in `bid_cure_files`.
  - `public.submit_cure_bond(p_bid_id uuid, p_path text, p_file_name text) returns timestamptz`. Order:
    1. `require_bidder`;
    2. `lock_bid` (`not_found`);
    3. not closed → `invalid_state`;
    4. status not `pending` → `invalid_state`;
    5. `clock_timestamp() >= due_at` → `cure_closed` (Ruling 8, after the lock);
    6. the path is not under `bids/{bid}/` → `invalid_data`;
    7. no storage object with a numeric size and an eTag → `invalid_bid` (detail `file_missing`).

    It inserts the row with `uploaded_at = clock_timestamp()` and audits `submit_cure_bond` with `{version, path}`. It returns `uploaded_at`.
  - `public.my_bid_cure(p_bid_id uuid) returns table (status text, due_at timestamptz)`. Own bid only (`not_found` otherwise). Before close it returns `not_required` with a null `due_at`, so nothing leaks.
  - Test helper `tests.make_closed_bid(p_sol uuid, p_bidder uuid, p_items bigint[], p_alts bigint[] default '{}', p_choice public.bid_bond_choice default null, p_apprentice boolean default null, p_signed_original boolean default true, p_bond_original boolean default false) returns uuid`.
    - It inserts `bids` and `bid_versions` v1 (`submitted_at = bid_due_at - 2 hours`, legal name from the org), and for `electronic` a storage object plus a `bid_bond` `bid_version_files` row.
    - It adds `bid_original_log` rows (`signed_form`, and `bid_bond` when asked) with `received_at = logged_at = bid_due_at - 1 hour`, `logged_by = p_bidder` (a fixture shortcut, commented).
    - Call it after the solicitation's due time is set.
  - Bidder UI:
    - `createCureUploadUrl(bidId: string, fileName: string): Promise<BidActionResult<{ path: string; token: string }>>` and `submitCureBond(bidId: string, path: string, fileName: string): Promise<BidActionResult<{ uploadedAt: string }>>`;
    - `cureMessageFor` maps `cure_closed` → "The cure deadline has passed." and `invalid_state` → "This bid has no bond to cure.";
    - `CurePanel` shows the status text and the due time in local time. When pending, it shows one file input and a primary "Upload bid bond" `Button`.
    - Copy:
      - pending: "Your bid bond was not received. Upload it by {due} or the bid will be disqualified.";
      - cured: "Bid bond received during the cure period.";
      - failed: "Bid bond not received by the cure deadline. The bid is non-responsive.".

- [ ] **Step 1: Write failing tests** in `cure.test.sql`. Insert into `public.holidays` inside the test; the transaction rolls back.
  - **Review Focus 1, `app.cure_due_at` with the `America/Denver` setting:**
    - `'2026-12-02 13:00 America/Denver'` (Wed) → `'2026-12-03 17:00 America/Denver'`;
    - `'2026-12-04 13:00 America/Denver'` (Fri) → `'2026-12-07 17:00 America/Denver'`;
    - with holiday `2026-12-25`, `'2026-12-24 13:00 America/Denver'` (Thu) → `'2026-12-28 17:00 America/Denver'` (skips Fri holiday, Sat, Sun);
    - `'2026-12-04 23:30 America/Denver'` → `'2026-12-07 17:00 America/Denver'`.
  - `app.bond_cure`, with the solicitation due `now() - interval '1 hour'` and bids made by `tests.make_closed_bid`:
    - estimate 14,999,999 → `not_required`;
    - paper with bond original → `ok`;
    - paper without → `pending`, with `due_at = app.cure_due_at(bid_due_at)`;
    - same bid, `p_now => due_at - interval '1 second'` → `pending`; `p_now => due_at` → `failed`;
    - a `bid_bond` log entry with `received_at = logged_at = due_at` → `cured` at `p_now => due_at + interval '1 day'`;
    - the same entry voided → `failed` at that `p_now`;
    - a withdrawn bid is ignored (its latest version is withdrawn).
  - `submit_cure_bond`:
    - the owner with a seeded object → returns a timestamp, status `cured`, 1 audit row;
    - a second call → `invalid_state`;
    - another bidder → `not_found`;
    - a bid with status `ok` → `invalid_state`;
    - a solicitation whose bid due is `now() - interval '10 days'` (cure due long past) → `cure_closed`;
    - a path under another bid → `invalid_data`;
    - a path with no object → `invalid_bid`.
  - Storage:
    - the pending owner can insert `bids/{bid}/{uuid}/bond.pdf` after close;
    - the owner of an `ok` bid cannot;
    - the office reads the cure file after close (1 row);
    - an agency author reads 0 rows.
  - `my_bid_cure`:
    - another bidder → `not_found`;
    - before close → `('not_required', null)`.
  - `update`/`delete` on `bid_cure_files` raise for every role.
- [ ] **Step 2:** Run `npm run db:reset && npm run db:test`; expect failures. Implement 0016.
- [ ] **Step 3:** Write the failing `logic.test.ts` cases for `cureMessageFor` and the path check (reuse `assertOwnBidPath`). Implement the actions and `CurePanel`. On the bidder page, show it when `bidding_state` is `closed` and the bid has a submitted version.
- [ ] **Step 4:** Run the gates, `npm run db:types` and `npm run build`; expect all green.
- [ ] **Step 5:** Commit: `feat: bid-bond cure period with automatic disqualification`.

---

### Task 4: Review outcomes: evaluation state, outcome rows, derived statuses

**Files:**
- Create: `supabase/migrations/0017_review_outcomes.sql`, `supabase/tests/review_outcomes.test.sql`
- Modify: `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: Task 3 (`app.bond_cure`); `app.original_received`, `public.opened_bids` (0012); `app.require_office`; `app.is_agency`, `app.my_org`.
- Produces:
  - Enums:
    - `public.evaluation_stage` (see Names);
    - `public.bid_outcome` (`accepted`, `accepted_flagged`, `non_responsive`);
    - `public.non_responsive_ground` (`late_upload`, `wrong_form`, `missing_signature`);
    - `public.flag_decision` (`accept`, `reject`).
  - `public.evaluations`:
    - `solicitation_id uuid pk references solicitations`;
    - `stage evaluation_stage not null default 'bid_review'`;
    - `flags_released_at timestamptz`;
    - `recap_preparer_id uuid`, `recap_draft jsonb`, `award_preparer_id uuid`;
    - `updated_at`.

    `grant select to authenticated` with policy `evaluations_read`: office, or `app.is_agency()` and `my_org()` = the solicitation's `agency_id`. No write grants.
  - `public.bid_outcomes`:
    - `id uuid pk`, `solicitation_id`, `bid_id`, `version int` (FK to `bid_versions`);
    - `outcome`, `ground null`;
    - `note text not null check (btrim(note) <> '')`;
    - `set_by`, `set_at default now()`;
    - check `(outcome = 'non_responsive') = (ground is not null)`.

    Append-only, no API privileges.
  - `public.flagged_decisions`:
    - `id uuid pk`, `solicitation_id`, `bid_id`, `outcome_id references bid_outcomes`;
    - `decision`, `reason text not null` (non-blank);
    - `decided_by`, `decided_at default now()`.

    Append-only, no API privileges. Written in Task 7.
  - `app.lock_evaluation(p_solicitation_id uuid) returns public.evaluations`: `sealed` unless `app.bids_closed`; insert on conflict do nothing; `select … for update`.
  - `app.require_stage(p_eval public.evaluations, p_stage public.evaluation_stage)`: raises `invalid_state`.
  - `app.current_outcome(p_bid_id uuid) returns public.bid_outcomes`: the latest by `set_at, id`, or null.
  - `app.bid_review_status(p_bid_id uuid, p_now timestamptz default now()) returns table (status text, reason text)`. Precedence as in Names. Reasons:
    - the two verbatim automatic reasons;
    - the ground label (`late upload`, `wrong form`, `missing signature`) for office non-responsive;
    - the outcome note for `flagged`;
    - the decision reason for `flag_*`.
  - `public.set_bid_outcome(p_bid_id uuid, p_outcome public.bid_outcome, p_ground public.non_responsive_ground, p_note text) returns uuid`. Order:
    1. `require_office`;
    2. the bid exists → else `not_found`;
    3. `lock_evaluation` on its solicitation (`sealed` before close);
    4. it has an opened version (latest, not withdrawn) → else `not_found`; stage `bid_review`;
    5. an automatic non-responsive status → `outcome_locked`;
    6. blank note → `reason_required`;
    7. ground/outcome mismatch → `invalid_data`.

    It inserts and audits `set_bid_outcome` with `{outcome_id, version, outcome, ground, note, previous_outcome_id}`.
  - `public.review_bids(p_solicitation_id uuid) returns table`:
    - columns: `bid_id uuid, reference text, version int, bidder_name text, bidder_org_id uuid, base_total_cents bigint, alternate_cents bigint[], apprentice_commitment boolean, cure_status text, cure_due_at timestamptz, outcome_id uuid, outcome public.bid_outcome, ground public.non_responsive_ground, note text, status text, status_reason text`;
    - built on `public.opened_bids`, so the 2a gates and the close-determination audit are inherited;
    - office only;
    - it writes one `bid_cure_determination` audit row per bid when the cure status first becomes `failed` (and again only if it changes), using the 0012 pattern and lock.

- [ ] **Step 1: Write failing tests** in `review_outcomes.test.sql`:
  - Fixture: solicitation due `now() - interval '1 hour'`; bids A (all fine), B (no signed original), C (paper bond, no bond original, pending cure).
  - Before close (a second solicitation due `now() + 1 hour`), `set_bid_outcome` raises `sealed`.
  - As office:
    - A `accepted` → uuid, `app.bid_review_status(A)` = `accepted`;
    - A changed to `accepted_flagged` with note "Mailed form total differs from portal entry" → status `flagged` with that reason;
    - 2 audit rows for A.
  - B: any outcome raises `outcome_locked`. The status is `non_responsive` with `signed original not received by the bid due time`.
  - C: status `pending_cure` even after an `accepted` row. With `p_now => cure due` the status is `non_responsive` with `bid bond not received by the cure deadline`, and `set_bid_outcome(C, …)` evaluated after a `tests.set_bid_due` that puts the cure deadline in the past raises `outcome_locked`.
  - `non_responsive` with a null ground → `invalid_data`; `accepted` with a ground → `invalid_data`; a blank note → `reason_required`; a bidder or agency caller → `not_authorized`.
  - Once `evaluations.stage` is set to `recap_check` (direct update as the test superuser), `set_bid_outcome` → `invalid_state`.
  - `review_bids` as office returns 3 rows for this solicitation with the statuses above; as an agency author it raises `not_authorized`.
  - `evaluations`: the office reads the row; the owning agency's author reads it; another agency's author and a bidder read 0 rows; anon throws 42501.
  - `update`/`delete` on `bid_outcomes` and `flagged_decisions` raise for every role.
  - `app.lock_evaluation` on an open solicitation → `sealed`; on a closed one it creates exactly one `evaluations` row (a second call adds none).
- [ ] **Step 2:** Run the database gates; expect failures. Implement 0017.
- [ ] **Step 3:** Run the gates and `npm run db:types`; expect PASS.
- [ ] **Step 4:** Commit: `feat(db): bid review outcomes with derived non-responsive rules`.

---

### Task 5: Resident verification

**Files:**
- Create: `supabase/migrations/0018_resident_verification.sql`, `supabase/tests/resident.test.sql`
- Modify: `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: Task 4 (`app.lock_evaluation`, `app.require_stage`), `public.bidder_companies (resident_claimed, resident_certificate)`.
- Produces:
  - `public.resident_verifications`:
    - `id uuid pk`, `solicitation_id`, `bid_id`;
    - `certificate text not null` (copied at verification);
    - `verified boolean not null`, `note text not null` (non-blank);
    - `verified_by`, `verified_at default now()`.

    Append-only, no API privileges.
  - `app.resident_verified(p_bid_id uuid) returns boolean`: the latest row's `verified`, or false.
  - `app.resident_unverified(p_bid_id uuid) returns boolean`: the bidder claims residency and no row exists.
  - `public.verify_resident(p_bid_id uuid, p_verified boolean, p_note text) returns uuid`. Order:
    1. `require_office`;
    2. opened bid → else `not_found`;
    3. `lock_evaluation` and stage `bid_review`;
    4. no claim → `invalid_state`;
    5. null `p_verified` → `invalid_data`;
    6. blank note → `reason_required`.

    Audit `verify_resident` with `{verified, certificate, note}`.
  - `public.resident_claims(p_solicitation_id uuid) returns table (bid_id uuid, reference text, certificate text, verified boolean, note text, verified_at timestamptz)`. Office only, after close. One row per opened bid whose bidder claims residency; `verified` is null when there is no row.

- [ ] **Step 1: Write failing tests:**
  - A claimant bid (bidder made with `register_bidder(..., true, 'CR-0042')`) and a non-claimant.
  - `verify_resident(claimant, true, 'Certificate checked against the registry')` → uuid, `app.resident_verified` = true.
  - A later `false` row → false, and `resident_claims` shows `verified = false` with the new note.
  - On the non-claimant → `invalid_state`; a blank note → `reason_required`; a bidder → `not_authorized`.
  - In stage `recap_check` → `invalid_state`.
  - `resident_claims` returns 1 row for the fixture solicitation.
  - The certificate stored is `CR-0042`.
  - Append-only checks.
- [ ] **Step 2:** Run the database gates; expect failures. Implement. Re-run; expect PASS, then run `npm run db:types`.
- [ ] **Step 3:** Commit: `feat(db): office verification of resident certificates`.

---

### Task 6: Office review screen

**Files:**
- Create: `src/app/office/solicitations/[id]/review/{page.tsx,ReviewTable.tsx,actions.ts,logic.ts,logic.test.ts}`
- Modify:
  - `src/components/ui/status.ts` (+ `status.test.ts`)
  - `src/app/office/solicitations/[id]/bids/page.tsx` (a "Review bids" `ButtonLink` after close)

**Interfaces:**
- Consumes: `review_bids`, `resident_claims`, `set_bid_outcome`, `verify_resident`, the `evaluations` select, `log_bid_original` (an existing panel on the bids page logs paper bonds during the cure), `requireOfficePage`/`requireOfficeAction`.
- Produces:
  - `DomainStatus` gains:
    - `{ kind: "evaluation"; stage: string; awaitingAgency: boolean }`. Labels:
      - `bid_review`: "Bid review" (warning), or "Awaiting agency" (warning) when `awaitingAgency`;
      - `recap_check`: "Recap in check" (warning);
      - `recap_posted`: "Award pending" (warning);
      - `award_check`: "Award in check" (warning);
      - `awarded`: "Awarded" (success);
      - `all_rejected`: "All bids rejected" (danger).
    - `{ kind: "review"; status: string }`. Labels:
      - `accepted`: "Accepted" (success);
      - `flagged`: "Flagged for agency" (warning);
      - `flag_accepted`: "Accepted by agency" (success);
      - `flag_rejected`: "Rejected by agency" (danger);
      - `non_responsive`: "Non-responsive" (danger);
      - `pending_cure`: "Pending cure" (warning);
      - `undecided`: "Not reviewed" (neutral).
  - `GROUND_LABELS: Record<NonResponsiveGround, string>` = late upload / wrong form / missing signature, in `logic.ts`.
  - `parseOutcomeForm(form: Record<string, unknown>): { ok: true; value: { bidId: string; outcome: BidOutcome; ground: NonResponsiveGround | null; note: string } } | { ok: false; message: string }`. Messages:
    - "Choose an outcome.";
    - "Choose the non-responsive reason.";
    - "Enter a reason or note.".
  - `reviewMessageFor(e: unknown): string` maps every new error code to plain copy:
    - `outcome_locked` → "This outcome is set automatically and cannot be changed.";
    - `invalid_state` → "Outcomes can no longer be changed at this stage.";
    - `same_person` → "You prepared this, so a different person must check it.";
    - and so on for the rest.
  - `setOutcome(prev, formData)` and `verifyResident(prev, formData)` server actions.
  - The page:
    - stage badge;
    - one row per bid (reference, bidder, base total, apprentice yes/no/—, status badge followed by the reason text, cure due as `DateTime`);
    - an outcome form per bid (`Choice` ×3, a ground `select` in a `Field`, note `textarea`). For automatic statuses and any stage other than `bid_review` it is disabled with the disabled look;
    - a resident section with a verify form per claim.

- [ ] **Step 1: Write failing tests:**
  - `status.test.ts`: each new label and tone; `awaitingAgency: true` gives "Awaiting agency"; an unknown stage gives its readable raw value.
  - `logic.test.ts`:
    - `parseOutcomeForm({ bidId: <uuid>, outcome: "non_responsive", ground: "", note: "x" })` gives "Choose the non-responsive reason.";
    - `accepted` with ground `"wrong_form"` passes with `ground: null`;
    - a blank note fails;
    - `reviewMessageFor({ message: "outcome_locked" })` returns its copy.
- [ ] **Step 2:** Run `npm test -- status logic`; expect FAIL. Implement; expect PASS.
- [ ] **Step 3:** Build the page and run `npm run lint && npm run build`. Verify manually after Task 12's seed exists, or with a test solicitation: outcomes save, a locked row shows the disabled look, and keyboard focus is visible.
- [ ] **Step 4:** Commit: `feat(app): office bid review screen`.

---

### Task 7: Flagged-bid decisions by the agency

**Files:**
- Create:
  - `supabase/migrations/0019_flagged_decisions.sql`, `supabase/tests/flagged.test.sql`
  - `src/app/agency/solicitations/[id]/bids/{page.tsx,FlaggedPanel.tsx,actions.ts,logic.ts,logic.test.ts}`
- Modify:
  - `src/app/agency/solicitations/[id]/page.tsx` (a "Bids and award" link once the row is published and closed)
  - `src/app/office/solicitations/[id]/review/{page.tsx,actions.ts}` (a "Send flagged bids to the agency" button)
  - `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: Task 4 (`flagged_decisions`, `app.bid_review_status`, `app.current_outcome`, `app.lock_evaluation`).
- Produces:
  - `app.require_solicitation_agency(p_solicitation_id uuid)`: `not_authorized` unless `app.is_agency()` and `my_org()` = `agency_id`.
  - `public.send_flags_to_agency(p_solicitation_id uuid) returns void`.
    - Office; stage `bid_review`.
    - Any `pending_cure` → `cure_pending`; any `undecided` → `undecided_bids`; no `flagged` bid → `invalid_state`.
    - Sets `flags_released_at = now()` (idempotent: a second call keeps the first time) and audits `send_flags_to_agency` with `{flagged_count}`.
  - `public.agency_flagged_bids(p_solicitation_id uuid) returns table (outcome_id uuid, reference text, note text, base_total_cents bigint, decision public.flag_decision, decision_reason text, decided_at timestamptz)`.
    - Owning agency only.
    - It returns nothing until `flags_released_at` is set.
    - Then it returns every bid whose current outcome is `accepted_flagged`, and the decision for that outcome row if one exists.
    - No bidder name, items or alternates.
  - `public.decide_flagged_bid(p_outcome_id uuid, p_decision public.flag_decision, p_reason text) returns uuid`. Order:
    1. the owning agency (`not_authorized`);
    2. the outcome exists and is the bid's current outcome, of kind `accepted_flagged` → else `invalid_state`;
    3. `lock_evaluation`, stage `bid_review`, flags released → else `invalid_state`;
    4. blank reason → `reason_required`.

    It inserts a row (the latest counts, so a decision can be revised until send-to-check) and audits `decide_flagged_bid` with `{outcome_id, decision, reason}`.
  - Agency UI: `FlaggedPanel` lists each flagged bid with the note, a `Money` base total, accept/reject `Choice` and a reason, and the current decision badge. `decideFlagged(prev, formData)` action. `flaggedMessageFor(e)`.

- [ ] **Step 1: Write failing tests** in `flagged.test.sql`. Fixture: A flagged, B accepted, C non-responsive.
  - Before release, the agency gets 0 rows from `agency_flagged_bids`, and `decide_flagged_bid` → `invalid_state`.
  - `send_flags_to_agency` with an undecided bid present → `undecided_bids`. After all are set it succeeds.
  - The agency author gets exactly 1 row: A's reference, note and base total. The result has no column carrying B's or C's data, and no `bidder_name`.
  - Another agency's author → `not_authorized`. A bidder → `not_authorized`.
  - `decide_flagged_bid(A_outcome, 'reject', 'Missing addendum acknowledgment is material')` → A's status is `flag_rejected` with that reason. A second decision `accept` → `flag_accepted`.
  - The office changes A's outcome to `accepted_flagged` again (a new row) → status `flagged`: the old decision no longer applies. A decision on the old outcome id → `invalid_state`.
  - A blank reason → `reason_required`.
  - Audit rows exist and are visible to the office, not to the agency (0 rows from `bid_audit_log`).
- [ ] **Step 2:** Run the database gates; expect failures. Implement 0019; expect PASS. Run `npm run db:types`.
- [ ] **Step 3:** `logic.test.ts`: the form parse ("Choose accept or reject.", "Enter a reason.") and the message mapping. Build the agency page. It shows "No flagged bids need a decision." when the list is empty, and a sealed notice before close.
- [ ] **Step 4:** Run the gates and `npm run build`; expect all green.
- [ ] **Step 5:** Commit: `feat: agency decisions on flagged bids`.

---

### Task 8: Recap computation (single SQL source of truth)

**Files:**
- Create:
  - `supabase/migrations/0020_recap_compute.sql`, `supabase/tests/recap_compute.test.sql`
  - `src/domain/recap/snapshot.ts`, `src/domain/recap/snapshot.test.ts`
- Modify: `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: Task 1 (`app.funding_cents`, `app.funding_from_estimate`), Task 2 (`bid_versions.apprentice_commitment`), Task 4 (`app.bid_review_status`), Task 5 (`app.resident_verified`, `app.resident_unverified`).
- Produces:
  - `app.rank_recap(p_bids jsonb, p_alternate_kinds text[], p_funding_cents bigint, p_estimate_cents bigint) returns jsonb`. Immutable, pure.
    - Each `p_bids` element is `{bidId, reference, bidderName, baseCents, alternateCents[], resident, apprentice}`.
    - It returns the snapshot keys `kind, reason, fundingCents, selectedAlternates, rows, expectedWinnerBidId, winnerOverFunding`.
  - `app.build_recap(p_solicitation_id uuid) returns jsonb`.
    - It gathers the opened bids whose `app.bid_review_status` is `accepted` or `flag_accepted`.
    - For each it reads `resident = app.resident_verified(bid)` and `apprentice = coalesce(version.apprentice_commitment, false)`.
    - It calls `rank_recap` with the snapshot's alternate kinds, `app.funding_cents(snapshot)` and the snapshot's `estimateCents`.
    - It adds `solicitationNumber`, `alternates` and `fundingFromEstimate`.
  - `app.recap_blockers(p_solicitation_id uuid) returns text[]`. In this order, each code at most once:
    - `cure_pending` (any `pending_cure`);
    - `undecided_bids` (any `undecided`);
    - `flags_pending` (any `flagged`);
    - `resident_unverified` (any recap-eligible bid with `app.resident_unverified`).
  - `public.preview_recap(p_solicitation_id uuid) returns jsonb`: office only, after close (`sealed`). It returns `{ recap: app.build_recap(id), blockers: app.recap_blockers(id) }`.
  - TypeScript, `src/domain/recap/snapshot.ts`:
    - `RecapRow`, `RecapSnapshot` (kind `"recap"`), `MemoSnapshot` (kind `"all_rejected"`), `AwardSnapshot`; Zod schemas matching the JSON under Names;
    - `parseRecap(raw: unknown): RecapSnapshot | MemoSnapshot | null`;
    - `parseAward(raw: unknown): AwardSnapshot | null`;
    - `recapColumns(s: RecapSnapshot): string[]` (alternate headers via the existing `alternateHeader`, each marked "(selected)" when it is in `selectedAlternates`);
    - `memoText(s: MemoSnapshot): string`.

- [ ] **Step 1: The algorithm.** The tests do not determine it, so implement exactly this:

```
Let n = number of alternates; sign(j) = +1 if p_alternate_kinds[j] = 'additive' else -1.
For a bid b and a set S of alternate indexes:
  T(b,S) = baseCents(b) + Σ_{j∈S} sign(j) * alternateCents(b)[j]           -- actual price, cents
  credit(b) = apprentice(b) AND p_estimate_cents >= 100000000
  E(b,S) = T(b,S) * (credit(b) ? 99 : 100)                                  -- evaluated, hundredths of a cent (exact)

0. If p_bids is empty -> {kind:'all_rejected', reason:'no_accepted_bids', rows:[], selectedAlternates:[], ...}.
   If every baseCents > p_funding_cents -> {kind:'all_rejected', reason:'over_funding', rows:[], ...}.

1. Alternate selection ("taken in the order stated", stop at the first that does not fit):
   S := {}
   for j in 1..n:
     S' := S ∪ {j}
     m := min_b E(b,S');  L := { b : E(b,S') = m }                          -- lowest evaluated (no resident preference)
     if max_{b∈L} T(b,S') <= p_funding_cents then S := S' else exit loop

2. Ranking for the final S:
   N := min E(b,S) over bids with resident(b) = false                       -- null if there are none
   preferred(b) := resident(b) AND N is not null AND E(b,S) * 100 <= N * 105 -- within 5%, inclusive
   key(b) := (preferred(b) ? 0 : 1, E(b,S))
   rank(b) := 1 + count of bids whose key is strictly less than key(b)       -- competition ranking: 1,1,3
   tied(b) := another bid has the same key

3. expectedWinnerBidId := the bid with rank 1 if exactly one has rank 1, else null.
   winnerOverFunding := expected winner exists AND T(winner,S) > p_funding_cents.
   rows ordered by rank, then reference. totalCents = T(b,S); evaluatedCents = (E(b,S) + 50) / 100 (half-up, display only);
   apprenticeCredit = credit(b); residentPreferred = preferred(b); selectedAlternates = S ascending.
```

- [ ] **Step 2: Write failing pgTAP cases** in `recap_compute.test.sql`, one literal `app.rank_recap` call each. Unless stated: no alternates, funding 200,000,000, estimate 150,000,000, `resident` and `apprentice` false.
  - **Review Focus 2:** N base 100,000,000; R `resident` base 105,000,000 → R rank 1, `residentPreferred` true, `expectedWinnerBidId` = R. With R base 105,000,001 → N rank 1, R rank 2, `residentPreferred` false.
  - R at 104,000,000 but `resident: false` (unverified, as `build_recap` passes it) → N rank 1.
  - Two non-residents (100,000,000 and 103,000,000) and R at 104,000,000 → R 1, then 100,000,000 at 2, then 103,000,000 at 3.
  - All residents (no non-resident) → plain ascending order, every `residentPreferred` false.
  - **Review Focus 3:** with estimate 100,000,000:
    - A base 100,000,000 `apprentice` against B 99,500,000 → A rank 1, `apprenticeCredit` true, `evaluatedCents` 99,000,000;
    - with estimate 99,999,999 → B rank 1 and A's `apprenticeCredit` false;
    - with estimate 100,000,000 and A `apprentice: false` → B rank 1;
    - A credited 100,000,000 against B 99,000,000 → both rank 1, both `tied`, `expectedWinnerBidId` null.
  - **Review Focus 4:** alternate kinds `{additive,additive}`; A base 100,000,000, alternates [10,000,000, 1]; B base 101,000,000, alternates [9,500,000, 5].
    - Funding 110,000,000 → `selectedAlternates` [1], A `totalCents` 110,000,000, rank 1.
    - Funding 109,999,999 → [] and A `totalCents` 100,000,000.
    - Funding 200,000,000 → [1,2].
  - Stop rule: kinds `{additive,additive}`; A base 100,000,000, alternates [20,000,000, 1], funding 110,000,000 → [] (alternate 2 is never considered once alternate 1 fails).
  - A deductive alternate: kind `{deductive}`; A base 100,000,000, alternate [5,000,000] → [1], `totalCents` 95,000,000.
  - Selection ignores the resident preference but the ranking applies it:
    - N base 100,000,000, alternate [10,000,000]; R resident base 104,000,000, alternate [10,000,000]; funding 110,000,000;
    - result: [1], R rank 1, `winnerOverFunding` true (R's total 114,000,000).
  - **Review Focus 6:**
    - bases 100,000,000 and 100,000,001 with funding 99,999,999 → `kind` `all_rejected`, `reason` `over_funding`, `rows` `[]`;
    - funding 100,000,000 → `kind` `recap`;
    - `'[]'` bids → `reason` `no_accepted_bids`.
  - Integration (`build_recap` / `recap_blockers` / `preview_recap`) on a fixture solicitation:
    - one `pending_cure` bid → blockers `{cure_pending}`;
    - after logging its bond: one undecided → `{undecided_bids}`;
    - then a flagged one → `{flags_pending}`;
    - an unverified resident claimant → `{resident_unverified}`;
    - with all resolved, `build_recap` lists only `accepted`/`flag_accepted` bids, with `fundingFromEstimate` false for a snapshot carrying `fundingAmountCents`;
    - `preview_recap` as an agency author → `not_authorized`; before close → `sealed`.
- [ ] **Step 3: Write failing Vitest cases** in `snapshot.test.ts`:
  - `parseRecap` accepts a recap and a memo object shaped as above, and returns null for `{ kind: "recap" }` missing `rows`;
  - `recapColumns` gives `["Alternate 1 (add) (selected)", "Alternate 2 (add)"]` for `selectedAlternates` [1];
  - `memoText` gives "All bids rejected: every accepted bid's base total exceeds the funding amount of $1,000,000.00." for `over_funding`, and "All bids rejected: no bid was accepted." for `no_accepted_bids`.
- [ ] **Step 4:** Implement 0020 and `snapshot.ts`. Run the gates and `npm run db:types`; expect all green.
- [ ] **Step 5:** Commit: `feat: recap computed in Postgres from sealed prices`.

---

### Task 9: Recap workflow: prepare, check, post, freeze; the all-rejected memo

**Files:**
- Create:
  - `supabase/migrations/0021_recap_workflow.sql`, `supabase/tests/recap_workflow.test.sql`
  - `src/components/RecapTable.tsx`
  - `src/app/office/solicitations/[id]/review/RecapPanel.tsx`
- Modify:
  - `src/app/office/solicitations/[id]/review/{page.tsx,actions.ts,logic.ts,logic.test.ts}`
  - `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: Task 8 (`app.build_recap`, `app.recap_blockers`, `parseRecap`, `recapColumns`, `memoText`), Task 4 (`app.lock_evaluation`, `app.require_stage`).
- Produces:
  - `public.recaps`:
    - `solicitation_id uuid pk`, `kind public.recap_kind` (`recap`, `all_rejected`), `snapshot jsonb not null`;
    - `prepared_by`, `checked_by null`, `single_reviewer boolean not null`;
    - `posted_at default now()`;
    - check `single_reviewer = (checked_by is null)`.

    Append-only. `grant select to anon, authenticated` with policy `recaps_read` `using (true)`: rows exist only once posted.
  - `app.was_evaluation_reviewer(p_solicitation_id uuid, p_user uuid) returns boolean`: true when `p_user` is the actor of any `bid_audit_log` row for the solicitation with action in `set_bid_outcome`, `verify_resident`, `send_flags_to_agency` or `send_recap_to_check`. Unlike slice 1 this has no rounds: anyone who ever reviewed these bids cannot check them.
  - `app.require_recap_ready(p_solicitation_id uuid)`: raises the first `app.recap_blockers` code.
  - `public.send_recap_to_check(p_solicitation_id uuid) returns void`: office; `bid_review`; ready. It sets `stage = 'recap_check'`, `recap_preparer_id = auth.uid()` and `recap_draft = app.build_recap(id)`, and audits `{kind}`.
  - `public.disagree_recap(p_solicitation_id uuid, p_comment text) returns void`: office; `recap_check`; `was_evaluation_reviewer` → `same_person`; blank → `comment_required`. It returns to `bid_review`, clears `recap_draft`, and audits `{comment}`.
  - `public.post_recap(p_solicitation_id uuid) returns void`:
    1. office; `recap_check`; `same_person` as above;
    2. `app.build_recap(id)` must equal `recap_draft`, else `recap_stale` (a post-close void can change a status);
    3. inserts `recaps` (`checked_by = auth.uid()`, `single_reviewer = false`);
    4. sets the stage to `recap_posted`, or to `all_rejected` for that kind;
    5. audits `post_recap` with `{kind}`.
  - `public.post_recap_alone(p_solicitation_id uuid) returns void`: office; `bid_review`; ready. It builds and inserts with `prepared_by = auth.uid()` and `single_reviewer = true`, sets the stage, and audits `post_recap_alone` with `{kind, 'fallback', 'no second reviewer available'}`.
  - `RecapTable({ recap }: { recap: RecapSnapshot })`:
    - columns: rank (with "tied"), bidder, reference, base, each alternate, the selected total, and the resident and apprentice flags as text ("Resident preference", "Apprentice credit");
    - the expected winner row is marked "Expected award";
    - a `Notice tone="warning"` when `winnerOverFunding`: "The expected award exceeds the funding amount.";
    - all amounts are `Money` of snapshot cents.
  - `RecapPanel`:
    - in `bid_review`: the preview (`preview_recap`), the blockers as a `Notice` list, and "Send recap to check" and "Post alone (no second reviewer available)" buttons, disabled while blockers exist;
    - in `recap_check`: the draft with "Post recap" and a disagree form;
    - posted: the frozen recap or memo;
    - the memo variant's buttons read "Send memo to check" and "Post memo".
  - Actions: `sendRecapToCheck`, `disagreeRecap`, `postRecap`, `postRecapAlone`.

- [ ] **Step 1: Write failing tests** in `recap_workflow.test.sql`. Office users r1 and r2; fixture with all bids resolved; r1 set the outcomes.
  - **Review Focus 5:**
    - r1 `send_recap_to_check` → stage `recap_check`, `recap_draft` = `app.build_recap(sol)`;
    - r1 `post_recap` → `same_person`; r1 `disagree_recap` → `same_person`;
    - r2 `disagree_recap(sol, '')` → `comment_required`;
    - r2 `disagree_recap(sol, 'Bid C ground is wrong')` → `bid_review`, `recap_draft` null;
    - r2 now sets an outcome, so r2 is a reviewer too; after r1 re-sends, r2 `post_recap` → `same_person`;
    - office r3 `post_recap` → 1 `recaps` row with `checked_by` r3 and `single_reviewer` false; stage `recap_posted`.
  - In `recap_check`, `set_bid_outcome` → `invalid_state`.
  - Stale: after send, void a counted `signed_form` entry of an accepted bid (allowed after close) → `post_recap` raises `recap_stale`.
  - `send_recap_to_check` with a pending cure → `cure_pending`; with an undecided bid → `undecided_bids`.
  - **Review Focus 6:** a fixture with funding 99,999,999 and accepted bases 100,000,000 and 100,000,001.
    - `post_recap_alone` → `kind` `all_rejected`, snapshot `reason` `over_funding`, `rows` `[]`;
    - `single_reviewer` true; the audit detail has `fallback`;
    - stage `all_rejected`; later `send_recap_to_check` → `invalid_state`.
  - Anon and a bidder read the posted `recaps` row (1 row for this solicitation). `update`/`delete` on `recaps` raise for every role. A second insert for the same solicitation fails (pk).
  - An agency author calling any of the four functions → `not_authorized`.
- [ ] **Step 2:** Run the database gates; expect failures. Implement 0021; expect PASS. Run `npm run db:types`.
- [ ] **Step 3:** `logic.test.ts`: `reviewMessageFor` covers `recap_stale` ("The bids changed after this recap was prepared. Send it back and prepare it again.") and `cure_pending`. Build `RecapTable` and `RecapPanel`.
- [ ] **Step 4:** Run the gates and `npm run build`; expect all green.
- [ ] **Step 5:** Commit: `feat: recap check and posting with the all-rejected memo`.

---

### Task 10: Award: agency pick, reason rules, office posting with check

**Files:**
- Create:
  - `supabase/migrations/0022_award.sql`, `supabase/tests/award.test.sql`
  - `src/app/agency/solicitations/[id]/bids/AwardPickPanel.tsx`
  - `src/app/office/solicitations/[id]/review/AwardPanel.tsx`
- Modify:
  - the agency and office `actions.ts`, `logic.ts`, `logic.test.ts` and `page.tsx`
  - `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: `recaps` (Task 9), `app.require_solicitation_agency` (Task 7), `RecapTable`, `parseAward`.
- Produces:
  - `public.award_picks`:
    - `id uuid pk`, `solicitation_id`, `bid_id`;
    - `reason text null`;
    - `picked_by`, `picked_at default now()`.

    Append-only, no API privileges.
  - `public.awards`:
    - `solicitation_id uuid pk`, `bid_id`, `pick_id references award_picks`;
    - `snapshot jsonb not null`;
    - `prepared_by`, `checked_by null`, `single_reviewer boolean not null`;
    - `posted_at`.

    Append-only. `awards_read` policy `using (true)` for anon and authenticated.
  - `public.pick_award(p_solicitation_id uuid, p_bid_id uuid, p_reason text) returns uuid`. Order:
    1. owning agency;
    2. `lock_evaluation`, stage `recap_posted`, recap kind `recap` → else `invalid_state`;
    3. the bid is not in the recap rows → `not_in_recap`;
    4. reason required (`reason_required`) unless `p_bid_id = expectedWinnerBidId` and that is non-null. This covers a pick that differs and any pick when rank 1 is tied.

    Audit `pick_award` with `{bid_id, reason, differs_from_expected}`.
  - `public.current_award_pick(p_solicitation_id uuid) returns table (bid_id uuid, reference text, reason text, picked_at timestamptz, differs_from_expected boolean)`: office or the owning agency; the latest pick.
  - `public.send_award_to_check(p_solicitation_id uuid) returns void`: office; `recap_posted`; no pick → `pick_required`. It sets `award_check` and `award_preparer_id`, and audits.
  - `public.disagree_award(p_solicitation_id uuid, p_comment text) returns void`: office; `award_check`; the caller is the actor of any `send_award_to_check` row for the solicitation → `same_person`; blank → `comment_required`. It returns to `recap_posted`.
  - `public.post_award(p_solicitation_id uuid) returns void`: office; `award_check`; same-person as above. It inserts `awards` with the snapshot built from the latest pick and the posted recap:
    - `amountCents` = that row's `totalCents`;
    - `selectedAlternates` and `alternates` from the recap;
    - `differsFromExpected`.

    It sets the stage to `awarded`.
  - `public.post_award_alone(p_solicitation_id uuid) returns void`: office; `recap_posted`; pick required. It sets `single_reviewer = true`, `awarded`, and the fallback audit detail.
  - Agency `AwardPickPanel`:
    - the posted `RecapTable`;
    - a `Choice` per recap row with the expected winner preselected;
    - a reason field that is required (and labelled so) when the selection is not the expected winner or rank 1 is tied;
    - "Record award choice".
  - `parsePick(form, recap): { ok: true; value: { bidId: string; reason: string | null } } | { ok: false; message: string }`:
    - "Choose a bidder from the recap.";
    - "Explain why this bid differs from the expected award.";
    - "Explain the choice between tied bids.".
  - Office `AwardPanel`: the current pick (with "Differs from the expected award" text), "Send award to check", "Post award", "Post alone (no second reviewer available)", and the disagree form; the same disabled rules as the recap.

- [ ] **Step 1: Write failing tests** in `award.test.sql`. Fixture: a posted recap with expected winner A (rank 1), B rank 2; and a second fixture with A and B tied at rank 1.
  - Before posting (`bid_review`), `pick_award` → `invalid_state`.
  - `pick_award(sol, A, null)` → ok. `pick_award(sol, B, null)` → `reason_required`. `pick_award(sol, B, 'A cannot meet the start date')` → ok, and `current_award_pick` shows B with `differs_from_expected` true.
  - A withdrawn or non-recap bid id → `not_in_recap`. A bidder or another agency → `not_authorized`.
  - Tied fixture: `pick_award(sol2, A, null)` → `reason_required`; with a reason → ok.
  - **Review Focus 5:**
    - r1 `send_award_to_check` → `award_check`;
    - r1 `post_award` → `same_person`; r1 `disagree_award` → `same_person`;
    - r2 `post_award` → stage `awarded`, and `awards.snapshot->>'amountCents'` equals the recap row's `totalCents` for B. The snapshot has no `reason` key.
  - `send_award_to_check` with no pick → `pick_required`.
  - In `award_check`, `pick_award` → `invalid_state`.
  - On a fresh fixture, `post_award_alone` → `single_reviewer` true with the fallback audit.
  - Anon reads the `awards` row. Anon and a bidder cannot execute `current_award_pick` (`not_authorized` / 42501). Append-only checks.
  - On an `all_rejected` solicitation, `pick_award` → `invalid_state`.
- [ ] **Step 2:** Run the database gates; expect failures. Implement 0022; expect PASS. Run `npm run db:types`.
- [ ] **Step 3:** `logic.test.ts` for `parsePick` (all three messages, and the expected-winner path with a null reason). Build both panels.
- [ ] **Step 4:** Run the gates and `npm run build`; expect all green.
- [ ] **Step 5:** Commit: `feat: agency award pick and checked award posting`.

---

### Task 11: Public recap, award and memo; the bidder's outcome

**Files:**
- Create: `supabase/migrations/0023_bid_outcome_view.sql`, `supabase/tests/bid_outcome.test.sql`, `src/app/bidder/solicitations/[id]/OutcomePanel.tsx`
- Modify:
  - `src/app/solicitations/[number]/page.tsx`
  - `src/app/bidder/solicitations/[id]/page.tsx`
  - `src/app/solicitations/status.ts` (+ test)

**Interfaces:**
- Consumes: `recaps`, `awards` (public select), `RecapTable`, `parseRecap`, `parseAward`, `memoText`, `app.bid_review_status`.
- Produces:
  - `public.my_bid_outcome(p_bid_id uuid) returns table (status text, reason text)`. Own bid only (`not_found`). It returns no row until a `recaps` row exists for the bid's solicitation; then the bid's `app.bid_review_status`.
  - `postedOutcomeLabel(status: string): string` in `status.ts`:
    - `accepted` and `flag_accepted` → "Accepted";
    - `non_responsive` → "Non-responsive";
    - `flag_rejected` → "Rejected by the agency".
  - Public page cards, below "Documents", only when the rows exist:
    - "Bid recap" (`RecapTable`, plus the posted date);
    - "All bids rejected" (`memoText`);
    - "Award": the winner's bidder name, `Money amountCents`, and the selected alternates listed by description, or "Base bid only".
  - The bidding badge stays as it is. A posted award adds `StatusBadge` `{ kind: "evaluation", stage: "awarded", awaitingAgency: false }`.
  - Bidder: `OutcomePanel` shows `postedOutcomeLabel` and the reason text after posting, plus links to the public page.

- [ ] **Step 1: Write failing tests:**
  - pgTAP:
    - before posting, `my_bid_outcome` returns 0 rows;
    - after `post_recap_alone`, the owner gets its status and another bidder gets `not_found`;
    - anon cannot execute it (42501).
  - Vitest: the `postedOutcomeLabel` mapping, and an unknown value returns itself.
- [ ] **Step 2:** Implement. Run the gates and `npm run build`; expect all green.
- [ ] **Step 3:** Verify manually on the Task 12 seed. Signed out, before posting, the closed solicitation's page shows no recap card and no bid data. After posting it shows exactly the recap or memo, then the award.
- [ ] **Step 4:** Commit: `feat: public recap, award and memo, and the bidder's outcome`.

---

### Task 12: Seed, end-to-end walk and docs

**Files:**
- Modify: `supabase/seed.sql`, `README.md`, `docs/decisions.md`

**Interfaces:**
- Seed, all fictional, inserted directly (as the 2a seed does):
  - Ridgeback's company row gets `resident_claimed = true`, `resident_certificate = 'CR-0042'`.
  - New bidder orgs, each with a company row and a user (password `proclaro-dev`; guarded with the `app.registering` flag as the existing seed does):
    - "Juniper Flats Paving" (`bidder.juniper@example.test`);
    - "Basalt Creek Builders" (`bidder.basalt@example.test`).
  - Solicitation 27-0003, "Maintenance building expansion":
    - estimate 120,000,000, `fundingAmountCents` 125,000,000;
    - two additive alternates: "Add skylights" and "Add solar-ready conduit";
    - due `date_trunc('minute', now()) - interval '1 hour'`;
    - the snapshot built like 27-0001's.
  - Its bids. Each is v1, submitted 2 hours before due, with a signed original logged 1 hour before due:

    | Bidder | Items | Alternates | Bid bond | Apprentice |
    |---|---|---|---|---|
    | Ridgeback | [100,000,000, 20,000,000] | [4,000,000, 6,000,000] | paper, logged | false |
    | Granite | [98,000,000, 20,000,000] | [4,000,000, 5,500,000] | paper, logged | true |
    | Juniper | [97,500,000, 20,000,000] | [4,500,000, 5,000,000] | paper, logged | false |
    | Basalt | [99,000,000, 20,000,000] | [4,200,000, 5,800,000] | paper, **not** logged (pending cure) | false |

  - The expected recap once Basalt is cured and accepted, and Ridgeback verified:
    - alternate 1 only (Granite's alternate-2 total of 127,500,000 exceeds funding);
    - Ridgeback first by resident preference ($1,240,000.00 against Granite's evaluated $1,207,800.00);
    - then Granite, Juniper and Basalt, in evaluated order: Granite 120,780,000 (credited), Juniper 122,000,000, Basalt 123,200,000.

    Without Ridgeback's verification, Granite ranks first.
  - 27-0001 and 27-0002 keep no `fundingAmountCents` (the estimate fallback).
- [ ] **Step 1:** Run `npm run lint && npm test && npm run db:reset && npm run db:test && npm run build`; expect all green.
- [ ] **Step 2: Walk the flow** with `npm run dev` on 27-0003:
  1. Basalt's bidder page shows "pending cure" with a due time of 17:00 the next business day, and uploads a bond. Ridgeback's page shows no upload.
  2. Reviewer One:
     - accepts Ridgeback, Juniper and Basalt;
     - flags Granite ("Mailed form total differs from portal entry");
     - verifies Ridgeback's certificate;
     - sends flags to the agency.
  3. The Corrections author sees only Granite's reference, note and base total, and accepts it.
  4. Reviewer One sends the recap to check. Reviewer One cannot post it. Reviewer Two posts it.
  5. Signed out, `/solicitations/27-0003` shows the recap in the order above, with alternate 1 selected.
  6. The author picks Granite with a reason. Reviewer One sends the award; Reviewer Two posts it.
  7. The public page shows Granite at $1,220,000.00 with "Add skylights".
  8. The REST API with the anon key: `select` on `bid_outcomes`, `award_picks` and `evaluations` returns a permission error or 0 rows.
- [ ] **Step 3:** Record "Slice 2b, as built" in `docs/decisions.md`:
  - the stored-versus-displayed stages;
  - the single SQL source for the recap;
  - the alternate and ranking algorithm (verbatim from Task 8);
  - cure counting (`<` for uploads, `<=` for logged paper bonds);
  - the bidder seeing its outcome only after posting;
  - the agency's minimal flagged view;
  - known gaps:
    - holiday edits after close move a live cure deadline;
    - deductive alternates are always taken when reached;
    - the expected winner can exceed funding under the resident preference or the apprentice credit (shown, not blocked);
    - the funding amount is readable in the public `published_snapshot`;
    - no two-session race test for the evaluation lock.

  Update the README seed list.
- [ ] **Step 4:** Search the repo for the real-world names on the slice 1 search list; expect no matches. Do not open `source-docs/`.
- [ ] **Step 5:** Commit: `docs: bid review and award slice complete`.

---

## Spec coverage

| Spec section | Task |
|---|---|
| §0 Funding amount: field, required, below-estimate warning, snapshot, frozen, fallback | 1 |
| §1 Office review: outcomes, fixed grounds, automatic signed-original rule, mismatch flagged, change until check, audited | 4, 6 |
| §2 Bond cure: pending status, bond-only upload, paper log, automatic disqualification, blocks the recap | 3, 8 |
| §3 Resident verification | 5, 6 |
| §3 Apprentice commitment: sealed, printed, parity | 2 |
| §4 Flagged bids: agency-only view with note and base total, accept/reject with reason, rejected excluded | 7, 8 |
| §5 Recap: evaluated price, alternates, ranking, ties, contents, two-person posting, frozen, public, memo | 8, 9, 11 |
| §6 Award: pick from recap, expected preselected, reason rules, checked posting, public, ends awarded | 10, 11 |
| §7 States after close, definer transitions with one audit row | 4, 9, 10 |
| Access rules (bidder, agency, office, public) | 3, 7, 9, 10, 11 |
| Anti-goals (typed numbers, overriding automatic rules, leaking bids) | 4, 8, 9, 7 |
