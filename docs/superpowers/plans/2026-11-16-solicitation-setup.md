# Solicitation Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An agency author creates a construction RFB from structured fields. The procurement office reviews and checks it. Publishing generates a locked RFB PDF and bid form and lists them publicly.

**Architecture:** Next.js App Router (TypeScript) on Supabase.
- Domain rules (value bands, dates, validation) are pure TypeScript modules, shared by the browser and the server.
- Workflow state changes are Postgres functions. Each one checks role and state, changes state atomically and writes the audit entry in the same transaction. Row-level security handles agency isolation and the published read-only rule.
- Documents are React components rendered to HTML on the server, then to PDF by headless Chromium behind a `PdfRenderer` interface.

**Tech Stack:** Next.js 15, React 19, TypeScript, Supabase (Postgres, Auth, Storage; CLI 3.x; `@supabase/ssr`), Zod, date-fns 4 + `@date-fns/tz`, Vitest, pgTAP (`supabase test db`), `playwright-core` + Chromium.

**Spec:** `docs/superpowers/specs/2026-11-16-solicitation-setup-design.md`. Read it before any task. Section references like §7.4 point into it.

## Global Constraints

- **No real data.** No real agency, state, statute, person, address, phone number or amount anywhere in the repo, including clause text, seeds and tests. Never read or copy from `source-docs/`.
  - The fictional setting is "State of Calder" and the "Calder State Construction Office". Both are configurable in `settings`.
- **Money** is stored and computed as integer cents (`number`), never as floats.
- **Deadlines** are entered and shown in the configured time zone (default `America/Denver`) and stored as UTC `timestamptz`. Calendar "today" is always computed in the configured time zone, never the server's.
- **Thresholds** (exact, inclusive lower bounds):
  - Under $50,000.00: blocked.
  - $50,000.00 or more: sealed bidding.
  - $100,000.00 or more: prevailing wage.
  - $150,000.00 or more: bid bond and performance bond.
  - $1,000,000.00 or more: apprentice credit.
- **Date rules** (calendar days):
  - Bid due ≥ answers due + 5 days.
  - Release ≥ latest submission + 3 days.
  - Ad period ≥ 14 days, ending on or before the bid due date.
- **Bid due time defaults to `13:00`.** Bid validity defaults to 90 days.
- **Short title:** 30 characters maximum.
- **Fiscal year starts in July by default.** Solicitation numbers are `YY-NNNN`; `YY` is the fiscal-year end year mod 100, and `NNNN` is a zero-padded per-fiscal-year sequence.
- **A published solicitation is never updated.** No code path writes to a row whose state is `published`.
- **Same-person rule:** a reviewer can never be the checker on the same solicitation, enforced in Postgres.
- **Audit log:** insert only. Revoke `update` and `delete` from every role.
- **Watermark:** draft previews carry `DRAFT — NOT FOR BIDDING` and no version.
- **Bid form footer:** `Solicitation {number} · Version {version} · Page {n} of {total}`.

## Review Focus

1. **Time zone and daylight saving:** a bid due at 13:00 on the Sunday DST changes, or a "today" check run at 18:30 local time (already the next day in UTC), must use the configured zone. Tested in Task 2.
2. **Money entered with commas, dollar signs or exactly at a threshold** (`"$150,000"`, `"150000.00"`) must parse to exact cents and land in the right band. Tested in Tasks 2 and 3.
3. **Two office staff acting on the same solicitation at once** (a checker approving while the reviewer reassigns or disagrees) must not both succeed. Every workflow function updates `where state = <expected>` and raises if no row changed. Tested in Task 6.
4. **Free text containing HTML or ampersands** (`<script>`, `R&D`, `"quotes"`) must be escaped in the generated document. Tested in Task 8.
5. **Large plan uploads** (tens of megabytes) must not go through a Next.js server action, which has a 1 MB body limit. They upload directly from the browser to Storage with a signed upload URL and a 100 MB bucket limit. Verified in Task 10.

---

## File Structure

```
src/domain/money.ts                     parse/format cents
src/domain/time.ts                      zone-aware dates, holidays, fiscal year
src/domain/numbering.ts                 solicitation number formatting
src/domain/solicitation/types.ts        SolicitationData and enums
src/domain/solicitation/schema.ts       Zod schema for SolicitationData
src/domain/solicitation/valueBands.ts   deriveRequirements()
src/domain/solicitation/validate.ts     validate() → errors + warnings
src/documents/clauses.ts                renderClause() variable substitution
src/documents/templates/*.tsx           RFB sections and bid form components
src/documents/renderHtml.ts             renderRfbHtml(), renderBidFormHtml()
src/documents/pdf.ts                    PdfRenderer interface + Chromium implementation
src/lib/supabase/{server,browser,admin}.ts, database.types.ts
src/lib/session.ts                      getSessionContext()
src/app/login/…, src/app/agency/…, src/app/office/…, src/app/admin/…, src/app/solicitations/…
supabase/migrations/0001_core.sql       tables, RLS, storage
supabase/migrations/0002_workflow.sql   workflow functions and audit
supabase/seed.sql                       fictional organizations, users, clauses
supabase/tests/*.test.sql               pgTAP
```

---

### Task 1: Project scaffold and tooling

**Files:**
- Create: the Next.js app at the repo root, `vitest.config.ts`, `supabase/config.toml`, and a `README.md` "Development" section.
- Test: `src/domain/smoke.test.ts`

**Interfaces:**
- Produces:
  - npm scripts: `dev`, `build`, `lint`, `test` (Vitest), `db:start` (`supabase start`), `db:reset` (`supabase db reset`), `db:test` (`supabase test db`), `db:types` (`supabase gen types typescript --local > src/lib/supabase/database.types.ts`).
  - The `@/*` path alias pointing to `src/*`.

