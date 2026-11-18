# Slice 2a: bidder registration, sealed bid submission and opening

Status: Approved by Drew, 2026-11-17 (builder check skipped at his direction).

## Intent

The structured price schedule is Proclaro's strongest evidence-backed feature. In the real procurement package, prices were transcribed by hand, and a wrong total reached the published recap and award. Slice 2a captures bid prices as structured data at the source, keeps every bid sealed until the deadline, and at close produces an internal tabulation computed from those prices. Nobody retypes a number.

Slice 2 is split into three parts, agreed with Drew on 2026-11-17:
- **2a (this design):** register, submit, seal, open.
- **2b:** review outcomes, the bid-bond cure, the recap and the award.
- **2c:** addenda.

## Goals

- **Registration.** Bidders create their own accounts and register a bidder company.
- **Bidding.** A bidder prepares a bid against a published, open solicitation: prices, required uploads and the bid bond. They print a pre-filled bid form, sign it and mail it, then submit.
- **Sealing.** Bids are sealed from everyone, including the bidder, until the bid due time. The database enforces this.
- **Replacing.** Before close, a bidder can replace a submitted bid. The latest version counts.
- **Paper originals.** The office logs the arrival of mailed signed forms and paper bid bonds, each with a timestamp and the bid version it belongs to.
- **Close.** Close is automatic at the bid due time. There is no override. At close:
  - a bid whose signed original for its latest version was not logged by the deadline is non-responsive, with the reason recorded;
  - the office sees an internal tabulation with each bid's base total and alternates, computed from the portal prices.

## Non-goals (later slices)

- **2b, review and award:**
  - review outcomes (accepted, accepted and flagged, non-responsive for other grounds);
  - comparing the mailed form with the portal entry;
  - the bid-bond cure deadline;
  - verifying resident status and applying the 5% preference and the apprentice credit;
  - the recap and its two-person check;
  - posting, the award and the "all bids rejected" memo;
  - ties.
- **2c, addenda and Q&A:** addenda and their acknowledgments on the bid form, and Q&A.
- **Later or out of v1:**
  - the subcontractor list due within 24 hours of opening;
  - the 30-day no-withdrawal rule after opening;
  - substitution requests;
  - the plan holders list;
  - the AI document check;
  - everything after award.
- **UI polish.** Drew will restyle once the functionality is done.

## Anti-goals

- Anyone (office, admin, agency, AI, or the bidder) seeing submitted bid contents before close.
- Any path that extends a deadline or accepts a late original.
- A recap or tabulation number that someone typed rather than one computed from the portal entry.
- Real data in the repo. The setting stays the fictional State of Calder.

## Decided by Drew

- **Self-signup is allowed, for bidders.** Staff remain invite-only. A self-signed-up account gets no agency or office role; only an admin can grant one.
- **The signed bid form is mailed, not uploaded, and must match the portal entry.**
- **The signed original must arrive by the bid due time.** If no original is logged by the deadline, the bid is non-responsive.
- **Sealing and drafting:**
  - Before submit, the bid is a draft the bidder can see and edit. The bidder prints the pre-filled form from the draft.
  - Submit seals the bid. The bidder receives a receipt with the time, a bid reference and the version number, but no prices.
  - Replacing creates the next version, which needs a newly signed and mailed form showing that version.
- **Close is automatic, with no manual open step.** The agency author and the public see nothing at close. The posted recap (2b) is the only public disclosure.
- **The seal is enforced by approach 1, time-gated database access.** See Approaches.

## Approaches considered

1. **Time-gated database access (chosen).**
   - How it works:
     - Submitted bids sit in tables that no API role can read directly, including service_role. Their files sit in a storage bucket that anon and authenticated users cannot read before close; service_role can (see the known limit below).
     - Reads go through security-definer functions that check `now() >= bid_due_at`.
     - "Closed" is derived from the clock, not stored, so no scheduled job is needed.
     - This is the same enforcement model as slice 1.
   - Known limit: a Postgres superuser with direct database access can still read bids. The service-role key can also read, replace or delete sealed bid files in Storage, read their metadata (`storage.objects.owner` and `created_at`: who uploaded which file for which bid, and when), and update the `bid-files` bucket row (for example make it public), because Supabase's storage admin grants it access and migrations can't revoke that; bid prices in tables stay sealed from it, and app code never touches bid files with the admin client.
2. **Encrypt bid contents until close.**
   - Stronger: even a DB admin sees only ciphertext.
   - Costs: key management, encrypted uploads, and a scheduled key release at close.
   - Deferred as hardening for hosting.
3. **Enforce the seal in app code only.**
   - Rejected: anyone holding the API key and a session could query the tables directly. That contradicts slice 1's rule that guarantees live in the database.

## Design

