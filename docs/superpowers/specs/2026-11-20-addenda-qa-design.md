# Slice 2c: addenda, acknowledgments and the Q&A board

Status: draft for Drew's approval, 2026-11-20. Items marked *(my call)* are the controller's proposals and are open to correction.

## Intent
A published solicitation is frozen. In the real process it still changes before close, but only through numbered addenda. An addendum can:
- move the bid date;
- answer bidders' questions;
- revise drawings;
- add or change bid items;
- approve substitutions.

Without addenda, Proclaro can't run a real procurement, so Drew wants them in v1 ("addenda are needed for v1"). The rule already recorded in `docs/decisions.md` (2026-11-17) governs this slice:
- each addendum increases the solicitation's version;
- published versions are never edited;
- bidders acknowledge every addendum;
- a missing acknowledgment at close means the bid is accepted but flagged for the agency.

## Decided by Drew
- **2c comes before the AI document check.**
- **Submitted bids when the schedule changes (option A).** An addendum that changes the bid schedule (items or alternates) moves every submitted bid to **resubmit required**. The old submission stays sealed and is never counted. The bidder re-prices, acknowledges, submits again and mails a new signed original.
- **Submitted bids when the schedule doesn't change.** The bid stays submitted. The bidder may replace it to add the acknowledgment.
- **The Q&A board is in scope.**
- **Questions stay anonymous until the addendum.** A bidder sees only its own questions. Everyone sees the answers once the addendum is published, without the asker's name.
- Drew accepted the 2026-11-20 playback without changes. That covers every item below marked *(played back)*.
- **Acknowledging is a separate online action** (builder-check answer). It is not a new bid version. A bidder acknowledges an addendum on the bid page whether or not its bid is submitted, so no new mailed original is needed. See §5.
- **The 5-day rule applies to every addendum** (builder-check answer). An addendum published with fewer than 5 days left must also push the bid due date out. See §3.

## Carried from earlier decisions
- **Published versions are read-only forever.** Storage paths are already versioned: `solicitations/{id}/v{n}/…`.
- **The bid form footer** shows the number, the version and "Page X of Y".
- **Two-person check:** the same person can't be both reviewer and checker. A one-reviewer fallback is allowed and recorded, the same rule as slice 1.
- **No deadline override.** Deadlines are judged on the database clock (Ruling 8: writers re-check `clock_timestamp()` after taking their lock).
- **Bids are sealed** from everyone, the bidder included, until close.

## Goals, non-goals, anti-goals
**Goals:** addenda from draft to publish, acknowledgments, resubmit required, and the Q&A board. Every guarantee is enforced in Postgres and covered by pgTAP:
- the version sequence;
- the published history can't be changed;
- the same-person check;
- question deadlines and anonymity;
- resubmit required;
- the acknowledgment flag at close.

**Non-goals:**
- Email or any other notification outside the app.
- A pre-bid meeting attendance log.
- Addenda after close.
- Cancelling a solicitation.
- Live Q&A visible to all bidders.
- Generating PDFs for seeded solicitations, an existing gap. New addenda do generate PDFs.

**Anti-goals:**
- Any edit to a published version or its files.
- A submitted bid priced against an old schedule being opened, tabulated or counted in the recap.
- Revealing to another bidder or the agency who asked a question.
- A bidder learning anything about other bids.

## Approaches
Today a published solicitation carries one frozen `published_snapshot` (jsonb). Every 2a/2b reader takes its items, alternates, bond rule and funding from that snapshot: `bid_draft_problems`, tabulation, the recap and the public page. Bid prices are arrays that line up with the snapshot's items by position (`item_cents`, `alternate_cents`). Items have no ids.