- [ ] **Step 1:** Run `npx create-next-app@15 . --ts --app --src-dir --eslint --import-alias "@/*" --no-tailwind --use-npm`. Keep the existing `README.md`, `docs/` and `.gitignore`, and merge the generated ignore entries into `.gitignore` so `source-docs/` stays ignored.
- [ ] **Step 2:** Install `vitest`, `@vitest/coverage-v8`, `zod`, `date-fns@4`, `@date-fns/tz`, `@supabase/supabase-js`, `@supabase/ssr`, `playwright-core`, and `supabase` as a dev dependency. Run `npx supabase init`.
- [ ] **Step 3:** Write `src/domain/smoke.test.ts` asserting `1 + 1 === 2`. Run `npm test`; expect 1 passed.
- [ ] **Step 4:** Run `npm run build` and `npm run lint`; expect both to succeed.
- [ ] **Step 5:** Add "Development" to the README: Docker Desktop must be running for `npm run db:start`, and run `npx playwright install chromium` once.
- [ ] **Step 6:** Run `git status` and confirm `source-docs/` isn't listed. Commit: `chore: scaffold Next.js, Supabase and Vitest`.

---

### Task 2: Money, time and numbering utilities

**Files:**
- Create: `src/domain/money.ts`, `src/domain/time.ts`, `src/domain/numbering.ts`
- Test: `src/domain/money.test.ts`, `src/domain/time.test.ts`, `src/domain/numbering.test.ts`

**Interfaces:**
- Produces:
  - `type Cents = number`
  - `parseMoney(input: string): Cents | null` (accepts `$`, commas and up to 2 decimals; anything else gives `null`)
  - `formatMoney(c: Cents): string` (`"$150,000.00"`)
  - `type LocalDate = string` (`YYYY-MM-DD`)
  - `type LocalTime = string` (`HH:mm`)
  - `toUtc(date: LocalDate, time: LocalTime, tz: string): Date`
  - `todayIn(tz: string, now: Date): LocalDate`
  - `addDays(d: LocalDate, n: number): LocalDate`
  - `diffDays(a: LocalDate, b: LocalDate): number` (a − b)
  - `isWeekend(d: LocalDate): boolean`
  - `isNonWorkingDay(d: LocalDate, holidays: LocalDate[]): boolean`
  - `fiscalYearOf(d: LocalDate, startMonth: number): number` (the year the fiscal year ends)
  - `formatSolicitationNumber(fiscalYear: number, seq: number): string`

- [ ] **Step 1: Write failing tests**

```ts
expect(parseMoney("$150,000")).toBe(15_000_000);
expect(parseMoney("150000.00")).toBe(15_000_000);
expect(parseMoney("49,999.99")).toBe(4_999_999);
expect(parseMoney("12.345")).toBeNull();
expect(parseMoney("abc")).toBeNull();
expect(formatMoney(15_000_000)).toBe("$150,000.00");
// Review Focus 1
expect(toUtc("2026-11-01", "13:00", "America/Denver").toISOString()).toBe("2026-11-01T20:00:00.000Z"); // day DST ends
expect(toUtc("2026-07-15", "13:00", "America/Denver").toISOString()).toBe("2026-07-15T19:00:00.000Z");
expect(todayIn("America/Denver", new Date("2026-11-17T01:30:00Z"))).toBe("2026-11-16");
expect(diffDays("2026-09-14", "2026-09-04")).toBe(10);
expect(isNonWorkingDay("2026-11-26", ["2026-11-26"])).toBe(true);
expect(isWeekend("2026-11-21")).toBe(true);
expect(fiscalYearOf("2026-06-30", 7)).toBe(2026);
expect(fiscalYearOf("2026-07-01", 7)).toBe(2027);
expect(formatSolicitationNumber(2027, 674)).toBe("27-0674");
expect(formatSolicitationNumber(2027, 1)).toBe("27-0001");
```

- [ ] **Step 2:** Run `npm test -- src/domain`; expect failures (modules missing).
- [ ] **Step 3:** Implement. Use `TZDate` from `@date-fns/tz` for `toUtc` and `todayIn`, and treat `LocalDate` arithmetic as pure calendar dates (no zone).
- [ ] **Step 4:** Run `npm test -- src/domain`; expect PASS.
- [ ] **Step 5:** Commit: `feat(domain): money, time and numbering utilities`.

---

### Task 3: Solicitation model and value bands

**Files:**
- Create: `src/domain/solicitation/types.ts`, `schema.ts`, `valueBands.ts`
- Test: `src/domain/solicitation/valueBands.test.ts`, `schema.test.ts`

**Interfaces:**
- Consumes: `Cents`, `LocalDate`, `LocalTime` (Task 2).
- Produces:

```ts
type Category = "construction" | "major_maintenance" | "capital_construction";
type FundingSource = "capital_construction" | "major_maintenance" | "other";
type PreBidKind = "none" | "optional" | "mandatory";
type PreBidFormat = "in_person" | "phone" | "video";
type BidSection = "bid_form_1" | "bid_form_2" | "signature_page" | "insurance"
  | "qualifications" | "references" | "current_work";
type OptionalSection = "qualifications" | "references" | "current_work";
type AttachmentKind = "plans" | "specifications" | "sample_contract" | "prevailing_wage" | "other";
interface Contact { name: string; email: string; phone: string }
interface SolicitationData {
  shortTitle: string; longTitle: string; category: Category | null;
  summary: string; projectDescription: string; scopeNotes: string; specialProvisions: string;
  location: { address: string; city: string; county: string };
  requester: Contact; projectManager: Contact;
  estimateCents: Cents | null; fundingSource: FundingSource | null; fundingOther: string; federalFunds: boolean | null;
  releaseDate: LocalDate | null; adStart: LocalDate | null; adEnd: LocalDate | null; newspapers: string;
  questionsDue: { date: LocalDate; time: LocalTime } | null;
  answersDue: { date: LocalDate; time: LocalTime } | null;
  bidDueDate: LocalDate | null; bidDueTime: LocalTime;            // default "13:00"
  tentativeAwardDate: LocalDate | null; estimatedStartDate: LocalDate | null; estimatedCompletionDate: LocalDate | null;
  bidValidityDays: number;                                        // default 90
  preBid: { kind: PreBidKind; format: PreBidFormat | null; date: LocalDate | null; time: LocalTime | null; location: string };
  backgroundCheck: { required: boolean; contact: string; leadDays: number | null };
  schedule: { items: { name: string; description: string }[];
              alternates: { kind: "additive" | "deductive"; description: string }[] };
  optionalSections: OptionalSection[];
  pageLimits: Partial<Record<BidSection, number>>;
  attachments: { kind: AttachmentKind; label: string; storagePath: string; issueDate: LocalDate | null }[];
}
emptySolicitation(): SolicitationData
solicitationSchema: z.ZodType<SolicitationData>   // shape only; business rules live in validate()
interface Requirements {
  blocked: boolean; prevailingWage: boolean; bonds: boolean; apprenticeCredit: boolean;
  federalClauses: boolean; requiredSections: BidSection[];
}
deriveRequirements(estimateCents: Cents, federalFunds: boolean, optional: OptionalSection[]): Requirements
```