### Registration
- **Self-signup is on** (`supabase/config.toml`).
- **First sign-in:** a signed-in user with no profile is taken to "Register your company". They enter:
  - legal name, address, contact name, phone and email;
  - an optional resident-bidder claim with a certificate number.
- **What registration creates:** an organization of kind `bidder` and a profile with role bidder. Agency and office access is still granted only by admin invite.
- **Home path:** a bidder's home path is `/bidder`.

### The bid
- A bid belongs to one bidder organization and one published solicitation. There is at most one active bid per pair; replacements are versions of it.
- **Contents**, driven by the solicitation snapshot:
  - **Prices:** a price in integer cents for every bid-schedule line item and alternate, in the order shown on the bid form.
  - **Required bid sections:** an upload for each section the solicitation requires, such as qualifications and references.
  - **Bid bond, when required (estimate ≥ $150K):** either an uploaded electronic surety bond, or "paper original mailed".
- **Lifecycle:**
  1. Draft, visible to the bidder only.
  2. Submit, which creates a sealed version n.
  3. Replace, which starts a new, empty draft. A sealed version cannot be read back, so nothing is prefilled. Submitting it creates version n+1, which supersedes n.
- **Who can bid when:**
  - Bidding is allowed only while the solicitation is published, released and not closed.
  - Submit, replace, withdraw and start are refused at or after `bid_due_at`. The database decides; the client clock does not. Each writer checks the deadline twice, against the transaction start time and again, on the database's own clock, after taking the bid lock, so a call that straddles the deadline is refused.
- **Pre-filled bid form PDF:**
  - Generated from the draft with the slice 1 templates and renderer.
  - Contains the bidder's prices, the bidder's legal name, the bid reference and the version the draft will become when submitted.
  - The footer keeps the slice 1 format.
  - The PDF is not stored as part of the sealed bid; the prices are.

### Paper originals log (office)
- Office staff record mailed items with these fields: bid reference, version, item type (signed bid form or paper bid bond), and a received-at timestamp. The timestamp defaults to now and can't be in the future.
- **Logged before close:** the office can log only the reference and version. Nothing else about the bid is visible.
- **Audit:** log entries are append-only and audited. A correction is a new entry that voids an earlier one, with a reason.

### Close and opening
- **Closed** is computed as `now() >= bid_due_at`.
- **What opens:** on read after close, each solicitation's latest submitted version of every bid becomes readable to office staff.
- **Original-received check:** a bid is computed as non-responsive (reason: "signed original not received by the bid due time") when no signed-form log entry exists for its latest version that was both received (`received_at <= bid_due_at`) and logged (`logged_at <= bid_due_at`) by the bid due time and has not been voided. A void counts whenever it is made. The result is derived on every read, and the determination is audited on the first read after close and again only when the derived result changes. Withdrawn bids are never opened. The bid bond is judged by the bidder's choice: a paper bond's receipt is shown to the office but does not make a bid non-responsive (the cure is 2b).
- **Internal tabulation (office only):** for each bid, the bidder, the base total, each alternate, and the original-received status. Totals are computed from the stored cents, never entered.

### Access rules (enforced in Postgres)

| Who | Before close | After close |
|---|---|---|
| Bidder | Own drafts and receipts (time, reference, version). Never prices or files of submitted versions. | Same (bidder visibility of the result comes in 2b) |
| Office | Reference, version and status only, for logging originals | All submitted bid contents for that solicitation, plus the tabulation |
| Agency author | Nothing | Nothing (2b) |
| Admin (as admin) | Nothing beyond office rights if also office | Same |
| Anon | Nothing | Nothing |

### Audit
Each of these writes an audit row:
- submit
- replace
- withdrawal
- original-log entry
- void
- close-time non-responsive determination

## Added while building
- **Bidder is an organization kind.** Solicitation writes are agency-only, and office staff profiles are hidden from bidders.
- **Tamper evidence for the accepted Storage limit.** Each file's size, eTag and object id are recorded at submit, and opening flags a file that is missing or changed since.

## Left to the builder
- Table and function names and shapes.
- The bid reference format (short, unique, non-guessable, safe to print).
- The storage path layout under a sealed bucket.
- How the close-time non-responsive determination is recorded: stored on first read, or always derived. (Built: always derived, audited on first read and on change.)
- Bidder screens, within the existing look.

## Settled after the first draft (Drew, 2026-11-17)
- **Any registered bidder can bid on any open solicitation.** There is no per-solicitation registration and no plan holders list.
- **A bidder can withdraw a submitted bid before close.** Withdrawal is refused at or after `bid_due_at`. A withdrawn bid is not opened and does not appear in the tabulation. Withdrawing writes an audit row, and the receipt shows the bid as withdrawn. *(My call: a bidder who withdraws can still submit a new version before close. That version needs its own mailed original.)*