- **A. Addendum as a draft of the next snapshot (chosen).**
  - An `addenda` row holds the full proposed solicitation data, a narrative and the Q&A answers.
  - It has its own review and check, which follow slice 1's rules.
  - Publishing appends a `solicitation_versions` row and advances `solicitations.published_snapshot`, `version`, `bid_due_at` and the PDF paths. Every existing reader keeps working unchanged and sees the current version.
  - "Schedule changed" is a comparison of the two snapshots.
  - Cost: the review and check functions are written again for addenda rather than shared.
- **B. Reopen the solicitation's own workflow.** Rejected. `bidding_open`, the public listing and every bid function depend on `state = 'published'`, so bidding would break while an addendum is in review. Avoiding that needs a parallel state, which is A with more risk.
- **C. Addendum as a list of typed changes, applied at publish.** Rejected. Every kind of change needs its own apply step. A's snapshot comparison produces the same "what changed" list for less code.

Drew handed over the how ("go"). A is the controller's pick.

## Design

### 1. Versions and history
- **New table `solicitation_versions`,** with columns:
  - `solicitation_id`, `version`, `snapshot` (jsonb), `rfb_path`, `bid_form_path`;
  - `addendum_path`, null for version 1;
  - `bid_due_at`, `published_at`, `published_by`, `schedule_changed` (bool).

  The table is append-only through the existing `app.reject_change` trigger plus the revoke.
- **A migration backfills version 1** for every solicitation that is already published.
- **`publish_solicitation` writes the v1 row as well.**
- `solicitations.published_snapshot`, `version`, `bid_due_at`, `rfb_path` and `bid_form_path` stay as the **current pointer**. Only addendum publication updates them.
- **Older versions stay viewable.** The public solicitation page lists every version with its RFB, bid form and addendum PDF. The current version is marked.

### 2. Drafting an addendum (agency author)
- **Who and when.** The agency author of the owning agency can start an addendum while all three hold:
  - the solicitation is published;
  - bidding hasn't closed;
  - no other addendum for it is unpublished.

  Only one addendum can be in progress at a time.
- **Numbering.** Addendum numbers run 1, 2, 3… per solicitation. Version = addendum number + 1.
- **What the draft holds:**
  - the full solicitation data, starting as a copy of the current snapshot's data;
  - a required **narrative**, "Changes in this addendum" (plain text);
  - a list of **answered questions**, each with an answer (§6).
- **The editor is the existing solicitation form** pointed at the addendum's data, with the narrative and answers added. The same TS validator and SQL validator apply, along with the existing parity tests.
- **Locked fields** *(my call)*: these are history once published, so an addendum can't change them:
  - `releaseDate`, `adStart`, `adEnd`, `newspapers`, `category`;
  - the clause locks (clauses stay at the versions locked at v1).
- **Funding amount.** It may change, since no price has been seen before close. It stays confidential exactly as in 2b. *(my call)*
- **Attachments.** Revised drawings are added as new attachments, and the old ones can be removed from the new version's list. A file referenced by any published version can never be deleted from storage.
- **Changing the schedule.** An item or alternate can be added, removed, reordered or reworded. The system shows the computed diff (§4) before the addendum goes to review.

### 3. Office review, check and publish
- **The state machine** mirrors slice 1: draft → submitted → in_review → in_check → approved → published. It has the same actions: return to agency with comments, reassign, disagree, approve alone (recorded fallback), reopen.
- **The same-person rule** is round-scoped, as in slice 1.
- **Publishing** is done by the reviewer or checker:
  - the app renders the RFB v{n}, the bid form v{n} and an **addendum PDF**;
  - it uploads them to `solicitations/{id}/v{n}/{rfb,bid-form,addendum}.pdf`;
  - it calls `publish_addendum`, which pins those exact paths, recomputes `bid_due_at` and refuses on mismatch, as `publish_solicitation` does.
- **The addendum PDF** contains the number, solicitation number and title, publish date, the narrative, the computed change list, and the questions and answers with no names.
- **Publish is refused when:**
  - bidding has closed (judged on `clock_timestamp()` after locking the solicitation);
  - the new bid due time is earlier than publish time plus 5 calendar days. This applies to **every** addendum (Drew), so an addendum published with fewer than 5 days left must also extend the bid due date.