- [ ] **Step 1: Write failing tests** (boundaries, Review Focus 2)

```ts
const r = (d: number, fed = false, opt: OptionalSection[] = []) => deriveRequirements(Math.round(d * 100), fed, opt);
expect(r(49_999.99).blocked).toBe(true);
expect(r(50_000).blocked).toBe(false);
expect(r(99_999.99).prevailingWage).toBe(false);
expect(r(100_000).prevailingWage).toBe(true);
expect(r(149_999.99).bonds).toBe(false);
expect(r(150_000).bonds).toBe(true);
expect(r(999_999.99).apprenticeCredit).toBe(false);
expect(r(1_000_000).apprenticeCredit).toBe(true);
expect(r(200_000, true).federalClauses).toBe(true);
expect(r(60_000).requiredSections).toEqual(["bid_form_1", "bid_form_2", "signature_page", "insurance"]);
expect(r(60_000, false, ["references"]).requiredSections).toContain("references");
expect(solicitationSchema.safeParse(emptySolicitation()).success).toBe(true);
expect(emptySolicitation().bidDueTime).toBe("13:00");
expect(emptySolicitation().bidValidityDays).toBe(90);
```

- [ ] **Step 2:** Run `npm test -- src/domain/solicitation`; expect FAIL.
- [ ] **Step 3:** Implement the three files.
- [ ] **Step 4:** Run the tests; expect PASS.
- [ ] **Step 5:** Commit: `feat(domain): solicitation model and value bands`.

---

### Task 4: Validation rules

**Files:**
- Create: `src/domain/solicitation/validate.ts`
- Test: `src/domain/solicitation/validate.test.ts`

**Interfaces:**
- Consumes: Tasks 2 and 3.
- Produces:

```ts
type IssueCode =
  | "required" | "short_title_too_long" | "estimate_below_minimum" | "schedule_empty"
  | "date_order" | "bid_due_too_soon" | "release_too_soon" | "ad_period_too_short" | "ad_ends_after_bid_due"
  | "prebid_incomplete" | "prebid_out_of_window" | "attachment_missing"
  | "bid_due_non_working_day" | "mandatory_prebid_soon" | "placeholder_text";
interface Issue { code: IssueCode; field: string; message: string }  // field is a dotted path, e.g. "preBid.date"
interface ValidationContext { tz: string; holidays: LocalDate[]; submissionDate: LocalDate }
interface ValidationResult { errors: Issue[]; warnings: Issue[] }
validate(data: SolicitationData, ctx: ValidationContext): ValidationResult
```

- `submissionDate` is "today" for a draft and the latest submission date once submitted. At publish (Task 12) it is today.
- Warning codes: `bid_due_non_working_day`, `mandatory_prebid_soon` (pre-bid meeting less than 7 days after release), `placeholder_text` (a `[` or `]` in summary, projectDescription, scopeNotes or specialProvisions). All other codes are errors.

- [ ] **Step 1: Write failing tests**, starting from a fixture `validData()` that has zero issues:
  - estimate $160,000, release 2026-08-03, ads 2026-08-03 to 2026-08-17, questions 2026-08-17 13:00, answers 2026-08-24 13:00, bid due 2026-08-31, no pre-bid meeting, one schedule item, attachments for plans, specifications, sample contract and prevailing wage;
  - context submission date 2026-07-29, tz `America/Denver`, no holidays.

  Then one test per code, each changing exactly one thing:

```ts
expect(validate(validData(), ctx)).toEqual({ errors: [], warnings: [] });
expectError({ estimateCents: 4_999_999 }, "estimate_below_minimum", "estimateCents");
expectError({ shortTitle: "x".repeat(31) }, "short_title_too_long", "shortTitle");
expectNoIssue({ shortTitle: "x".repeat(30) });
expectError({ bidDueDate: "2026-08-28" }, "bid_due_too_soon", "bidDueDate");      // answers + 4 days
expectNoErrorCode({ bidDueDate: "2026-08-29" }, "bid_due_too_soon");              // + 5 days (a Saturday, so only a warning)
expectError({ releaseDate: "2026-07-31" }, "release_too_soon", "releaseDate");     // submission + 2
expectError({ adEnd: "2026-08-16" }, "ad_period_too_short", "adEnd");              // 13 days
expectError({ adEnd: "2026-09-01" }, "ad_ends_after_bid_due", "adEnd");
expectError({ answersDue: { date: "2026-08-17", time: "12:00" } }, "date_order", "answersDue");
expectError({ preBid: { kind: "mandatory", format: "in_person", date: null, time: null, location: "" } }, "prebid_incomplete", "preBid.date");
expectError({ preBid: { kind: "optional", format: "phone", date: "2026-08-18", time: "10:00", location: "x" } }, "prebid_out_of_window", "preBid.date");
expectError({ schedule: { items: [], alternates: [] } }, "schedule_empty", "schedule.items");
expectError({ estimateCents: 10_000_000, attachments: without("prevailing_wage") }, "attachment_missing", "attachments.prevailing_wage");
expectNoIssue({ estimateCents: 9_999_999, attachments: without("prevailing_wage") });
expectWarning({ bidDueDate: "2026-09-05" }, "bid_due_non_working_day", "bidDueDate");
expectWarning({ preBid: { kind: "mandatory", format: "in_person", date: "2026-08-06", time: "10:00", location: "x" } }, "mandatory_prebid_soon", "preBid.date");
expectWarning({ summary: "Replace [ROOF TYPE] membranes" }, "placeholder_text", "summary");
expectError({ longTitle: "" }, "required", "longTitle");
```

