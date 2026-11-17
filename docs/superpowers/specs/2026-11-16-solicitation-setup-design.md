# Solicitation Setup — Design

**Date:** 2026-11-16
**Status:** Approved by Drew, 2026-11-16
**Context:** `docs/decisions.md` (decisions) and `docs/discovery.md` (the real process this is based on)

## 1. Intent

Today a requesting agency fills in the procurement office's Word template for an RFB. The office then checks the whole document by hand before posting it, and agency submissions are very error-prone. Typical problems are missing information, conflicting dates, wrong formatting, math errors and inconsistent structure.

This slice replaces the Word document with structured fields that are validated and then used to **generate** the RFB and its bid form. Errors that come from typing or editing the document can't happen, because nobody edits the document. The office's review focuses on content instead of formatting. Every later part of v1 builds on this structured solicitation: the bid schedule decides what bidders price, the value bands decide which checks apply, and the dates drive the close and the bid-bond cure deadline.

This is the first slice of v1. It's a real system, not a mock-up.

## 2. Goals

1. An agency author creates a construction RFB by filling in structured fields, sees validation errors and warnings as they work, and submits it to the procurement office.
2. The procurement office reviews it, using the field values, the validation results and a preview of the generated PDF. The reviewer either returns it to the agency with comments or passes it to a checker.
3. A second person in the office checks and approves it, or the reviewer uses the recorded one-reviewer fallback.
4. Publishing generates the final RFB PDF, freezes that version, and makes the RFB, its bid form and the attached files available on a public listing.
5. Every state change and every edit after submission is in an audit log.

## 3. Non-goals for this slice

- Bidder accounts, bid submission, sealing, review, the recap and the award. These are later v1 slices.
- Addenda, Q&A, substitution requests and the plan holders list. All changes after publication go through addenda, which is a later slice. This slice must not allow editing a published solicitation.
- AI of any kind. An AI consistency check of the free-text sections is a later candidate.
- RFQs, RFPs and design-build. Only construction RFBs are in scope.
- Solicitations estimated under $50,000 (competitive negotiation). Validation blocks them.
- Bid schedules with unit prices and estimated quantities. v1 supports lump-sum line items and alternates. *(My call: the real example used lump-sum lines per building. Unit-price schedules come later.)*
- Ordering newspaper ads and invoicing agencies. The ad dates are recorded but nothing is sent.
- Editing the document's structure from the UI (see Approaches).

## 4. Anti-goals: failure even if it works

- **A posted document that differs from the validated data.** The generated PDF is the only RFB. There's no download-and-edit path, and no upload to replace the generated RFB.
- **Real data in the repo.** Template wording must be written fresh and generalized: no real agency names, statute numbers, people, addresses or phone numbers, and no pasting from the real template in `source-docs/`. Use a fictional state and agency, configurable in settings.
- **Validation that blocks real work.** Rules the real process treats as hard are errors that block submission. Rules that are only judgment calls are warnings, which the author can acknowledge and the reviewer sees.
- **An agency seeing another agency's drafts.** This is enforced in the database (row-level security), not just in the UI.

## 5. Constraints

- **Stack:** Next.js (TypeScript), Supabase (Postgres, Auth, Storage, row-level security). Decided.
- **Roles** (decided; see `decisions.md`, "Roles adopted"):
  - Agency author, Procurement reviewer, Procurement checker and Admin are used in this slice. The Bidder role is not.
  - The same person can't be both reviewer and checker on one solicitation.
  - The one-reviewer fallback ("no second reviewer available") is stamped on the record and in the audit log.
  - If the checker disagrees, the solicitation goes back to the reviewer.
