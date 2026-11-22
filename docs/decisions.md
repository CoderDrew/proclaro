# Decision Log

## 2026-11-16 — Initial product decisions

- **Purpose:** Public portfolio project demonstrating product engineering with AI coding agents. Drew acts as product engineer; agents write the code. Runs alongside ContractIQ (the hands-on Python learning project).
- **Fictional agency:** Workflow modeled on a real state agency process, but no real names, branding, bidder data or documents in the repo.
- **v1 scope: RFBs only.** RFPs (weighted scoring, evaluation committees) deferred to phase 2.
- **Sealed bids:** No agency user — and no AI process — can see bid contents before the official close/opening time.
- *(Superseded by "Roles adopted" below.)* **Roles:** Bidder, Creator, Reviewer, Approver, Admin. The same person cannot review and approve the same solicitation; enforced by the system.
- *(Superseded by "Roles adopted" below.)* **Review flow:** Reviewer checks each bid against requirements; Approver signs off. Bids meeting requirements go forward to award; others are marked non-responsive with a recorded reason. Disagreement sends the bid back to the Reviewer rather than the Approver overriding.
- **AI compliance check is advisory only.** It never rejects a bid. Reviewer confirms or overrides each item; overrides are logged with a reason.
- **Two check types:** Structured fields are checked by deterministic rules (no AI). Uploaded documents are checked by the AI. The checklist shows which method verified each item.
- **AI output:** met / not met / unclear, with evidence (document, page, excerpt). No confidence scores — self-reported model confidence is poorly calibrated and invites over-trust.
- **AI checks compliance, not award.** No scoring, ranking or winner recommendation.
- **Evaluation:** Synthetic bids with planted defects. False "met" rate reported separately from false "not met" — passing a non-compliant bid is the costly error.
- **Demo approach:** Screen-shared walkthroughs, not a self-serve demo mode. AI runs only on agency-triggered actions, which limits cost exposure.
- **Stack (proposed, not final):** TypeScript/Next.js + Supabase — chosen so Drew can read and explain the agent-written code fluently.

## 2026-11-16 — Findings from the real process (source documents and agency contact)

Real reference documents are kept locally in `source-docs/`, which is git-ignored. Only generalized, fictionalized rules go in this repo.

### Evaluation and award

- **Evaluation is a MET / NOT MET checklist** per required bid section. This matches the AI output design.
- **Award goes to the lowest responsible bidder whose bid meets the requirements.** "Responsive" (meets the requirements) and "responsible" (able to do the work) are separate determinations.
- **Price adjustments are applied by deterministic rules, not by the AI:**
  - In-state resident preference: a certified resident bidder wins if their bid is within 5% of the lowest non-resident bid.
  - Apprentice credit: on projects of $1M or more, a bidder committing apprentices to at least 10% of labor hours is evaluated as if the bid were 1% lower.
- **Fallback:** if the winner won't sign the contract or can't provide the performance bond, the second-lowest bidder gets the option; if they decline, the project is re-bid. The ranked list of responsive bids is kept after award.
- **Price conflicts:** the amount in words overrides the figures; unit prices override extended totals.

### Requirements depend on project value

- Thresholds are applied to the **agency's project estimate**, so a solicitation's requirement set is fixed when it is created.
- Value bands: $50K (competitive sealed bidding at or above it), $100K (prevailing wage), $150K (bonds), $1M (apprentice credit). The required bid sections differ by band, so requirements are configured per solicitation instead of being a fixed checklist.

### Bonds

- **Bonds are required only when the project estimate is $150,000 or more.**
- **Bid bond (10% of the bid):** guarantees the winner will sign the contract. Submitted with the bid as an electronic surety bond, or as an original bond or cashier's/certified check delivered on paper (a copy is not accepted). Staff record receipt of a paper original with a timestamp. Forfeited if the winner refuses to sign; returned to the others after award.
- **Cure period for a missing bid bond:** if a required bid bond is not with the bid, the bidder has until **5:00 p.m. the next business day** to provide it. Otherwise the bid is disqualified.
  - During the cure period the item's status is "pending cure, due [timestamp]", not "not met".
  - At the deadline the system disqualifies the bid automatically by rule and logs the reason.
  - "Next business day" skips weekends and state holidays, using a holiday calendar the agency can edit.
  - After close, the bidder can upload only the missing item, and only until the cure deadline.
- **Performance and payment bond (100% of the accepted bid):** guarantees the work is completed and that subcontractors and suppliers are paid. Due within **20 calendar days of the award notice**. If it isn't delivered, the agency may move to the next-lowest responsible bidder.
  - This is the notarized document: the principal and the surety each sign before a notary.
  - It must be increased if change orders raise the contract amount.
  - The workflow therefore continues after award: Awarded → Bond pending → Contract executed.
- **Performance bond checks:**
  - Bond amount ≥ 100% of the accepted bid: deterministic. The AI extracts the amount and a rule compares it.
  - Signatures, notary blocks and matching bond numbers: AI, with evidence.
  - Notary commission not expired at the acknowledgment date: deterministic, from dates the AI extracts.
  - "No alterations to the printed form": human only.
  - Approval as to form by the state's legal office: an agency approval step in the workflow, not a check.

### Hard rejections and workflow events

- **Grounds for hard rejection:** a late or incomplete upload; improper or missing signatures, or numbers that can't be read; modifying contract language; not signing in at a mandatory pre-bid meeting; contacting agency staff outside the allowed channels. Other irregularities can be waived at the agency's discretion.
- **Workflow events to support:**
  - Addenda, which bidders must acknowledge on the bid form (a deterministic check).
  - Substitution requests.
  - Public Q&A that doesn't identify who asked.
  - Bid modification or withdrawal before opening; no withdrawal for 30 days after opening.
  - A subcontractor list due within 24 hours after opening.
  - Bids stay binding for 90 days.
  - A bid tabulation published after opening.