- [ ] **Step 2:** Run `npm test -- validate`; expect FAIL.
- [ ] **Step 3:** Implement `validate`. Each rule is a small function `(data, ctx) => Issue[]`, and the results are concatenated. A rule whose inputs are missing returns nothing and leaves the `required` rule to report it.
- [ ] **Step 4:** Run the tests; expect PASS.
- [ ] **Step 5:** Commit: `feat(domain): solicitation validation rules`.

---

### Task 5: Database schema, row-level security, storage, seed

**Files:**
- Create: `supabase/migrations/0001_core.sql`, `supabase/seed.sql`, `supabase/tests/00_helpers.sql`, `supabase/tests/rls.test.sql`
- Modify: `src/lib/supabase/database.types.ts` (generated)

**Interfaces:**
- Produces:
  - **Tables:**
    - `settings` (singleton `id = 1`): `state_name`, `office_name`, `timezone`, `fiscal_year_start_month`.
    - `holidays`: `day date` primary key, `name`.
    - `organizations`: `id`, `name`, `kind` (`agency` | `office`).
    - `profiles`: `user_id` (primary key, references `auth.users`), `org_id`, `display_name`, `is_admin bool`.
    - `solicitations`:
      - `id uuid`, `agency_id`, `created_by`, `state solicitation_state` (`draft`, `submitted`, `in_review`, `in_check`, `approved`, `published`), `number text unique null`, `fiscal_year int null`
      - `data jsonb` (the `SolicitationData`), `latest_submitted_at timestamptz`
      - `reviewer_id`, `checker_id`, `fallback_approved bool default false`, `version int null`
      - `published_at`, `release_date date null` (copied from `data` at publish), `bid_due_at timestamptz null`
      - `rfb_path`, `bid_form_path`, `published_snapshot jsonb`.
    - `number_sequences`: `fiscal_year` primary key, `last_seq`.
    - `clauses`: `key`, `version`, `body`, `created_by`, `created_at`, primary key `(key, version)`; insert only.
    - `solicitation_clause_locks`: `solicitation_id`, `clause_key`, `clause_version`.
    - `comments`: `id`, `solicitation_id`, `field text null`, `body`, `kind` (`return` | `disagree` | `note`), `author_id`, `created_at`.
    - `warning_acks`: `solicitation_id`, `code`, `field`, `acked_by`, `acked_at`, unique `(solicitation_id, code, field)`.
    - `audit_log`: `id bigserial`, `solicitation_id`, `actor_id`, `action text`, `detail jsonb`, `created_at`.
  - **SQL helpers** (`stable`, `security definer`): `app.my_org()`, `app.is_office()`, `app.is_admin()`, `app.today()` (today in the settings time zone).
  - **Storage buckets:** `attachments` (private, 100 MB file limit, paths `solicitations/{id}/{file}`) and `published` (public read).

- [ ] **Step 1: Write failing pgTAP tests** in `rls.test.sql`. `00_helpers.sql` defines `tests.make_user(email, org_id, is_admin)` and `tests.act_as(user_id)` (sets the role to `authenticated` and the `request.jwt.claims` sub). Assertions:
  - An agency A author sees their own draft and sees **0** rows of agency B's draft.
  - An office user sees both.
  - `anon` sees 0 drafts. It sees a `published` row only once `release_date <= app.today()`.
  - An agency author can `update solicitations set data = …` on their own `draft`, but the same update on a `submitted` row affects 0 rows.
  - An agency author's direct `update … set state = 'published'` throws (no column privilege).
  - Every role's `update` and `delete` on `audit_log` throw; so does `update` on `clauses`.
  - Agency A can't read objects under another agency's `attachments/solicitations/{id}/`; anyone can read `published`.
  - `comments`, `warning_acks` and `audit_log` follow their solicitation: an agency sees rows only for its own solicitations, and the office sees all of them. `anon` sees none.
- [ ] **Step 2:** Run `npm run db:start` then `npm run db:test`; expect failures.
- [ ] **Step 3:** Write `0001_core.sql`:
  - Grant `authenticated` only `insert` on solicitations and `update (data)`. All other changes go through Task 6's functions.
  - RLS policies per the assertions above.
  - Revoke `update` and `delete` on `audit_log` and `clauses` from `authenticated`, `anon` and `service_role`.
- [ ] **Step 4:** Write `seed.sql`:
  - Settings for State of Calder, `America/Denver`, fiscal year starting month 7.
  - Organizations: one office ("Calder State Construction Office") and two agencies ("Calder Department of Corrections", "Calder Parks Division").
  - Users with password `proclaro-dev` (local only): `author.corrections@example.test`, `author.parks@example.test`, `reviewer1@example.test`, `reviewer2@example.test`, `admin@example.test`.
  - Two holidays.
- [ ] **Step 5:** Run `npm run db:reset && npm run db:test`; expect all pass. Then run `npm run db:types`.
- [ ] **Step 6:** Commit: `feat(db): core schema, RLS, storage and seed`.

---

### Task 6: Workflow functions and audit

**Files:**
- Create: `supabase/migrations/0002_workflow.sql`, `supabase/tests/workflow.test.sql`

