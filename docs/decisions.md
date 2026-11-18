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

## Open questions

See `docs/discovery.md` §3.