- **v1 targets construction RFBs**, the domain of the reference documents.

## 2026-11-16 — Revisions after auditing a full real procurement package

Details and evidence: `docs/discovery.md`.

- *(Resolved by "Roles adopted" below.)* **Roles and review flow are under review.** The real process involves two organizations. A central procurement office decides whether each bid is accepted (responsive), and the requesting agency picks the award from the accepted bids. The single-agency Creator/Reviewer/Approver model above is on hold until the real steps are mapped.
- **No deadline override, for anyone.** In the real example, a project manager was willing to accept a late bid and procurement refused. The system offers no override path.
- **Sealed bids include the bidder.** After submitting, a bidder can't view their submission until close.
- **Bond threshold confirmed: the project estimate, $150,000 or more.** This is set on the solicitation when it's created, not evaluated per bid. The real intake form ties the statutory requirement to the bid amount instead; Drew confirmed the estimate-based rule for Proclaro.
- **Document checks must work on scanned images.** Most real bids are scans with handwriting and no text layer.
- **Post-award bond package.** The package is:
  - the original performance and payment bond, notarized for both principal and surety, left undated so the agency can date it after the contract is signed;
  - the surety's power of attorney;
  - a notarized certification letter authorizing the person who signed.

  The bidder's name must exactly match the business registration record. A mismatch sends the bond back for correction, not disqualification.
- **The recap lists only accepted bids.** Accepted is a separate state from awarded.
- **v1 ends at award publication.** Everything after award is out of scope for v1: the performance and payment bond, the bond package, legal approval and contract execution. The post-award bond notes above are kept as reference for later. The **bid bond** is submitted with the bid, so checking it at review stays in v1.
- **A bid not on the solicitation's own bid form is non-responsive.** This is confirmed by a real rejection.

## 2026-11-16 — Confirmed by the procurement office

- **Bid outcomes at review:**
  - **Accepted.**
  - **Accepted, flagged for the agency** (for example, a missing addendum acknowledgment). The agency decides whether to accept or reject it.
  - **Non-responsive.** Only for a late upload, the wrong form, a missing signature, or a bid bond still missing after the cure deadline.
- **The bid-bond cure is the only fix allowed after close.**
- **A bidder can replace their bid before close.** The latest version counts (assumed).
- **A mismatch between words and figures is flagged for a person to decide**, with the reason logged. There's no settled rule.
- **All bids over budget ends in an "all bids rejected" outcome**, published as a memo.
- **The posted recap is the only public disclosure**; there is no public opening.
- **Ties go to the agency to decide.**
## 2026-11-16 — Roles adopted

These replace the original Roles and Review flow entries.

| Role | Organization | Does |
|---|---|---|
| Bidder | Vendor | Submits and replaces bids before close |
| Agency author | Requesting agency | Fills in the solicitation; decides on flagged bids and ties; picks the award |
| Procurement reviewer | Procurement office | Reviews the solicitation before posting; reviews bids; prepares the recap and award |
| Procurement checker | Procurement office | A second person who confirms the reviewer's work before anything is posted |
| Admin | Procurement office | Templates, users, holiday calendar |

- **Two-person check by default.** Posting a solicitation, recap or award needs a reviewer and a checker. The system blocks the same person from filling both roles on the same item.
- **One-reviewer fallback, recorded.** If no checker is available, the reviewer may post alone but must choose "no second reviewer available". That is stamped on the record and the audit log, so how often it happens can be counted.
- **Disagreement goes back to the reviewer.** If the checker disagrees, the item returns to the reviewer. The checker doesn't override.
- **No Approver role in the office.** The award decision belongs to the agency author. The system computes the expected award (lowest after the preference) and shows when the agency's pick differs.

## 2026-11-17 — Solicitation setup slice, as built

Covers the path from an agency drafting a solicitation to a public listing: agency drafting and submitting (`/agency`), office review with the two-person check and the recorded single-reviewer fallback (`/office`), PDF preview, publishing, the public listing (`/solicitations`), and admin (`/admin`). Bids, bidders and everything after publication are not part of it. Design and plan: `docs/superpowers/`.

Decisions made during the build:

- **Published files are keyed by the solicitation's uuid, not its number.** Objects live at `solicitations/{id}/v1/...` in the `published` bucket, which matches the storage policy that decides who can read them.
- **Publish validation uses the latest submission date, plus a separate release-date check.** The rules are re-validated at send-to-check against the latest submission date, and a second check rejects a release date that has already passed. Using today as the submission date would have demanded a release date three days out, which contradicts the rule that only a passed date blocks publishing.
- **Attachments are copied into the published bucket at publish.** The attachments bucket is closed to the public and to the agency once published, so each attachment is copied to `solicitations/{id}/v1/attachments/` and the snapshot records the new paths. The published file set is immutable along with the row.
- **The published bucket is private, with release-gated reads.** Reads are allowed only when the solicitation is published and its release date has arrived (or for office staff). Public pages serve files through short-lived signed URLs created with the visitor's own client, so there is no public bucket URL.
- **The preview uses clause locks.** Sending to check (or approving alone) locks the clauses, so drafts and previews show the clause text that will be published.
- **First sign-in for invited users uses a token hash, not a URL fragment.** The invite email links to `/auth/confirm` with the token hash, and the server verifies it with `verifyOtp` under `@supabase/ssr`. The tokens never pass through the browser in a URL fragment, and no client-side code handles them. `/auth/set-password` and its action both require an auth user with `invited_at` set, whose current session's `amr` claim says `otp`. Verifying a token hash records `otp`, and login offers only passwords, so a password sign-in can never reach the page. The invite's `redirectTo` comes from `SITE_URL` and must be listed in `additional_redirect_urls`; otherwise the auth server falls back to `site_url` and the link loses its path. The app requires passwords of 8 to 72 bytes; the auth server's own floor (6) is lower.
- **The admin client is confined to user invites.** Everything else, including all other admin screens, runs under the signed-in admin's own session and row-level security. The invite path also uses it to check whether a profile exists and to remove a half-created auth user, so cleanup can never delete an existing user whom row-level security hides from an agency-organization admin.
- **Admin changes are not audited.** The spec's audit list (§7.8) covers the solicitation workflow only: every state change, every field edit after submission (old value, new value and reason), every comment, every fallback approval and every publish, each with who and when. So users, organizations, clauses, holidays and settings are not logged.
- **An approved solicitation can be reopened to correct its dates.** The reviewer or checker can move an approved solicitation back to review with a recorded reason (`reopen_review`). That clears the checker, the single-reviewer flag and the clause locks, so it needs a fresh check (or approval alone) before publishing. This is the remedy the design names for a release date that passes before publishing. Send to check and approve alone also refuse a release date that has already passed, so a stale date can't be approved in the first place.
- **The release date comes before the other dates.** A release date on or after the questions-due date is an error. An advertisement that starts before the release date is a warning to acknowledge, because advertising may legitimately start before the posting.
- **Publishing pins its file paths and recomputes the bid due time.** `publish_solicitation` accepts only `solicitations/{id}/v1/rfb.pdf` and `.../bid-form.pdf` for that row, and recomputes `bid_due_at` from the bid due date and time in the configured time zone. A caller value that differs is rejected, so a disagreement between the app and the database shows up instead of being silently replaced. Uploads to the `published` bucket are limited to office staff, versioned solicitation paths, and solicitations that are approved.
- **The same-person rule spans reassignment.** Nobody who was a reviewer in the current review round can check it. A round starts at the latest submission or reopen, and the round's reviewers are read from the audit log.

### Known gaps

- **Invite links are verified by a GET to `/auth/confirm`.** The token is spent the moment the link is opened, so an email security scanner that follows links could use up an invitation before the person clicks it. The fix, if that happens, is a confirm page with a button that does the verification on POST. Opening any invite link also signs out whoever was signed in in that browser.
- **An expired invitation cannot be re-sent, and there is no password reset.** Invite links expire after an hour (`otp_expiry`). Inviting the same address again returns the existing auth user, which already has a profile, so `/admin/users` refuses it. Until there is a re-send action and a forgot-password flow, the fix is to delete the auth user in Studio and invite again.
- **Public visibility of released rows is verified only by database tests.** A published row stays hidden from signed-out visitors until its release date, which must be at least three days after submission. End to end, that could only be checked by waiting or by backdating timestamps, and neither was done. The pgTAP tests in `supabase/tests/rls.test.sql` cover signed-out access to released and unreleased rows and files.

## 2026-11-17 — Decided for the bid-submission slice

- **Self-signup is allowed.** Users can create their own accounts. The design said staff don't self-sign up, so a self-signed-up account belongs to a bidder. It gets no agency or office role, and only an admin can grant one. Slice 2a turned it on in `supabase/config.toml` together with bidder registration.
- **Addenda are in scope.** Changes to a published solicitation go through addenda. Each addendum increases the solicitation's version, as the setup design already anticipated. Bidders acknowledge every addendum on the bid form, and a missing acknowledgment means the bid is accepted but flagged for the agency, as the procurement office confirmed. Published versions themselves are never edited.

## 2026-11-18 — Slice 2a, as built

Bidder registration, sealed bid submission and opening. Design: `docs/superpowers/specs/2026-11-17-bid-submission-design.md`. Rulings that changed behaviour from the plan:

- **Bidder roles.** Bidder is an organization kind. Solicitation inserts and updates are agency-only, and office staff profiles are hidden from bidders.
- **Sealing.** The bid tables are sealed from every API role, `service_role` included, by revoke and by policy. Reads go through definer functions that check the database clock.
- **Accepted limit (ruling 3).** The Supabase service key can read, replace or delete sealed bid files, can read their `storage.objects.owner` and `created_at` (which bidder user uploaded which file, and when), and can make the `bid-files` bucket public, because Storage owns that grant and a migration cannot revoke it. Bid prices stay sealed from it. App code never uses that key for bid files. A superuser can still read bids; encryption until close (approach 2) is deferred hardening.
- **Tamper evidence (ruling 5).** Submit records each file's size, eTag and object id from `storage.objects`. Opening compares them with the live object and flags files that are missing or changed. It catches changes made through the Storage API, not writes made directly to the backing object store.
- **Originals deadline.** An original counts only if it was received and logged by the bid due time. A void counts whenever it is made. An original for an older version counts for nothing.
- **Non-responsive status.** It is derived at opening, never stored. The first read after close writes a `bid_close_determination` row to `bid_audit_log`, and later reads write another only if the result changes. Withdrawn bids are never opened. `bid_audit_log` is separate from `audit_log` so the slice 1 history keeps its shape and sealed-bid events have their own access rules.
- **Ruling 8, deadline on the database clock.** Writers re-check `clock_timestamp() < bid_due_at` after taking the bid lock, so a submit or withdraw that straddles the deadline is refused with `bids_closed`. The plan's earlier "never `clock_timestamp()`" wording is amended.
- **Bid bond.** Judged by the bidder's choice (electronic needs the file, paper does not). A paper bond's receipt is shown to the office, not enforced. The cure is 2b.
- **Names.** Bid reference `XXXX-XXXX`; `bid_drafts.version` is the version the draft will become (submit checks it is latest + 1). Seeded solicitation 27-0002 closes about 20 minutes after `db:reset`, so the opening can be tried locally.
- **Bidder-org guard (final review).** Only `register_bidder` can put a profile into a bidder org: a trigger on `profiles` refuses it otherwise, for `service_role` and admins too. Admins can't create or rename bidder orgs, and the invite page offers agencies and offices only.
- **As-submitted names (final review).** Each submitted version records the bidder's legal name; the tabulation shows that, not the live organization name.
- **Originals log clock (final review).** Logging an original locks the bid row (conflicting with opening's lock) and stamps `logged_at` with the database clock after the lock, so a log whose transaction straddles the due time doesn't count.
- **Late submits are the bidder's risk (Drew, 2026-11-18).** An original counts only if it is logged by the bid due time, and it can only be logged once its version exists. A bidder who submits a new version just before close may leave no time to log that version's original, and the bid is then non-responsive. The office keeps all mailed originals on file regardless. There is no logging after close.
- **Withdrawn bidders stay visible to the office after close (Drew, 2026-11-18).** The bid audit log shows who withdrew and when. Withdrawn bids are still never opened: they have no prices or files in the tabulation.

### Known gaps

- **A real two-session race is not tested.** The opening lock is pinned by source checks; the clock re-checks are covered by single-transaction fixtures. There is no two-connection test yet.
- **The first office view after close writes the close-determination audit row.** Nothing writes it at the due time itself; if no one opens the tabulation, no row exists yet.
- **No committed browser test.** The walk-through was a one-off scripted Playwright run; nothing in the repo repeats it.
- **Orphan uploaded objects stay.** A file uploaded and then removed or abandoned leaves its object in Storage until a cleanup job exists.
- **The bidder home's open list uses the server clock.** The solicitation page asks the database; the list does not.
- **Email confirmation is off locally.** It must be on before hosting.

## 2026-11-18 — Look and feel, as built

A visual pass over every page. Behaviour, server logic, generated PDFs and test strings did not change. Specs and plans: `docs/superpowers/`.

- **Direction.** Soft gray page, white cards, one blue accent, tinted pill badges, Inter (via `next/font/google`, system-ui fallback). Plain CSS, no new dependencies. No dark mode (a spec non-goal).
- **Tokens.** `src/styles/tokens.css`: colours (page, surface, border, text, accent, focus, disabled, and a background/text pair per tone: success, danger, warning, neutral, info), spacing, radii, shadow, type scale and weights, content width. `src/styles/contrast.test.ts` checks every text/background pairing for WCAG AA, the focus ring (3:1 against surface and page) and the disabled pair.
- **Components.** `src/components/ui/`: `AppShell` and `AppNav`, `PageHeader` and `Page`, `Card`, `Button` (variants primary, secondary, danger, link; `type` is required), `Field`, `FieldGrid`, `Choice` and `MoneyInput`, `Table` (`Th`, `Td`, `EmptyState`; wide tables scroll horizontally), `StatusBadge` (domain status to tone and label in `status.ts`), `Notice`, `Money` and `DateTime`. Component rules are in `src/styles/components.css`; element defaults and the global focus ring are in `src/app/globals.css`.
- **Nav.** Computed on the server by `navFor` (`nav.ts`) and mirrored to the page guards, so a role is never shown a link it cannot use. A link gets `aria-current="page"` on an exact path match and `aria-current="true"` when the current page is nested under it (a section match); hash links are never marked. The Mine/All segment on `/office` uses `aria-current="true"`.

  | Session | Links |
  |---|---|
  | Signed out (and a signed-in user with no profile) | Solicitations, Sign in |
  | Bidder | My bids (`/bidder#my-bids`), Open solicitations |
  | Agency | My solicitations |
  | Office | Review queue, Published (`/office#published`) |
  | Admin (added to the role's links) | Users, Organizations, Clauses, Holidays, Settings |

- **Two copy decisions.** (1) Solicitation states are shown as badge labels ("In review", "In check") rather than the raw state value. (2) Receipt-status badges show the status text without the parentheses the old markup added, for example "current" or "withdrawn Nov 18, 2026, 11:00 AM". The badge's tone comes from the receipt's state (withdrawn, current or superseded), not from the label text.
- **Other record copy changes.** Two badges lost their parentheses: "after the bid due time" and "missing since submission". The "·" between Mine and All on the office queue and the " - " separators on the admin home were dropped.
- **Allowed inline styles.** Only the two preview iframes in `ReviewPanel.tsx` (fixed width and height). `src/documents/templates/RfbSections.tsx` has one `style` in the PDF template, which is out of scope.
- **State is never hidden by styling.** Disabled and read-only controls get the disabled fill and text and `not-allowed`; the sealed notice stays a warning `Notice`; "Non-responsive" stays a danger badge followed by the database reason; file flags keep `role="alert"`.

### Known gaps

- **Set-password is not screenshotted.** It is reached only from an invite email link.
- **Unregistered users see the signed-out nav.** A signed-in account with no profile has a null session context, so it gets Solicitations and Sign in and no sign-out link.
- **No admin overview link** in the nav; admins reach their pages through the five admin links.
- **No dark mode.** The spec excluded it.

## 2026-11-19 — Bid bond may be cured after submit (Drew)

A bidder may submit a bid whose bond choice is "electronic" with no bid bond file. At close that bid's bond counts as missing and enters the cure: the bidder has until 5 p.m. the next business day to upload it, or the bid is non-responsive ("bid bond not received by the cure deadline"). The bond choice itself stays required wherever a bond is required, and printing the bid form for signature still needs the choice and the apprentice answer. The bidder form shows the bond slot but no longer marks it required; the office tabulation says "Electronic bond (not uploaded)" until a sealed bond file exists.

## 2026-11-19 — Slice 2b, as built

Bid review, the bond cure, the recap and the award, from close to a posted award. Design: `docs/superpowers/specs/2026-11-19-bid-review-award-design.md`; plan: `docs/superpowers/plans/2026-11-19-bid-review-award.md`.

- **Stored stages versus displayed ones.** `public.evaluation_stage` stores `bid_review`, `recap_check`, `recap_posted`, `award_check`, `awarded` and `all_rejected`, one `evaluations` row per solicitation, created at the first office read after close. The spec's "awaiting agency" is displayed, not stored: `bid_review` with `flags_released_at` set and a bid still `flagged`. Its "award pending" is `recap_posted`. So the office can change outcomes until it sends the recap to check, and the agency's state never needs a transition back. Every stage change goes through a definer function that writes one audit row.
- **One SQL source for the recap.** `app.rank_recap` computes every recap figure from the sealed `bid_versions` cents, the published estimate and alternates, and the confidential funding amount. Nobody types a number. The office preview, the snapshot sent to check, the posted `recaps` row and the award all come from it; TypeScript only formats the frozen snapshot. Posting rebuilds the recap and refuses with `recap_stale` if it no longer matches the draft that was checked.
- **The recap algorithm (0021, after the Ruling 9 fix).** All arithmetic is exact integers.
  - For a bid *b* and a set *S* of selected alternates, the actual price is *T(b,S)* = base + the selected additive alternates − the selected deductive ones. The evaluated price is *E(b,S)* = *T* × 99 when the bid commits apprentices on a $1M+ job (estimate ≥ $1,000,000), else *T* × 100, in hundredths of a cent. The displayed evaluated price is *E* rounded half up to cents.
  - **Memo first.** If every accepted bid's total with all deductive alternates taken exceeds funding, the result is the "all bids rejected" memo (reason `over_funding`); with no deductives this is the spec's "every base total exceeds funding". Zero accepted bids give the memo with reason `no_accepted_bids`.
  - **Alternate selection** (one set for every bid). "Fits" means the bid(s) with the lowest *E* under *S* (no resident preference) have *T* ≤ funding. Start with no alternates. Only if that doesn't fit, take deductive alternates in listed order until it fits. Then, if it fits, take additive alternates in listed order while the next one still fits, stopping at the first that doesn't. Deductives are never taken when the base already fits. If it still doesn't fit after every deductive (the apprentice credit made an over-funding bid the lowest), *S* stays at all deductives, no additive is taken, and the recap carries a `winnerOverFunding` warning.
  - A negative total, in the memo check or the final *S*, is `invalid_data`.
  - **Ranking.** *N* is the lowest *E* among non-resident bids. A resident bid whose resident certificate the office verified is preferred when *E* × 100 ≤ *N* × 105 (within 5%, inclusive). Bids sort by (preferred first, then *E*); rank is 1 + the number of strictly smaller keys (1, 1, 3). Bids with the same key are tied. The expected winner is the sole rank-1 bid; a tie at rank 1 has none and goes to the agency.
- **Cure counting.** A bond cure is due when bonds are required and, at close, an electronic choice has no sealed bond file or a paper bond's original was not received and logged by the bid due time. The deadline is 17:00 local on the next business day (weekends and `holidays` skipped), frozen when the evaluation row is created. An uploaded bond counts only with `uploaded_at < deadline` (the upload is refused at or after it). A logged paper bond counts with `received_at <= deadline` and `logged_at <= deadline`, the same `<=` rule as 2a originals. A bid still uncured at the deadline is non-responsive, "bid bond not received by the cure deadline", automatically; nobody can change it.
- **The bidder sees its outcome only after posting.** Outcomes can change until send-to-check, so a bidder sees its own outcome only once the recap or memo is posted. Its cure status is shown live from close.
- **The agency's flagged view is minimal.** For each bid the office flagged, the agency sees the reference, the reviewer's note, the base total and the current decision. It does not see the bidder's name, which the decision doesn't need. A rejected flagged bid is left out of the recap.
- **Two-person check.** Posting the recap, the memo and the award needs a different office user from the one who prepared it. The fallback (`post_*_alone`) is stamped `single_reviewer` and audited as "no second reviewer available". Posting is irreversible, so every post (recap, memo, award, and each "post alone") asks for confirmation first. Buttons a user can never use (the sender or a past reviewer checking the recap, the sender checking the award) are disabled with the reason.
- **Originals and cure frozen after bid review (Ruling 14).** After close, voiding or logging an original and uploading a cure bond are allowed only while the evaluation is in `bid_review`. Each takes the bid row lock and then the evaluation lock (the same order as `review_bids`), so a posted recap or award can't be contradicted by a later void or a reopened cure. Before close nothing changes. A void made after close counts as reviewing the bids for the recap's same-person rule.

### Rulings made during the build

Rulings 2–14 changed or refined the plan. Ruling 1 accepted the planner's resolutions as written.

2. **Funding amount stays confidential until posting.** It moves out of the public data at publish into `solicitation_funding` (agency and office only). Public pages and bidders see it only in the posted recap.
3. **Cure deadline frozen at close.** It is computed when the evaluation row is created; later holiday edits don't move it.
4. **Alternates follow common practice.** Deductives are taken only to get the lowest bid within funding, then additives while it still fits. One set applies to every bid.
5. **An expected winner over funding is a warning, not a block.** The agency decides.
6. **The printed bid form needs the bond choice and the apprentice answer**, so the signed original matches what will be sealed.
7. **A bid may be submitted without its electronic bond file (Drew).** It enters the cure at close.
8. **The agency can't read the unposted recap.** `evaluations` has a column-level grant; the draft is read only through office definer functions.
9. **The memo means every bid is over funding** even with all deductives taken; otherwise it's a recap, with the over-funding warning when needed. (Revised from a first version that issued the memo when only the lowest evaluated bid was over.)
10. **Irreversible posts ask for confirmation** ("This makes ... public and can't be undone."): Post recap, Post memo, Post award and each "Post alone".
11. **An objecting checker can't be bypassed.** After a disagree on the award, sending it to check again or posting it alone needs a newer agency pick.
12. **No two-user deadlock on the award.** The same-person rule applies to the current round's sender only, so the person who disagreed can send round two and the first sender can check it. The recap keeps the stricter rule (no reviewer of the bids may check), with the recorded fallback.
13. **Recall.** The sender can recall from `recap_check` (back to `bid_review`, draft cleared) or `award_check` (back to `recap_posted`, the pick kept and no disagreement recorded), so an office that has no eligible checker is never stuck; the recorded fallback then applies. `recall_recap` and `recall_award` are sender-only and audited.
14. **No changes behind a frozen recap.** After close, `void_bid_original`, `log_bid_original` and the bond cure upload work only in `bid_review`. To correct an original once the recap is under check, recall it (or have the checker send it back) first.

### Known gaps

- **The expected winner can exceed funding** under the resident preference or the apprentice credit. It is shown as a warning, not blocked.
- **No warning when tied rank-1 bids are over funding.** `winnerOverFunding` is set only for a sole expected winner. An exact evaluated tie at rank 1 that is also over funding (after every deductive) shows no warning; the table still shows each total and the funding amount, and the agency picks.
- **No two-session race test for the evaluation lock.** The lock is pinned by single-transaction fixtures only.
- **A bid bond may be cured after submit (Ruling 7).** A bidder can submit an electronic bond choice with no file and rely on the cure, so the cure is part of the normal path, not only for a lost paper bond.
- **Award check rounds (Rulings 11–12)** depend on timestamp ordering (a pick newer than the latest disagree) rather than a stored link to the disputed pick.
- **The recap fallback after a disagree is allowed and recorded.** A reviewer whose recap was sent back can post it alone as "no second reviewer available"; it is stamped and audited, not blocked.
- **`recap_stale` is now a backstop only.** Since Ruling 14 no API path changes a bid's status after the recap is sent to check, so `post_recap`'s staleness check guards against future paths rather than a known race.
- **The memo is blocked by an unverified resident claim** even though residency can't change a memo. Verifying the claim (one action) clears it.
- **Seeded solicitations have no PDFs** until `npm run seed:docs` runs (2026-11-22: it renders every seeded version's RFB, bid form and addendum with the app's renderers and uploads them; `npm run hosted:reset` runs it).
- **The posted `recaps` and `awards` rows include office user ids** (`prepared_by`, `checked_by`) readable by anyone; the public page shows only the snapshot.

## 2026-11-20 — Slice 2c, as built

Addenda, acknowledgments and the Q&A board. Design: `docs/superpowers/specs/2026-11-20-addenda-qa-design.md`; plan: `docs/superpowers/plans/2026-11-20-addenda-qa.md`.

- **Versions.** Each publish adds one append-only `solicitation_versions` row. Version 1 is the original publish and version *n* is Addendum *n* − 1, with its files under `solicitations/{id}/v{n}/` (`rfb.pdf`, `bid-form.pdf`, `addendum.pdf`, `attachments/…`). `publish_addendum` refuses (`invalid_paths`) unless every one of those files is in the published bucket, and holds a share lock on them until it commits, so a concurrent attempt's cleanup can't remove them from under a publish. The `solicitations` row keeps the current pointer (`version`, `published_snapshot`, `data`, `bid_due_at`, `rfb_path`, `bid_form_path`), so every 2a/2b reader works unchanged. Only `publish_addendum` may move those columns of a published row, and only while it holds the transaction-local `app.publishing_addendum` setting, which it clears straight after the update. Nothing else on a published row ever changes.
- **States.** `public.addendum_state` is `draft`, `submitted`, `in_review`, `in_check`, `approved`, `published`, `withdrawn`. "Returned" is back to `draft` with a `return` comment, as in slice 1. After close an unpublished addendum is shown as withdrawn (`app.addendum_effective_state`, derived, not written by a job), and the one-at-a-time guard ignores it.
- **Numbers have no gaps.** A new addendum takes (published addenda) + 1, and a withdrawn addendum's number is reused (a unique index on live numbers only).
- **One addendum at a time, while bids are open.** Starting, saving, submitting and reviewing an addendum need bidding open (released and not yet closed), judged on the database clock after the lock. Publishing needs only that bids haven't closed. There are no addenda after close.
- **No addendum before the release date.** A published solicitation that hasn't reached its release date can't be corrected by addendum until release day, because the addendum functions use the same bidding-open check as bid writers. Widening that window is a later choice.
- **Locked fields.** An addendum can't change `releaseDate`, `adStart`, `adEnd`, `newspapers` or `category`, and clause locks are never re-locked. Clauses stay at the versions locked at version 1. The addendum validator skips the release-date rule and does not check that the ad ends before bids are due: `adEnd` is locked and already past for any released solicitation, and the 5-day rule bounds the due date.
- **The 5-day rule (Drew).** Every addendum's resulting bid due time must be at least `clock_timestamp()` + 5 days at publish, or publish raises `too_close`. Exactly 5 days is allowed. An addendum published with fewer than 5 days left must also move the due date out.
- **Two-person check, as in slice 1.** The reviewer can't be the checker (`same_person`, round-scoped). The fallback, `approve_addendum_alone`, runs from `in_review` like slice 1's approve-alone, stamps `single_reviewer` and records "no second reviewer available". Only the reviewer or the checker can reopen an approved addendum.
- **The office doesn't edit addendum data.** It returns the addendum to the agency with comments. An addendum is short, and slice 1's office edit existed for typos.
- **The editor has no addendum preview.** The addendum PDF is rendered at publish. Validator warnings don't block an addendum.
- **Publishing.** The office renders the new RFB, bid form and addendum PDF, uploads them to `v{n}`, copies the attachments next to them, then calls `publish_addendum`. Files in an unpublished `v{n}` folder are not publicly readable. While no version *n* row exists, the office may delete objects there, so publish first clears any leftovers from a crashed attempt, and a failed publish cleans up after itself. The agency may read its attachments-bucket files while its addendum is a draft (the same window in which it may write them); after publish the copies are read from the published bucket.
- **Funding.** An addendum carries the confidential funding amount in its staff-only `data`. Publishing freezes it per version in the append-only `solicitation_funding_changes`, never in the public snapshot. `app.funding_cents` prefers the highest version, then `solicitation_funding`, then the estimate. `app.funding_from_estimate` is false once any amount has been frozen.
- **Schedule changes and resubmit required (Drew, option A).** An addendum that changes the items or alternates marks every bid submitted against an older version as resubmit required. The stale submission stays sealed and never counts: it is left out of `opened_bids` and the review, its original doesn't count, and at close it gets one `bid_close_determination` row in `bid_audit_log` with `{"version": v, "reason": "resubmit_required"}`. The office lists such bids with `public.stale_bids`. A bid submitted before an addendum that doesn't change the schedule stays submitted and counts; the bidder may replace it to add the acknowledgment.
- **Drafts are reset at publish, not on read.** When the schedule changes, `publish_addendum` clears every draft's prices for that solicitation and moves the draft to the new version. `replace_bid` always starts the new draft with empty prices, and `submit_bid` refuses a draft priced against an old schedule with `stale_draft`. Bid writers take a share lock on the solicitation before the bid lock, so a submit and a publish can't deadlock, and the wall-clock check still follows the bid lock. A price save from a page loaded before an addendum sends the version the page loaded, and is refused with the prices-cleared notice when the draft has moved on.
- **Opening waits for an in-flight publish.** The opening gate and the evaluation lock take a share lock on the solicitation before judging that bids have closed. A publish that straddles the old due time holds the row, so opening waits, reads the new due time and stays sealed.
- **Stale originals are flagged.** Before close, the office's bid index shows a version priced against a changed schedule as "Resubmit required (not counted)", so a mailed original for it is visibly worth nothing. Withdrawn still wins.
- **The resubmit banner keys on resubmit required only.** A withdrawn stale version doesn't show it.
- **Acknowledgments are a separate online action (Drew).** A bidder acknowledges an addendum on the bid page whether or not its bid is submitted. It is not a new bid version and needs no new mailed original. Acknowledgments are append-only. The bidder reads its own, office staff read them only at or after close, and the agency and the public never do. An acknowledgment recorded before close always counts, and one at close raises `bids_closed`. Another bidder's bid id gives `not_found`, so a bid's existence doesn't leak.
- **Missing acknowledgments are flagged at review, not blocked at submit.** `set_bid_outcome` refuses `accepted` for a bid missing an acknowledgment (`ack_missing`, checked last), and prepends the fixed note "Did not acknowledge Addendum {n}[, {m}…]." to a flagged outcome when it's absent. The review page preselects "flagged" with the note. No outcome row is written automatically, because a flagged decision needs a real outcome row. At submit the bidder only sees the warning "Bids that don't acknowledge every addendum are flagged for the agency at close."; the database never blocks the submit, so there is no SQL-side warning list. The printed bid form lists the acknowledged addenda.
- **The Q&A board is anonymous until the addendum (Drew).** `public.question_status` is `open`, `answered`, `closed`; `public.question_close_reason` is `duplicate`, `out_of_scope`. A question's body and status are readable by the asker's organization (through `my_questions`), and everything by office staff. The agency reads questions through `agency_questions`, which has no identity columns. The public sees only the agency's published question and answer, and only for published addenda. `ask_question` writes its audit row with no actor and only the question id, so the agency, which can read its audit log, can't link an asker; anonymity outranks a complete audit actor here. The office still knows the asker from `questions.asked_by`.
- **The questions deadline moves with an addendum.** `ask_question` judges `questionsDue` from the current published snapshot, in `settings.timezone`. A question is answered in at most one published addendum; a withdrawn addendum's answers are ignored and its questions stay open. The ask form is shown or hidden on the server clock; the database enforces the deadline.
- **The public page lists every version** with its documents, and the published answers. The versions card appears only when there is more than one version.
- **The bid form footer keeps its form**, "Solicitation {n} · Version {v} · Page X of Y".
- **Fixed copy.** "Resubmit required: Addendum {n} changed the bid schedule.", "Addendum {n} published. Acknowledge it before bids close." and "Addendum {n} changed the bid schedule, so your prices were cleared. Enter them again." Publishing or withdrawing an addendum, closing a question and acknowledging an addendum each ask for confirmation.
- **Schema rules.** New SQL lives only in new migrations (0026–0035), and a replaced function starts from its latest definition in any earlier migration. SQL files are stored with LF line endings (`.gitattributes`), because clause text is compared byte for byte. The pgTAP helper `tests.make_published_solicitation` creates no version row, so a test that needs one inserts it or publishes through `publish_solicitation`. In the seed, the version 1 backfill runs before any addendum moves a solicitation's pointer.

### Known gaps

- **A printed original from before a schedule change.** A draft reset by an addendum keeps its bid version number, so an original printed and mailed before the reset shares its reference and version with the re-priced submission. The bid form footer shows the solicitation version, so the mismatch is visible, and 2b's rule (a mailed form that doesn't match the portal entry is accepted and flagged) covers it.
- **The snapshot's data isn't compared with the addendum's.** `publish_addendum` computes the schedule change from the addendum's data and trusts the caller's snapshot to match it.
- **A stale price save in a race** gets `stale_draft` without the stale flag, so the page doesn't refresh or show the prices-cleared notice until it is reloaded.
- **An addendum holding an answer to a question that is no longer open can't be published** (`question_not_open`). No current path reaches this; withdrawing the addendum recovers.
- **Same-organization colleagues can read `questions.asked_by`** through RLS. The UI reads only through `my_questions`.
- **The narrative autosave timer isn't re-armed while the text is dirty**, so leaving the page within 5 seconds of typing can lose the last edit.
- **Switching a flagged bid to non-responsive keeps the automatic acknowledgment note** in the note field; the reviewer edits it.
- **The office addendum panel remounts after each action**, so the success message in the live region is lost (the same pattern as the slice 1 office page).
- **Seeded addenda get their PDFs from `npm run seed:docs`**, like the other seeded documents (SQL can't upload file bytes). Seeded solicitations have no attachments either, so the 27-0001 draft addendum needs its required attachments added before it can be submitted.

## 2026-11-22 — Slice 3, the advisory AI document check, as built

Design: `docs/superpowers/specs/2026-11-21-ai-document-check-design.md`. Drew decided: advisory only, met / not met / unclear with evidence and no confidence scores, the office scans each signed original after close, OpenAI with Drew's key, office-only trigger with caps and a kill switch, recorded results for seeded bids, and a planted-defect evaluation.

- **Who and when.** Only office staff can scan, run, record or review a check, and only after close. Every function raises `sealed` before close, and opening-style reads take a share lock on the solicitation. The agency, bidders and the public never see results, recorded ones included, because bid documents stay confidential after close.
- **Advisory, enforced.** No check function writes outcomes, flagged decisions, recaps or awards (a pgTAP assertion reads their bodies). The panel has no outcome buttons.
- **Addenda on the form.** The model is asked for the addendum numbers only. The rule also drops dates and expands ranges ("1 through 3"), because real acknowledgment lines usually carry dates.
- **Who decides each item.** The checklist is fixed per document kind. The model judges "ai" items. For "rule" items (amount in words, addenda listed, form version, resident certificate, names, obligee, coverage dates) it only extracts the value, and TypeScript compares it with the portal. A missing or unreadable value is "unclear", never "met".
- **One call per document,** made from a server action the browser calls in turn, so no request handles a whole bid. The PDF goes to the OpenAI Responses API as a file input with a strict JSON schema of exactly that kind's item codes. The instructions treat the document as untrusted bidder material; the real guard is the schema plus the advisory role, since the reviewer sees the page and excerpt.
- **Model.** The default is `gpt-6.2-astra`, the model OpenAI's file-input docs used on 2026-11-21; `OPENAI_MODEL` overrides it. No temperature is set, because not every current model accepts one.
- **Caps and runs.** 3 runs per bid (recorded runs don't count), 50 document checks per office user per day and 200 in total, in `settings`. A document with no file ("Scan not attached") costs nothing.
- **Reserve before the paid call.** The app calls `begin_ai_check_document` before it downloads a document or calls the model. The database checks run ownership, that the document is one of the run's own bid's documents, that it hasn't already been checked in this run, and the daily caps, and only then reserves the call. Items can be recorded only for a reserved document, and the facts come from the run's bid, never from ids the browser sends. The server action also refuses outright while checks are turned off or no key is configured. (Found by the final review: the first version checked these only after the call was paid for.)
- **Retrying one document.** A failed model call is recorded as unclear items with the error class. The run stays open, and the reviewer can check the failed documents again (each retry is a new reserved call) or finish the run. The panel shows each item's latest result. The OpenAI client makes no retries of its own, so a timeout is never billed twice. One run can be running per bid; a run older than 10 minutes counts as failed. A new run starts unreviewed; earlier runs and their reviews stay in the history.
- **Integrity of writes.** Office staff are trusted to store what the model returned. The database checks the structure: only the run's starter can add items, only to a running run, only with item codes of that document kind, and `recorded` has no API path.
- **Scans** are stored in the sealed `bid-files` bucket at `bids/{bid}/{log entry}/scan-….pdf` (the shape the existing storage helpers parse). The browser checks PDF type, 20 MB and 30 pages before upload; the database checks the size again. A new scan supersedes the old one, which is kept.
- **Seeds.** 27-0003's four bids carry uploaded insurance certificates (with each fixture's real size and MD5, so the opening's tamper check stays clean after `seed:files`), scans and one recorded run each. Basalt's planted finding is an addendum it lists, not a missing surety signature: its paper bond was never logged, so its bond items read "Scan not attached". The missing-signature case is in the evaluation-only documents.

### Known gaps

- **The live evaluation hasn't been run.** It needs Drew's key; the fixtures, scoring and report are in place.
- **A modified browser could attach a scan over 30 pages.** The database checks only the size; the cost is model tokens, still inside the daily caps (enforced before each call).
- **Smaller items from the final review are not done:** the amount-in-words parser returns "unclear" for "No/100" and en-dashes; a page number of 0 from the model makes that document's items unclear; the form-version rule takes the first number after "v"; and the agency name falls back to blank if it can't be read, which would show the obligee as not met.
- **The scan-upload screens were checked by build and a browser walk on seeded data only;** no live AI run has been made through the screens.

## Open questions

See `docs/discovery.md` §3.