**Interfaces:**
- Consumes: Task 5.
- Produces: Postgres functions (`security definer`, `set search_path = public`). Each one:
  - checks the caller's org and role;
  - updates with `where id = $1 and state = '<expected>'`, and raises `'invalid_state'` if no row changed;
  - inserts one `audit_log` row with `action` equal to the function name.

| Function | Caller | From → To | Side effects |
|---|---|---|---|
| `submit_solicitation(p_id uuid)` | author in the owning agency | `draft` → `submitted` | On first submission: lock the `number_sequences` row and assign `number`/`fiscal_year` (from `app.today()`). Set `latest_submitted_at`. |
| `start_review(p_id)` | office staff | `submitted` → `in_review` | `reviewer_id = caller` |
| `reassign_review(p_id, p_user uuid)` | office staff | `in_review` → `in_review` | `p_user` must be office staff and ≠ `checker_id`; audit records old and new |
| `office_update_data(p_id, p_data jsonb, p_reason text)` | reviewer | `in_review` | Raises `reason_required` if the reason is blank. Audit `detail` = `{reason, changes: [{key, old, new}]}` for each changed top-level key |
| `return_to_agency(p_id, p_comments jsonb)` | reviewer | `in_review` → `draft` | Insert comments (`kind = 'return'`, `field` from each item); delete the `warning_acks` |
| `send_to_check(p_id)` | reviewer | `in_review` → `in_check` | Lock the latest version of every clause key into `solicitation_clause_locks` |
| `approve_check(p_id)` | office staff ≠ reviewer | `in_check` → `approved` | `checker_id = caller`; raises `same_person` if the caller is the reviewer |
| `disagree(p_id, p_comment text, p_field text)` | office staff ≠ reviewer | `in_check` → `in_review` | Insert a `disagree` comment; delete the clause locks |
| `approve_alone(p_id)` | reviewer | `in_review` → `approved` | Lock the clauses; `fallback_approved = true`; audit `detail` = `{fallback: "no second reviewer available"}` |
| `publish_solicitation(p_id, p_rfb_path text, p_bid_form_path text, p_snapshot jsonb, p_bid_due_at timestamptz)` | reviewer or checker | `approved` → `published` | `version = 1`, `published_at = now()`, `release_date = (data->>'releaseDate')::date`, set the paths, snapshot and `bid_due_at` |
| `acknowledge_warning(p_id, p_code text, p_field text)` | author while `draft`; reviewer while `in_review` | — | Upsert `warning_acks` |

- [ ] **Step 1: Write failing pgTAP tests** in `workflow.test.sql`:
  - Happy path: submit → start_review → send_to_check → approve_check (by reviewer2) → publish. The state ends `published`, `number` matches `^\d{2}-\d{4}$`, `version = 1`, and there are 5 audit rows.
  - `approve_check` by the reviewer raises `same_person`.
  - Review Focus 3: after reviewer2 calls `disagree`, an `approve_check` by reviewer2 raises `invalid_state`.
  - `office_update_data` with reason `''` raises `reason_required`. With a reason, the audit `detail->'changes'` contains the changed key with its old and new values.
  - `approve_alone` sets `fallback_approved` and writes the fallback text in the audit detail.
  - `send_to_check` creates one lock per clause key. Then a new clause version insert and an `approve_check` leave the locks unchanged.
  - An agency author calling `start_review` raises (not office).
  - Two submissions in the same fiscal year get consecutive numbers. A resubmission after `return_to_agency` keeps its number.
  - Any function on a `published` row raises `invalid_state`.
- [ ] **Step 2:** Run `npm run db:test`; expect failures.
- [ ] **Step 3:** Implement `0002_workflow.sql`. `grant execute` to `authenticated` only.
- [ ] **Step 4:** Run `npm run db:reset && npm run db:test`; expect PASS. Run `npm run db:types`.
- [ ] **Step 5:** Commit: `feat(db): workflow functions with audit`.

---

### Task 7: Auth, session context and app shell

**Files:**
- Create: `src/lib/supabase/server.ts`, `browser.ts`, `admin.ts`, `src/lib/session.ts`, `src/middleware.ts`, `src/app/login/page.tsx`, `src/app/login/actions.ts`, `src/app/layout.tsx` (modify), `src/app/page.tsx` (modify)
- Test: `src/lib/session.test.ts`

**Interfaces:**
- Produces:
  - `createServerClient(): SupabaseClient<Database>` (cookie-based, `@supabase/ssr`)
  - `createBrowserClient()`
  - `createAdminClient()`: service role; import it **only** in `src/app/admin/**` server code
  - `type SessionContext = { userId: string; orgId: string; orgKind: "agency" | "office"; isAdmin: boolean; displayName: string } | null`
  - `getSessionContext(): Promise<SessionContext>`
  - `homePathFor(ctx: SessionContext): string` (`/login`, `/agency`, `/office`, or `/admin` for an admin)
- Login: email and password for local development (the seed users). The method sits behind `signIn` in `login/actions.ts`, so magic link can replace it later.
- Middleware redirects anonymous users from `/agency`, `/office` and `/admin` to `/login`. `/solicitations` is public.

- [ ] **Step 1:** Write the failing test: `homePathFor` returns `/login` for null, `/agency` for an agency user, `/office` for an office user, and `/admin` when `isAdmin`.
- [ ] **Step 2:** Run it; expect FAIL. Implement it; expect PASS.
- [ ] **Step 3:** Implement the clients, `getSessionContext` (joins `profiles` and `organizations`), the login page and middleware, and a header showing the user, organization and sign-out.
- [ ] **Step 4:** Verify manually: `npm run dev`, then sign in as `author.parks@example.test` → lands on `/agency`; `reviewer1@example.test` → `/office`; signed out, `/office` → `/login`.
- [ ] **Step 5:** Commit: `feat(app): auth, session context and shell`.

---

### Task 8: Document templates and clause text