- **Answers-due date.** A publish after the answers-due date is allowed, with a warning the office acknowledges *(my call)*. Refusing it would block a needed correction.
- **Confirmation.** Publish uses `ConfirmAction` (Ruling 10).

**Withdrawing an addendum** *(my call)*:
- A terminal state, `withdrawn`, is reachable from any unpublished state.
- The agency author may withdraw an addendum while it is in draft or returned. The office may withdraw it from any unpublished state.
- Withdrawing needs a reason and is audited.
- After close, an unpublished addendum can no longer be published and counts as withdrawn for the one-at-a-time guard. That status is derived, not written by a job.
- Questions picked into a withdrawn addendum go back to open.

### 4. Schedule change and resubmit required
- **When the schedule counts as changed.** `schedule_changed` is true when the new snapshot's `schedule.items` or `schedule.alternates` differ from the previous version's in count, order, name, description or kind. It is computed in SQL at publish and stored on the version row.
- **Bids record their version.** `bid_versions` and `bid_drafts` gain `solicitation_version`, the version the prices were entered against. A backfill migration sets it to 1.
- **When a bid needs resubmission.** A bid is **resubmit required** when its latest submitted version has `solicitation_version` below the latest version with `schedule_changed`. This status is derived, never stored.
  - **For the bidder:** the bid page shows "Resubmit required: Addendum N changed the bid schedule". `submit_bid` works as usual.
  - **At close:** a bid still in resubmit required is treated like a withdrawn bid. It is not opened, tabulated, reviewed or counted, and its prices stay sealed. Its close determination records `resubmit_required`, so the office sees that a bidder had a stale bid.
  - **For the office:** the originals log flags any original for a stale version as not counting, the same as 2a's older-version rule.
- **Drafts.** When a bid's draft was started against an older schedule, the next read of the draft resets `item_cents` and `alternate_cents` to the new lengths (empty) and sets `solicitation_version`. The bid page explains why the prices were cleared *(my call)*. Items have no ids, so carrying prices across would guess wrong. `submit_bid` refuses a draft whose `solicitation_version` is older than the latest schedule change. This is a guard against a race with publish.
- **Bonds and the apprentice question** follow the current snapshot. If an addendum changes the estimate across $150K or $1M, `bid_draft_problems` already reads the current snapshot. A submitted bid that no longer meets the new rule doesn't become resubmit required on that account. It is judged at close by 2b's existing rules (bond cure). *(my call)*

### 5. Acknowledgments
- **Recording them (Drew: a separate online action).**
  - New append-only table `bid_acknowledgments` with columns `bid_id`, `addendum_number`, `acknowledged_at`, `acknowledged_by`.
  - The bidder clicks "Acknowledge Addendum N" on the bid page. This works whether the bid is a draft or already submitted. It never creates a bid version and never needs a new mailed original.
  - Acknowledging is refused at or after close (database clock, Ruling 8) and for an addendum that isn't published.
  - An acknowledgment can't be undone.
  - The bidder can see its own acknowledgments. Office staff see them only at or after close, like the rest of the bid.