- **Bond rule** (decided): a bid bond is required when the project estimate is $150,000 or more. It's derived from the estimate and can't be edited. *(The real intake form allows a discretionary bond between $50,000 and $149,999; Proclaro doesn't.)*
- **Time zone:** all deadlines are in the agency's time zone (one configured zone, Mountain Time by default), stored in UTC.
- **Plans and specifications** are large uploaded PDFs (the real ones were around 3.5 MB each), stored in Supabase Storage.

## 6. Approaches considered

**What setup produces:**

| | Option | Trade-off |
|---|---|---|
| **A (chosen)** | Structured fields generate the RFB and the bid form; plans and specs are uploaded | Removes whole classes of errors at the source, and the bid form becomes a system document the rest of v1 relies on. Cost: building the document generation. |
| B | Structured fields, plus the agency's own Word file checked by AI against the fields | Less to build, but it only finds errors instead of preventing them, and the bid form stays whatever the agency made. |
| C | Structured fields only, with documents attached unchecked | Does nothing about the office's main complaint. |

**How the document is generated:**

| | Option | Trade-off |
|---|---|---|
| **1 (chosen)** | HTML templates in code, rendered to PDF by headless Chromium | The conditional logic is code with tests, and the output is locked. Admins edit clause *text* (stored and versioned in the database); changing the *structure* requires a code change. |
| 2 | The office's Word template filled in by a merge library | The office keeps editing in Word, but the logic is hidden in the document, PDF output needs LibreOffice running as a service, and a .docx invites manual edits after generation. |

Drew chose A and 1.

## 7. Decided design

### 7.1 Workflow

```
Draft (agency) ──submit──▶ Submitted ──reviewer picks up──▶ In review
     ▲                                                          │
     └──────────── Returned (with comments) ◀───return──────────┤
                                                                ├──pass to checker──▶ In check ──approve──▶ Approved
                                                                │                        │
                                                                │◀────disagree (comment)─┘
                                                                └──approve alone (fallback, recorded)──▶ Approved
Approved ──publish (reviewer or checker)──▶ Published (frozen)
```

- **Draft:** only the agency can edit. On submit, all errors must be resolved and all warnings acknowledged.
- **Submitted / In review / In check:** the agency can't edit. The reviewer may edit fields and must give a reason, which is logged. *(My call: the office fixes small mistakes today instead of sending everything back.)*
- **Returned:** the solicitation goes back to Draft with comments, which can be attached to specific fields. The agency resubmits.
- **Clause versions are locked when the reviewer sends the solicitation to check** (or approves it alone). The checker reviews exactly the text that will be published. A clause edited by the Admin afterwards doesn't affect it. *(My call.)*
- **Approved → Published:** publishing renders the final PDF from the frozen field values and the locked clause versions, stores the PDF together with a snapshot of all its text, and makes it public. A published solicitation is read-only forever. Changes come through addenda, in a later slice.
- **Release timing:** publishing sets the record to Published right away. It appears on the public listing at the start of the requested release date, so no job runner is needed: the listing filters on release date ≤ now. If the release date has already passed when the reviewer goes to publish, publishing is blocked until the reviewer corrects the dates (an edit with a logged reason) and the date rules pass again with "now" as the earliest release. *(My call.)*
- **The 3-day rule** (release date ≥ submission + 3 days) is measured from the **latest** submission, because that's when the office actually receives what it will review. *(My call.)*
- **Who acts at each stage** *(my calls)*:
  - In the office, "reviewer" and "checker" are assignments on each solicitation, not fixed user roles. Any office staff member can be either, but not both on the same solicitation.
  - Any other staff member can pick up a check; the reviewer doesn't choose one.
  - A solicitation in review can be reassigned to a different reviewer, and this is logged.
  - The checker can't edit. The checker approves or disagrees with a comment.
  - Warnings created by a reviewer's edit are acknowledged by the reviewer.
- **Version:** a published solicitation is version 1. Each addendum (a later slice) increases it. Draft previews carry the "DRAFT" watermark and no version. *(My call.)*
- **Solicitation number:** assigned when the solicitation is first submitted, in the format `YY-NNNN`, where `YY` is the fiscal year (the fiscal year start is configurable, July by default). *(My call: the real office assigns the number at the request stage. Assigning it at first submission avoids numbering drafts that are abandoned.)*

### 7.2 Fields

Grouped as an author would fill them in. Unless marked, a field is required.

- **Identity:** requesting agency (from the user's organization); requester and project manager (name, email, phone); short title (30 characters max); long title; category (Construction / Major Maintenance / Capital Construction); one- or two-sentence summary; project description (text); project location (address, city, county).
- **Money:** estimated cost; funding source (Capital Construction / Major Maintenance / Other + text); federal funds (yes/no).
- **Dates:**
  - Requested release date
  - Advertisement start and end dates, plus the newspapers (text)
  - Questions due (date and time)
  - Answers/addenda due (date and time)
  - Bid due (date; the time defaults to 1:00 p.m.)
  - Optional: tentative award date, estimated start date, estimated completion date
  - Bid validity in days (default 90)
- **Pre-bid meeting:** none / optional / mandatory. If held: format (in person, phone, video), date and time, location or connection details. Optional: facility background-check requirement, with contact and lead time.
- **Bid schedule:** one or more lump-sum line items (name and optional description), plus optional alternates (additive or deductive, with a description). The bid form shows a total line.
- **Bid content:** which sections bidders must submit (see 7.3), with an optional page limit per section. The sections are a **fixed list in code**. Sections required by the value band are locked on, and authors can't add custom sections in v1. Page limits are printed in the RFB and the checklist but aren't checked automatically. *(My call; the later bid-review slice evaluates against this list.)*
- **Author-editable text:** the author writes only these free-text fields: summary, project description, project-specific scope notes (optional) and project-specific special provisions (optional). All other text is Admin-maintained clause text. The placeholder-bracket warning applies to these four fields. *(My call.)*
- **Attachments:** plans, the project manual/specifications (each with an issue date), the sample contract, prevailing wage rates and any additional documents. The "List of attached documents" in the RFB is generated from these.

### 7.3 Value bands: derived from the estimate, not editable

| Estimate | Effect on the generated RFB |
|---|---|
| < $50,000 | **Blocked in v1** (validation error). In the real process these are competitive negotiation, which isn't designed yet. *(Drew's decision.)* |
| ≥ $50,000 | Competitive sealed bidding. Bid form sections 1 and 2, the signature page and proof of insurance are required. Modified bids must not reveal the price. |
| ≥ $100,000 | Prevailing wage clause |
| ≥ $150,000 | Bid bond (10%) and performance and payment bond (100%) clauses; the bond line is included on the bid form |
| ≥ $1,000,000 | Apprentice-credit clause and question on the bid form |
| Federal funds = yes | Federal domestic-content clauses |

Qualifications, references and current work are optional sections the author can choose to require.

### 7.4 Validation

**Errors (block submission):**
- Missing required fields; short title over 30 characters; estimate under $50,000 (competitive negotiation isn't supported in v1); no bid schedule line items.
- Date order: questions due < answers due < bid due.
- Bid due ≥ answers due + 5 calendar days.
- Requested release date ≥ submission date + 3 calendar days.
- Advertisement period is at least 14 calendar days and ends on or before the bid due date.
- A mandatory or optional pre-bid meeting has a date, time and location; it falls after the release date and before questions due.
- All required attachments are present (plans, specifications, sample contract, and prevailing wage when the estimate is ≥ $100,000).

**Warnings (must be acknowledged):**
- Bid due date on a weekend or a configured holiday.
- Mandatory pre-bid meeting less than 7 days after release. *(My call; tunable.)*
- Free-text sections that still contain template placeholder brackets.

The rules are pure functions, run both in the browser (feedback while typing) and on the server (enforced on submit and publish). The server's result is the one that counts.

### 7.5 Generated documents

- **RFB PDF:** cover page, table of contents, notice, special provisions, key dates table, specifications and plans, submission of bids, evaluation and award (including the MET/NOT MET checklist generated from the required sections), bid form instructions, bid form sections 1 and 2, signature page, the selected optional sections, and the list of attached documents.
- **Bid form:** the bid form pages are also produced as a **separate PDF** for bidders to fill in. Every bid form page has a footer with the solicitation number, the solicitation's version and "Page X of Y". The later wrong-form check anchors on this footer.
- **Clause text:** stored in the database as versioned clause records, edited by the Admin. A published solicitation records which clause versions it used, so it can always be regenerated exactly as published.
- **Preview:** the reviewer, the checker and the author can render a draft preview at any time, watermarked "DRAFT — NOT FOR BIDDING".

### 7.6 Public listing

A public page lists published solicitations: number, title, agency, bid due date and status (Open, or Closed after the bid due time). The detail page has the RFB PDF, the bid form PDF and the attachments for download. No login is required. *(Bidder accounts come in a later slice.)*

### 7.7 Access and users

- Users belong to an organization: either an agency or the procurement office. Agency authors see only their own agency's solicitations; office staff see all of them.
- No self-signup for staff. The Admin creates organizations and users and assigns roles. Login is by email (Supabase Auth). *(My call: the login method is the builder's choice within Supabase Auth.)*
- Row-level security enforces: agency isolation, edit rights by state and role, published records read-only, and public read access only for published solicitations and their files.

### 7.8 Audit log

The audit log is append-only. It records every state change, every field edit after submission (old value, new value, reason), every comment, every fallback approval and every publish, each with who did it and when. No role can update or delete entries.

## 8. Left to the builder

- Table design and migrations, provided the constraints above hold.
- The UI component library and layout. Use plain, dense, form-heavy screens suited to office staff.
- How headless Chromium runs (for example Playwright locally, plus a serverless-compatible Chromium build when deployed). The deployment target isn't decided yet, so keep the rendering behind a small interface.
- The fictional state and agency names, and the clause text, written fresh and in plain language, following the structure of the real template.
- The test approach, with this minimum: unit tests for every validation rule and value-band derivation, tests that conditional sections appear or disappear for each band, and tests that the row-level security policies enforce agency isolation and published read-only.