**Files:**
- Create: `src/documents/clauses.ts`, `src/documents/clauseKeys.ts`, `src/documents/templates/` (`RfbDocument.tsx`, `BidForm.tsx`, plus one file per section group), `src/documents/renderHtml.ts`, `supabase/migrations/0003_clauses_seed.sql`
- Test: `src/documents/clauses.test.ts`, `src/documents/renderHtml.test.ts`

**Interfaces:**
- Consumes: `SolicitationData`, `deriveRequirements`, `formatMoney` and the dates (Tasks 2–3).
- Produces:
  - `CLAUSE_KEYS: readonly string[]` — exactly: `notice`, `prebid_meeting`, `background_check`, `addenda`, `substitutions`, `submission`, `bid_deposit`, `performance_bond`, `modification_withdrawal`, `award_contract`, `resident_preference`, `registrations`, `apprentice_credit`, `reservation_of_rights`, `questions`, `communication_restrictions`, `insurance`, `prevailing_wage`, `warranty`, `federal_domestic_content`, `evaluation_award`, `bid_form_instructions`, `bid_form_terms`, `signature_certifications`.
  - `renderClause(body: string, vars: Record<string, string>): string` replaces `{{name}}`. It throws `UnknownClauseVariable` for a name not in `vars`, and HTML-escapes the values.
  - `interface DocContext { data: SolicitationData; number: string | null; version: number | null; settings: { stateName: string; officeName: string; timezone: string }; agencyName: string; clauses: Record<string, string> }`
  - `renderRfbHtml(ctx: DocContext, opts: { draft: boolean }): string`
  - `renderBidFormHtml(ctx: DocContext, opts: { draft: boolean }): string`
- The bid form markup marks every page with `data-bid-form-page` and contains the footer text template from Global Constraints; the page numbers are filled in by the PDF step.

- [ ] **Step 1: Write failing tests**

```ts
expect(renderClause("Due {{bidDue}}", { bidDue: "Aug 31" })).toBe("Due Aug 31");
expect(() => renderClause("{{nope}}", {})).toThrow("UnknownClauseVariable");
expect(renderClause("{{x}}", { x: "<b>&" })).toBe("&lt;b&gt;&amp;");
const html = (est: number, extra: Partial<SolicitationData> = {}) => renderRfbHtml(ctxWith(est, extra), { draft: false });
expect(html(16_000_000)).toContain('data-clause="bid_deposit"');
expect(html(14_999_999)).not.toContain('data-clause="bid_deposit"');
expect(html(9_999_999)).not.toContain('data-clause="prevailing_wage"');
expect(html(10_000_000)).toContain('data-clause="prevailing_wage"');
expect(html(99_999_999)).not.toContain('data-clause="apprentice_credit"');
expect(html(100_000_000)).toContain('data-clause="apprentice_credit"');
expect(html(16_000_000, { federalFunds: true })).toContain('data-clause="federal_domestic_content"');
expect(html(16_000_000)).not.toContain('data-clause="prebid_meeting"');     // preBid none
expect(html(16_000_000, { projectDescription: '<script>alert(1)</script> R&D' })).toContain("&lt;script&gt;alert(1)&lt;/script&gt; R&amp;D"); // Review Focus 4
expect(renderRfbHtml(ctxWith(16_000_000), { draft: true })).toContain("DRAFT — NOT FOR BIDDING");
expect(renderBidFormHtml(ctxWith(16_000_000, { schedule: twoItemsOneAlternate }), { draft: false })).toMatch(/Dormitory A[\s\S]*Dormitory B[\s\S]*Alternate 1[\s\S]*TOTAL/);
expect(renderBidFormHtml(ctxWith(16_000_000), { draft: false })).toContain("Solicitation 27-0001 · Version 1");
// the evaluation checklist lists exactly the required sections
expect(checklistRows(html(16_000_000, { optionalSections: ["references"] }))).toEqual(
  ["Bid Form Section 1", "Bid Form Section 2", "Signature Page", "Proof of Insurance", "References"]);
```

- [ ] **Step 2:** Run `npm test -- src/documents`; expect FAIL.
- [ ] **Step 3:** Implement the templates with `renderToStaticMarkup`. Wrap each clause in `<section data-clause="{key}">`. Section order follows spec §7.5. Print CSS uses letter size and `page-break-before` per major section.
- [ ] **Step 4:** Write `0003_clauses_seed.sql`: version 1 of every `CLAUSE_KEYS` entry, written fresh in plain language, using only the variables the templates pass in (`stateName`, `officeName`, `agencyName`, `number`, `bidDueDate`, `bidDueTime`, `questionsDue`, `answersDue`, `bidValidityDays`). No statute numbers, no real names.
- [ ] **Step 5:** Run the tests; expect PASS. Run `npm run db:reset`.
- [ ] **Step 6:** Commit: `feat(documents): RFB and bid form templates with clause text`.

---

### Task 9: PDF rendering and preview

**Files:**
- Create: `src/documents/pdf.ts`, `src/documents/loadDocContext.ts`, `src/app/api/solicitations/[id]/preview/route.ts`
- Test: `src/documents/pdf.test.ts`

**Interfaces:**
- Consumes: Task 8, Task 7's `createServerClient`.
- Produces:
  - `interface PdfRenderer { render(html: string, opts: { footerTemplate?: string }): Promise<Uint8Array> }`
  - `chromiumRenderer(): PdfRenderer`: `playwright-core`, `chromium.launch()`, `page.setContent`, `page.pdf({ format: "Letter", printBackground: true, displayHeaderFooter: !!footerTemplate, footerTemplate })`. The bid form footer uses the `pageNumber` and `totalPages` classes.
  - `loadDocContext(supabase, solicitationId: string, opts: { useLocks: boolean }): Promise<DocContext>`. With `useLocks` it reads clause bodies from `solicitation_clause_locks`; otherwise the latest version of each clause.
  - `GET /api/solicitations/{id}/preview?doc=rfb|bid-form` returns `application/pdf` with `draft: true`. RLS on the caller's own client decides access, so a missing row gives 404.