- **Submitting without every acknowledgment is allowed.** The page warns: "Bids that don't acknowledge every addendum are flagged for the agency at close." `bid_draft_problems` reports it as a warning, not an error, with TS parity.
- **On the bid form.** The "Addenda acknowledged" line is filled from the acknowledgments recorded when the form is printed, replacing today's blank line. A blank-form print leaves it blank for handwriting.
- **The mailed original isn't checked.** The acknowledgments written on the mailed original aren't compared with the online record, and the online record is what counts *(my call)*. A mismatch the reviewer notices falls under 2b's existing rule: "mailed form doesn't match the portal entry" means accepted and flagged.
- **The banner.** A bidder with a bid in progress or submitted sees: "Addendum N published. Acknowledge it before bids close." It shows an Acknowledge button.
- **At close.** A counted bid missing any addendum gets 2b's review outcome **accepted, flagged for the agency**. It is preset when the review opens, with the fixed note "Did not acknowledge Addendum N[, M]". The reviewer can't change that outcome to plain "accepted" but may still set non-responsive for a listed reason *(my call)*. The agency decides it in the existing flagged-decision step.
- **Correction to the playback.** The playback mentioned "paper bids the office enters". 2a has no such feature: every bid is entered by the bidder online, and the office only logs mailed originals. Nothing extra is built for paper bids, and the acknowledgment rules above apply to every bid.

### 6. Q&A board
- **New table `questions`:** `id`, `solicitation_id`, `asked_by` (profile), `org_id`, `body`, optional `reference` (free text such as "Item 3" or "Section 02 41 00"), `asked_at`, `status` (open | answered | closed), `answered_in` (addendum id), `close_reason` (duplicate | out_of_scope).
- **Asking.** Any signed-in bidder can post a question on a published solicitation until the questions-due date and time. The deadline is judged on the database clock. Questions are plain text, 1 to 4,000 characters *(my call)*. A bidder can't edit or delete a question once posted *(my call)*. It can post a correction as a new question.
- **Visibility, enforced in Postgres:**
  - **A bidder:** its own organization's questions only, with their status and the addendum that answered them.
  - **The office:** every question with the asker's organization and name.
  - **The agency author:** questions on its own solicitations, without the asker or organization *(played back; my call)*. They are read through a definer function that leaves out the identity columns.
  - **The public and other bidders:** only answered questions, through the published addendum, with no identity.
- **Answering.** In the addendum editor the agency author picks open questions. For each one they write:
  - a **published question**, prefilled from the body and edited to remove anything that identifies the asker;
  - an **answer**.

  Publishing the addendum marks those questions answered with `answered_in`.
- **The original body is never public** *(my call)*. Only the asker's organization, the office and the agency author can read `questions.body`. The public page and the addendum PDF show only the published question and answer. The stored body is never changed.
- **Closing.** The office can close a question as a duplicate or out of scope. The asker sees the status. Every action is audited.
- **The public solicitation page** shows "Questions and answers" grouped by addendum.

### 7. Screens
- **Agency** `/agency/solicitations/[id]`:
  - an Addenda section listing every addendum and its state, with a "Start addendum" button;
  - an addendum editor (the solicitation form plus the narrative, the schedule diff and the answers);
  - the open questions list without identities.
- **Office:**
  - an addendum review page with the same panels as the slice 1 review (comments, send to check, disagree, approve alone, publish);
  - the questions list with identities and a close action.
- **Bidder:**
  - an "Ask a question" form and "Your questions" on the solicitation page;
  - addendum checkboxes and banners on the bid page.
- **Public:** the version history, the addendum PDFs and Q&A on `/solicitations/[number]`.

### 8. Seeds
- **27-0004 (open, $1.5M):**
  - one published addendum that changes the schedule (adds an item);
  - questions in every status: one answered by that addendum, one open, one closed as a duplicate.
- **27-0001 (bond required, closes in 14 days):** an addendum in draft, for walking the review and publish flow.
- **A bidder in resubmit required** on 27-0004, for the bidder walkthrough.
- Seeded addendum PDFs are absent, like the other seeded documents. *(my call)*
- The README seed list is updated.

## Left to the builder
- The table and function names beyond those fixed above.
- Whether the addendum review functions share helpers with slice 1's.
- The layout of the addendum PDF.
- The diff presentation.
- Migration numbering from 0026.
- Test structure, following the existing patterns: pgTAP for every guarantee, Vitest for logic and validator parity, and one browser walk of the seeded flow.