- [ ] **Step 1:** Write the failing test (tagged slow, needs Chromium): render a minimal bid form, then use `pdfjs-dist` text extraction to assert the output contains `Solicitation 27-0001 · Version 1 · Page 1 of`.
- [ ] **Step 2:** Run it; expect FAIL. Implement `pdf.ts`; expect PASS.
- [ ] **Step 3:** Implement `loadDocContext` and the preview route.
- [ ] **Step 4:** Verify manually: with a seeded draft, open `/api/solicitations/{id}/preview?doc=rfb` as its author and see the watermarked PDF; as the other agency's author, get 404.
- [ ] **Step 5:** Commit: `feat(documents): PDF rendering and draft preview`.

---

### Task 10: Agency author screens

**Files:**
- Create: `src/app/agency/page.tsx` (my solicitations), `src/app/agency/solicitations/new/actions.ts`, `src/app/agency/solicitations/[id]/page.tsx`, `src/app/agency/solicitations/[id]/SolicitationForm.tsx` (client), `src/app/agency/solicitations/[id]/actions.ts`, `src/components/AttachmentUploader.tsx`, `src/components/IssueList.tsx`
- Test: `src/app/agency/solicitations/[id]/actions.test.ts`

**Interfaces:**
- Consumes: `validate`, `deriveRequirements`, `solicitationSchema`, `emptySolicitation`, the session, Task 6's functions.
- Produces server actions:
  - `createSolicitation(): Promise<{ id: string }>` inserts a `draft` with `emptySolicitation()`.
  - `saveDraft(id: string, data: SolicitationData): Promise<void>` runs the Zod parse, then `update … set data`.
  - `createUploadUrl(id: string, fileName: string): Promise<{ path: string; token: string }>` uses `storage.from("attachments").createSignedUploadUrl` (Review Focus 5).
  - `acknowledgeWarning(id, code, field)`
  - `submitSolicitation(id: string): Promise<{ ok: true } | { ok: false; errors: Issue[]; unacknowledged: Issue[] }>`

- The form's sections follow spec §7.2.
- `validate()` runs in the browser on every change against `{ tz, holidays, submissionDate: todayIn(tz) }`, with errors and warnings shown next to their fields.
- A requirements panel shows `deriveRequirements` live: blocked, bonds, prevailing wage and so on.
- Comments from a return are shown on their fields.
- Saving is explicit (a Save button), with a debounced autosave after 5 seconds idle.

- [ ] **Step 1: Write failing tests** for `submitSolicitation`, with Supabase mocked behind a small injected `deps` parameter:
  - It returns `ok: false` with the errors when `validate` has errors, and doesn't call `submit_solicitation`.
  - It returns `ok: false` with `unacknowledged` when warnings lack acknowledgments.
  - It calls the `submit_solicitation` function when clean.
  - The server re-validates using `deps.loadData`, **not** client-supplied data.
- [ ] **Step 2:** Run; expect FAIL. Implement the actions; expect PASS.
- [ ] **Step 3:** Build the screens. Uploads go from the browser with `uploadToSignedUrl`, and `attachments[]` gets `storagePath`.
- [ ] **Step 4: Verify manually:**
  - Create a draft as `author.parks`. Set the estimate to $49,999.99 and see the blocked error; $150,000 shows the bonds requirement.
  - Upload a 40 MB PDF as plans; it succeeds without a server-action body error.
  - Fix all errors, acknowledge a weekend warning and submit. The draft becomes read-only with a number like `27-0001`.
- [ ] **Step 5:** Commit: `feat(agency): solicitation form, uploads and submit`.

---

### Task 11: Office review and check screens

**Files:**
- Create: `src/app/office/page.tsx` (queues: Submitted, In review (mine / all), In check, Approved), `src/app/office/solicitations/[id]/page.tsx`, `src/app/office/solicitations/[id]/ReviewPanel.tsx`, `src/app/office/solicitations/[id]/actions.ts`
- Test: `src/app/office/solicitations/[id]/actions.test.ts`

**Interfaces:**
- Consumes: Task 6's functions, `validate`, the preview route, `IssueList`.
- Produces server actions, each a thin wrapper over its function that maps `invalid_state`, `same_person` and `reason_required` to user messages:
  - `startReview(id)`, `reassign(id, userId)`
  - `editAsReviewer(id, data, reason)` (Zod parse, then `office_update_data`)
  - `returnToAgency(id, comments: { field: string | null; body: string }[])`
  - `sendToCheck(id)` (refuses with errors if `validate` has errors or unacknowledged warnings, using `submissionDate` = the latest submission date)
  - `approveAlone(id)` (same validation gate)
  - `approveCheck(id)`, `disagree(id, comment, field)`

- The review page shows:
  - the fields read-only by default, with "Edit" switching on editing and a required reason box;
  - live validation with acknowledgment;
  - the requirements panel;
  - embedded RFB and bid form previews;
  - per-field comment boxes;
  - the audit history.
- Action buttons depend on the state and on whether the viewer is the reviewer:

  | State | Viewer | Buttons |
  |---|---|---|
  | `in_review` | reviewer | Return / Send to check / Approve alone |
  | `in_check` | not the reviewer | Approve / Disagree |
  | `in_check` | the reviewer | waiting message, no buttons |

- "Approve alone" asks for confirmation: *"No second reviewer available. This approval will be recorded as a single-reviewer approval."*

- [ ] **Step 1: Write failing tests:**
  - `sendToCheck` and `approveAlone` refuse when `validate` has errors.
  - `approveCheck` maps a `same_person` error to "You reviewed this solicitation; a different person must check it."
  - `editAsReviewer` with a blank reason refuses before calling the database.
- [ ] **Step 2:** Run; expect FAIL. Implement; expect PASS.
- [ ] **Step 3:** Build the screens.
- [ ] **Step 4: Verify manually:**
  - reviewer1 starts the review, edits a date with a reason (it appears in the history), and sends it to check.
  - reviewer1 sees no Approve button.
  - reviewer2 disagrees with a comment, and the solicitation is back in reviewer1's queue.
  - reviewer1 approves alone; the history shows the fallback.
  - A second solicitation goes through return → resubmit and keeps its number.
- [ ] **Step 5:** Commit: `feat(office): review, check and fallback approval`.

---

### Task 12: Publish and public listing

**Files:**
- Create: `src/app/office/solicitations/[id]/publish.ts`, `src/app/solicitations/page.tsx`, `src/app/solicitations/[number]/page.tsx`
- Test: `src/app/office/solicitations/[id]/publish.test.ts`

**Interfaces:**
- Consumes: `loadDocContext(…, { useLocks: true })`, `renderRfbHtml`, `renderBidFormHtml`, `PdfRenderer`, `toUtc`, `todayIn`, `validate`, `publish_solicitation`.
- Produces: `publishSolicitation(id: string, deps?: PublishDeps): Promise<{ ok: true; number: string } | { ok: false; errors: Issue[] }>`. Steps, in order:
  1. Load the solicitation; it must be `approved`.
  2. Run `validate` with `submissionDate = todayIn(tz)`, and refuse if `releaseDate < today` (code `release_too_soon`, message "Release date has passed; correct the dates before publishing").
  3. Render both documents with `draft: false`, version 1 and the locked clauses.
  4. Upload them to `published/solicitations/{number}/v1/rfb.pdf` and `bid-form.pdf`.
  5. Call `publish_solicitation` with the paths, `snapshot = { data, clauses, settings, renderedAt }` and `bid_due_at = toUtc(bidDueDate, bidDueTime, tz)`.
  6. If step 5 fails, delete the two uploads.
- Public listing:
  - `/solicitations` shows published rows (RLS already filters by release date): number, long title, agency, bid due (local) and status. Status is `Open` while `now < bid_due_at`, otherwise `Closed`.
  - `/solicitations/{number}` shows the summary, key dates and download links for the RFB, bid form and attachments.

- [ ] **Step 1: Write failing tests** with deps injected:
  - With a fixed `now` of `2026-08-04T01:00:00Z` (still Aug 3 in `America/Denver`):
    - a release date of 2026-08-03 is **allowed**, because the local date is Aug 3 even though the UTC date is Aug 4;
    - a release date of 2026-08-02 is refused with `release_too_soon`.
  - It refuses when the state isn't `approved`.
  - On success it calls the renderer twice with `draft: false` and the locked clauses, uploads to the `v1` paths, and passes `bid_due_at` = `2026-08-31T19:00:00Z` for Aug 31 13:00 MDT.
  - When `publish_solicitation` fails, it deletes both uploads.
- [ ] **Step 2:** Run; expect FAIL. Implement; expect PASS.
- [ ] **Step 3:** Add the Publish button to the office page for `approved` rows (shown to the reviewer or checker). Build the public pages.
- [ ] **Step 4: Verify manually:**
  - Publish an approved solicitation with today's release date. It appears at `/solicitations` signed out, and the downloaded bid form footer reads `Solicitation 27-000N · Version 1 · Page 1 of N`.
  - A solicitation with a future release date doesn't appear.
  - An attempted `saveDraft` or `office_update_data` on the published row fails.
- [ ] **Step 5:** Commit: `feat: publish solicitations and public listing`.

---

### Task 13: Admin screens

**Files:**
- Create: `src/app/admin/page.tsx`, `src/app/admin/users/…`, `src/app/admin/organizations/…`, `src/app/admin/clauses/…`, `src/app/admin/holidays/…`, `src/app/admin/settings/…`, and an `actions.ts` for each
- Test: `src/app/admin/clauses/actions.test.ts`

**Interfaces:**
- Consumes: `createAdminClient` (users only), `createServerClient`, `CLAUSE_KEYS`, `renderClause`.
- Produces:
  - `createUser({ email, displayName, orgId, isAdmin })` uses `auth.admin.inviteUserByEmail`, then inserts the profile.
  - `saveClause(key: string, body: string)` inserts version `max + 1` and never updates. It validates that `key` is in `CLAUSE_KEYS`, and that `renderClause(body, sampleVars)` doesn't throw (so an unknown variable is rejected with its name).
  - Organizations: create and rename. Holidays: add and remove. Settings: state name, office name, time zone (IANA list), fiscal year start month.
- Every admin action checks `ctx.isAdmin` on the server.

- [ ] **Step 1: Write failing tests:**
  - `saveClause("notice", "{{bogus}}")` returns an error naming `bogus`.
  - `saveClause("unknown_key", "x")` errors.
  - A valid save inserts `version = previous + 1`.
  - A non-admin context is refused.
- [ ] **Step 2:** Run; expect FAIL. Implement; expect PASS.
- [ ] **Step 3:** Build the screens. The clause page shows the version history for each key, read-only.
- [ ] **Step 4:** Verify manually: edit `insurance` as admin. A solicitation sent to check *before* the edit still previews and publishes the old text; one sent after uses the new text.
- [ ] **Step 5:** Commit: `feat(admin): users, organizations, clauses, holidays, settings`.

---

### Task 14: End-to-end verification and docs

**Files:**
- Modify: `README.md` (how to run, seed users), `docs/decisions.md` (record the slice as built)

- [ ] **Step 1:** Run `npm run lint && npm test && npm run db:reset && npm run db:test && npm run build`; expect all green.
- [ ] **Step 2:** Walk the full flow: agency draft → errors fixed → submit → review with edit → disagree → send to check again → approve by second person → publish → public download. Check that the audit history shows every step.
- [ ] **Step 3:** Search the repo for the real-world names listed in the git-ignored source-docs notes; expect no matches.
- [ ] **Step 4:** Commit: `docs: solicitation setup slice complete`.
