# Advisory AI Document Check (Slice 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After close, the office scans each signed original. It then runs an advisory AI check of each bid's documents (one OpenAI call per document) and sees met / not met / unclear per checklist item, with page and excerpt. The office confirms or overrides each item, and nothing the check finds changes an outcome.

**Architecture:**
- **Postgres** owns who can run a check, when, the caps and the append-only record: definer functions, pgTAP.
- **TypeScript** owns the checklist, the rule comparisons (names, amount in words, dates, addenda, version, certificate) and the model call. These are pure modules plus one server-only OpenAI module.
- **The browser** starts a run, then calls one server action per document, so no request covers a whole bid.

**Tech Stack:** Existing (Next.js 15, React 19, TypeScript, Supabase, Zod, Vitest, pgTAP, playwright-core), plus two new dependencies: `openai` (official SDK) and `pdf-lib` (page count, fixtures).

**Spec:** `docs/superpowers/specs/2026-11-21-ai-document-check-design.md` (approved; its *(my call)* items are binding).

## Global Constraints

- **Advisory only.** No writer here touches `bid_outcomes`, `flagged_decisions`, recaps or awards. The UI has no outcome buttons in the check panel.
- **Results** are exactly `met | not_met | unclear`, with `page` (int or null) and `excerpt` (≤ 300 characters) per item.
  - There are **no confidence scores** anywhere: schema, DB or UI.
  - A missing or unparseable extraction is `unclear`, never `met`.
- **Sealed until close.** Every function raises `sealed` before `app.bids_closed`. File reads go through the existing post-close office path.
- **Office only.** Agency, bidders and anon get `not_authorized` on every function. Results are never public, recorded ones included.
- **The key.** `OPENAI_API_KEY` is read only in `src/server/aicheck/openai.ts` (with `import "server-only"`).
  - Never use `NEXT_PUBLIC_` for it, never log it, never commit it.
  - `OPENAI_MODEL` selects the model (the default is chosen from current OpenAI docs at build time and recorded in decisions.md).
  - `AI_CHECK_ENABLED` must be `1` for live runs. Anything else hides "Run check" and shows `Document checks are turned off.`
- **Caps** are stored in `public.settings` and enforced in SQL:
  - `ai_runs_per_bid = 3`
  - `ai_calls_per_user_day = 50`
  - `ai_calls_per_day = 200`

  A "day" is `app.today()` in `settings.timezone`.
- **Stale runs.** A `running` run older than 10 minutes counts as failed.
- **Scans** are PDF only, ≤ 20 MB (enforced in SQL from `storage.objects` metadata) and ≤ 30 pages (enforced in TS before upload).
- **Unit tests never call OpenAI.** Vitest uses recorded responses; the live evaluation is `npm run aicheck:eval`, run manually only.
- **Fictional data only;** never open `source-docs/`.
- **SQL conventions:**
  - new migrations from `0036`;
  - definer, `set search_path = ''`, revoke from public/anon/authenticated/service_role, then grant `public` functions to authenticated;
  - errors `raise exception '<code>' using errcode = 'P0001'`;
  - new codes `ai_check_running`, `ai_cap_reached`, `scan_too_large`, `not_scannable`; reused `not_authorized`, `not_found`, `sealed`, `invalid_state`, `invalid_data`, `reason_required`.
- **Copy (verbatim):**
  - `Scan not attached`
  - `Recorded result`
  - `Document checks are turned off.`
  - `Advisory only. The reviewer decides every outcome.`
- **UI rules** as in prior slices: `src/components/ui` only, no inline style, onSubmit + startTransition, a polite live region and role=alert, row-specific aria-labels, `ConfirmAction` for "Run check".
- **Gates:** `npm run lint && npm test && npm run db:reset && npm run db:test`; plus `npm run db:types` after a migration and `npm run build` for UI tasks.

## Review Focus

1. **A bad model response.** If the model omits an item, returns invalid JSON or an unknown result value, that document's items become `unclear` and the run continues. Pinned in Task 3.
2. **Amount in words.** "One Million Two Hundred Thousand and 50/100 Dollars" parses to 120000050 cents. "Twelve thousand dollars only" parses to 1200000. Garbage gives null, which gives `unclear`. Pinned in Task 2.
3. **A double click.** A second `start_ai_check` while one is running raises `ai_check_running`. After 10 minutes it is allowed. Pinned in Task 1.
4. **Caps.** The 3rd run on a bid is allowed and the 4th raises `ai_cap_reached`. The 50th document call for a user today is allowed and the 51st is refused. Pinned in Task 1.
5. **Missing configuration.** With no `OPENAI_API_KEY`, "Run check" returns `The AI check is not configured.` without a network call. Pinned in Task 4.

---

## File map

- `supabase/migrations/0036_ai_check.sql` and `supabase/tests/ai_check.test.sql`
- `src/domain/aicheck/`:
  - `checklist.ts` (item codes per document kind);
  - `words.ts` (amount in words to cents);
  - `rules.ts` (the comparisons);
  - `evaluate.ts` (model response plus facts to items);
  - each with a `.test.ts`.
- `src/server/aicheck/openai.ts` (+ test): the only module that reads the key.
- `src/app/office/solicitations/[id]/review/aicheck/`: `logic.ts`, `actions.ts`, `DocumentCheckPanel.tsx`, `logic.test.ts`.
- Modified: `src/app/office/solicitations/[id]/review/page.tsx`, and `src/app/office/solicitations/[id]/bids/OriginalsPanel.tsx` (attach scan).
- `scripts/aicheck-fixtures.mjs`, `scripts/seed-files.mjs`, `scripts/aicheck-eval.mjs`, `fixtures/aicheck/` (generated PDFs plus `manifest.json`).
- `supabase/seed.sql`, `README.md`, `docs/decisions.md`, `package.json`.

---

### Task 1: Schema, caps and the run lifecycle

**Files:** Create `supabase/migrations/0036_ai_check.sql`, `supabase/tests/ai_check.test.sql`.

**Interfaces (Produces):**
- **`settings` columns:** `ai_runs_per_bid int not null default 3`, `ai_calls_per_user_day int not null default 50`, `ai_calls_per_day int not null default 200`, admin-editable like the other settings columns.
- **`public.bid_original_scans`:** `id`, `log_entry_id` (→ `bid_original_log`, a non-void entry), `bid_id`, `path`, `attached_by`, `attached_at`, `superseded_by` (uuid null).
  - Append-only except `superseded_by`, which only `attach_original_scan` sets.
  - No API grants.
- **Scan storage path:** `bids/{bid_id}/originals/{log_entry_id}/{uuid}.pdf` in the `bid-files` bucket.
  - Office insert is allowed only after close, for an existing non-void log entry of that bid.
  - Office read is allowed after close (extend `app.can_upload_bid_file` / `app.can_read_bid_file` from their latest definitions, R1).
- **`public.attach_original_scan(p_log_entry_id uuid, p_path text) returns uuid`:**
  - office only, after close (`sealed` before);
  - the object must exist in `storage.objects` with size ≤ 20971520 (`scan_too_large`) and the pinned path (`invalid_data`);
  - a void entry raises `not_scannable`;
  - it supersedes the previous current scan of that entry, and is audited in `bid_audit_log`.
- **`public.ai_check_runs`:** `id`, `bid_id`, `started_by`, `started_at`, `finished_at`, `status` (`running|done|failed`), `model text`, `bid_version int`, `solicitation_version int`, `recorded boolean not null default false`.
  - Partial unique index on `(bid_id) where status = 'running'`.
- **`public.ai_check_items`** (append-only): `id`, `run_id`, `document_kind` (`signed_form|bid_bond_scan|insurance|bid_bond|qualifications|references|current_work`), `document_path text null`, `item_code text`, `method` (`ai|rule`), `result` (`met|not_met|unclear`), `page int null`, `excerpt text null` (≤ 300), `extracted text null`, `detail text null`, `call_failed boolean not null default false`.
- **`public.ai_check_reviews`** (append-only): `item_id`, `decision` (`confirm|override`), `reason` (required for override), `reviewed_by`, `reviewed_at`.
- **`public.start_ai_check(p_bid_id uuid, p_model text) returns uuid`.** Checks in this order:
  1. office;
  2. the bid is counted (`app.bid_excluded` false) or `not_found`;
  3. closed or `sealed`;
  4. a stale `running` run (older than 10 min) is set to `failed` first;
  5. a live running run raises `ai_check_running`;
  6. non-recorded runs on the bid ≥ `ai_runs_per_bid` raises `ai_cap_reached`.

  It inserts `running`, records the bid's latest version and the solicitation version, and is audited.
- **`public.record_ai_check_document(p_run_id uuid, p_items jsonb) returns void`:**
  - the caller must be the run's `started_by`, and the run must be `running` and not stale (`invalid_state` otherwise);
  - before inserting, it counts 1 document call against both daily caps: calls are counted as the distinct (run, document) groups recorded by that user today and overall today (`ai_cap_reached`);
  - each item's code must belong to its `document_kind` (`invalid_data`), using the same list as `checklist.ts` via a marker-comment parity test;
  - it inserts the items.
- **`public.finish_ai_check(p_run_id uuid, p_status text) returns void`:** caller is the starter; `running` becomes `done|failed`.
- **`public.review_ai_check_item(p_item_id uuid, p_decision text, p_reason text) returns void`:** office, after close; an override with a blank reason raises `reason_required`.
- **`public.bid_ai_check(p_bid_id uuid) returns jsonb`:** office, after close. Returns the latest run (by `started_at`) with its items, each item's latest review, `recorded`, and run counts and remaining caps:
  - `{run, items:[...], runsUsed, runsLeft, callsLeftUser, callsLeftTotal}`.
- **`public.ai_check_documents(p_bid_id uuid) returns table(document_kind text, path text)`:** office, after close.
  - The latest version's files for slots `insurance`, `bid_bond`, `qualifications`, `references` and `current_work`, where present.
  - The current scan for the signed-form log entry, with kind `signed_form` and path null when there is no scan.
  - The bond log entry's scan, with kind `bid_bond_scan`, when the bond choice is paper.
- **`recorded = true` has no API write path;** only the seed inserts such runs.

- [ ] **Step 1: Write failing pgTAP** covering:
  - every function's not_authorized (agency, bidder, anon) and `sealed` before close;
  - Review Focus 3 (a second start raises `ai_check_running`; after `update ... started_at = now() - interval '11 minutes'` a start succeeds and the old run reads `failed`);
  - Review Focus 4 (runs 1–3 ok and the 4th raises `ai_cap_reached`; set `ai_calls_per_user_day = 2` in the fixture, then the 3rd `record_ai_check_document` raises `ai_cap_reached`);
  - a wrong item code raises `invalid_data`;
  - a non-starter recording raises `invalid_state`;
  - an override with a blank reason raises `reason_required`;
  - `attach_original_scan` cases: before close `sealed`, void entry `not_scannable`, a 20971521-byte object `scan_too_large`, a second scan supersedes the first;
  - `bid_ai_check` shows the latest review per item;
  - the API has no insert/update on the four tables;
  - no function writes `bid_outcomes` (row count is unchanged across a full run).
- [ ] **Step 2:** `npm run db:reset && npm run db:test`. The new file should fail.
- [ ] **Step 3:** Implement 0036.
- [ ] **Step 4:** Run the gates plus `db:types`. Everything should pass.
- [ ] **Step 5:** Commit `feat(db): AI check runs, items, reviews, scans and caps`.

---

### Task 2: The checklist and the rule comparisons (pure TS)

**Files:** Create `src/domain/aicheck/{checklist,words,rules,evaluate}.ts` plus tests.

**Interfaces (Produces):**
- `type DocumentKind = "signed_form" | "bid_bond_scan" | "insurance" | "bid_bond" | "qualifications" | "references" | "current_work"`.
- `CHECKLIST: Record<DocumentKind, readonly ItemSpec[]>`, where `ItemSpec = {code, label, method: "ai" | "rule", asks: string}` (`asks` is the instruction to the model for that item). The codes:
  - **signed_form:** `signature_present` (ai), `amount_in_words` (rule), `addenda_listed` (rule), `form_version` (rule), `resident_certificate` (rule, only when the bid claims residency).
  - **insurance:** `insured_name` (rule), `coverage_dates` (rule).
  - **bid_bond** and **bid_bond_scan:** `principal_name` (rule), `obligee` (rule), `surety_signature` (ai).
  - **qualifications, references, current_work:** `document_matches_slot` (ai).
- Mark the code list with `// aicheck-codes:start/end` markers; Task 1's SQL list must match it (parity test reads the migration).
- `wordsToCents(text: string): number | null`. Handles "and NN/100", "and NN cents", "dollars", "only", hyphens, commas and capitalisation. Returns null on anything it can't parse.
- `namesMatch(a: string, b: string): boolean`. Case and punctuation insensitive, and treats "LLC", "L.L.C.", "Inc", "Incorporated", "Co", "Company" and "Corp" as equal suffixes.
- `coversDate(from: string | null, to: string | null, dueLocalDate: string): boolean | null`. Null when a date is missing or unparseable.
- `addendaMatch(listed: string | null, published: number[]): boolean | null`. Parses "1, 2", "1 and 2", "#1, #2", and "None" (which means `[]`).
- `type ModelItem = {code: string; result: "met" | "not_met" | "unclear"; page: number | null; excerpt: string | null; extracted: string | null}`.
- `type Facts = {legalName: string; baseTotalCents: number; publishedAddenda: number[]; submittedFormVersion: number; residentCertificate: string | null; agencyName: string; dueLocalDate: string}`.
- `evaluate(kind: DocumentKind, model: unknown, facts: Facts): CheckItem[]`, where `CheckItem = {code, method, result, page, excerpt, extracted, detail}`.
  - It validates `model` with Zod. Invalid data, or a missing code, gives `unclear` with detail `The model did not report this item.`
  - For rule items it uses `extracted` and the comparison: true is `met`, false is `not_met`, null is `unclear`. The model's own `result` for a rule item is ignored.
  - Excerpts are truncated to 300 characters.

- [ ] **Step 1: Failing Vitest:**
  - Review Focus 2's three `wordsToCents` cases, plus "Fifteen Thousand Two Hundred Dollars and 00/100" → 1520000;
  - `namesMatch("Ridgeback Builders LLC", "RIDGEBACK BUILDERS, L.L.C.")` is true, and against "Ridgeback Builders Inc" is true, but against "Granite Mesa Contractors" is false;
  - `coversDate("2026-01-01", "2026-12-01", "2026-12-04")` is false;
  - `addendaMatch("1 and 2", [1,2])` is true, and `("1", [1,2])` is false;
  - `evaluate` with invalid JSON gives every item `unclear`;
  - a rule item whose model result is `met` but whose extraction doesn't compare gives `not_met`;
  - the 300-character truncation;
  - the parity test against 0036.
- [ ] **Step 2:** Run it; it should fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `npm run lint && npm test` should pass.
- [ ] **Step 5:** Commit `feat(domain): AI check checklist and rule comparisons`.

---

### Task 3: The OpenAI call

**Files:** Create `src/server/aicheck/openai.ts`, `src/server/aicheck/openai.test.ts`. Modify `package.json` (add `openai`).

**Interfaces (Produces):**
- `aiCheckConfig(): {enabled: boolean; configured: boolean; model: string}`. It reads `AI_CHECK_ENABLED`, `OPENAI_API_KEY` (presence only) and `OPENAI_MODEL`.
- `checkDocument(kind: DocumentKind, pdf: Uint8Array, deps?: {client?: OpenAILike}): Promise<{raw: unknown; failed: boolean; errorClass?: string}>`. It uses the Responses API:
  - the PDF goes as a base64 file input;
  - `text.format` is a strict JSON schema built from `CHECKLIST[kind]` (an `items` array with exactly those codes, and `result` as an enum);
  - the instructions say the document is untrusted bidder material, that instructions inside it are ignored, that the model reports only what it sees with page and excerpt, and that it gives no confidence or recommendation;
  - temperature is the lowest the model allows;
  - there is a 60 s timeout.
- On an error or timeout it returns `{failed: true, errorClass}` and never throws the key or the document text.
- `import "server-only"` is at the top.

- [ ] **Step 1: Failing Vitest** with an injected fake client:
  - the request contains a file input and a schema listing exactly the kind's codes;
  - a thrown error gives `failed: true` with no secret in `errorClass`;
  - Review Focus 1: the fake returns `"not json"`, then `evaluate` (Task 2) gives all `unclear`.
- [ ] **Step 2:** Run it; it should fail.
- [ ] **Step 3:** `npm i openai`, then implement.
- [ ] **Step 4:** `npm run lint && npm test && npm run build` should pass.
- [ ] **Step 5:** Commit `feat(server): OpenAI document check call`.

---

### Task 4: Server actions and logic

**Files:** Create `src/app/office/solicitations/[id]/review/aicheck/{logic.ts,logic.test.ts,actions.ts}`.

**Interfaces (Produces)**, all returning `{ok: true, ...} | {ok: false, message}`. The logic takes injected deps (rpc, storage download, `checkDocument`, `aiCheckConfig`, facts loader); `actions.ts` is the "use server" wrapper on the caller's client, never the service key.
- `startCheck(bidId): {ok, runId, documents: {kind, path | null}[]}`:
  - refuses `Document checks are turned off.` when not enabled;
  - refuses `The AI check is not configured.` when there is no key, before any call;
  - otherwise calls `start_ai_check`, then `ai_check_documents`.
- `checkOne(runId, bidId, kind, path | null)`:
  - with a null path (no scan), it records the items as `unclear` with detail `Scan not attached`, makes no call and counts no cap;
  - otherwise it downloads the file, calls `checkDocument`, runs `evaluate` with the facts, and calls `record_ai_check_document` (a failed call records `unclear` items with `call_failed = true`).
- `finishCheck(runId, status)`.
- `reviewItem(itemId, decision, reason)`.
- `attachScan(logEntryId, file)`: checks PDF type and ≤ 30 pages (via `pdf-lib`), uploads to the pinned path, then calls `attach_original_scan`.
- `loadFacts(bidId)`: the legal name and base total (from `opened_bids`), the published addenda numbers, the bid's `solicitation_version` and version, the resident certificate claim (from `resident_claims`), the agency name, and the due local date.
- Error-code messages:
  - `ai_check_running` → `A check is already running for this bid.`
  - `ai_cap_reached` → `The check limit has been reached. Try again tomorrow.`
  - `sealed` → `Bids are still sealed.`
  - `scan_too_large` → `The scan is larger than 20 MB.`
  - `not_scannable` → `That log entry was voided.`

- [ ] **Step 1: Failing Vitest:**
  - Review Focus 5;
  - a null scan path gives `Scan not attached` items with no `checkDocument` call;
  - a failed call gives `call_failed` items;
  - every error code maps;
  - `attachScan` refuses a 31-page PDF before upload.
- [ ] **Step 2:** Run it; it should fail.
- [ ] **Step 3:** `npm i pdf-lib`, then implement.
- [ ] **Step 4:** Run the gates plus `build`. Everything should pass.
- [ ] **Step 5:** Commit `feat(office): AI check actions`.

---

### Task 5: Screens

**Files:** Create `DocumentCheckPanel.tsx`. Modify `review/page.tsx` and `bids/OriginalsPanel.tsx`.

**Produces:**
- **The review page panel, per bid row** (expandable), titled "Document check" with the line `Advisory only. The reviewer decides every outcome.`:
  - the run status; `Recorded result` when recorded;
  - `runsLeft` / `callsLeft`;
  - "Run check", a `ConfirmAction` that says the check calls the AI service and counts against today's limit. It is hidden with `Document checks are turned off.` when disabled. After confirming, the client loops `checkOne` over the documents, showing progress ("Checking 2 of 5…"), then calls `finishCheck`.
  - Items grouped by document. Each shows the label, a result badge (`Met`, `Not met`, `Unclear`, with text and never colour alone), a method chip (`AI` / `Rule`), the page, the excerpt, a link to the file at `#page=N`, and the detail.
  - Confirm / Override (reason) per item, with row-specific aria-labels and the latest review shown.
  - A summary: "N not met · M unclear".
- **Originals panel (after close):** "Attach scan" per non-void signed-form or bond entry, showing the current scan with an "Open" link.

- [ ] **Step 1:** Failing Vitest for any pure helpers the panel uses (grouping, summary counts, badge mapping).
- [ ] **Step 2:** Run it; it should fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the gates plus `build`. Everything should pass.
- [ ] **Step 5:** Commit `feat(office): document check panel and scan upload`.

---

### Task 6: Fixtures, seed files and recorded results

**Files:** Create `scripts/aicheck-fixtures.mjs`, `scripts/seed-files.mjs`, `fixtures/aicheck/*`. Modify `supabase/seed.sql`, `package.json` (scripts `aicheck:fixtures`, `seed:files`).

**Produces:**
- **`aicheck:fixtures`** renders fictional documents with playwright (signed bid forms with a drawn signature and handwritten-style amount in words, insurance certificates, bid bonds) and rasterizes each page to an image-only PDF via screenshots and `pdf-lib`.
  - It writes `fixtures/aicheck/manifest.json`: file → kind, planted defects, expected result per item.
  - The set covers each item code with at least one `met` and one `not_met` case. The three seed defects must be included:
    - Juniper: amount in words ≠ total;
    - Basalt: no surety signature;
    - Granite: insurance ends before the due date.
  - The generated PDFs are committed (small, fictional).
- **`seed:files`** uploads the seed bids' fixture PDFs to local storage at the paths `seed.sql` references. It uses the local service key from `supabase status`; it is a local dev script only (never app code), and it refuses to run unless `NEXT_PUBLIC_SUPABASE_URL` is 127.0.0.1 or localhost.
- **`seed.sql`:** for 27-0003's four bids:
  - a scan row per signed-form log entry;
  - one `recorded = true` run each, with items matching the manifest (including the three defects).
  - Keep it after the existing 2b and 2c seed blocks.

- [ ] **Step 1:** Write a Vitest test that loads `manifest.json` and asserts every checklist code has both a `met` and a `not_met` expectation, and that the three seed defects are present.
- [ ] **Step 2:** Run it; it should fail.
- [ ] **Step 3:** Implement the scripts, generate the fixtures, and add the seed blocks.
- [ ] **Step 4:** Run `npm run db:reset && npm run seed:files && npm run db:test && npm test`. Everything should pass.
- [ ] **Step 5:** Commit `chore: AI check fixtures, seed files and recorded results`.

---

### Task 7: Evaluation, runbook and decisions

**Files:** Create `scripts/aicheck-eval.mjs`, `docs/evaluation/.gitkeep`. Modify `package.json` (`aicheck:eval`), `README.md`, `docs/decisions.md`.

**Produces:**
- **`aicheck:eval`** runs `checkDocument` and `evaluate` (live API) over every fixture.
  - It prints a per-item confusion table, the **false-met rate** (expected not_met or unclear, got met) separately from the **false-not-met rate**, and the call count.
  - It writes `docs/evaluation/YYYY-MM-DD-aicheck.md`.
  - It refuses to run without `OPENAI_API_KEY`, and prints the number of calls before starting.
- **README runbook:**
  - the env vars;
  - set a monthly spend limit and a project-scoped key in the OpenAI dashboard;
  - `AI_CHECK_ENABLED=0` on any hosted site where visitors could reach an office login;
  - `npm run seed:files` after `db:reset`.
- **`docs/decisions.md` "Slice 3, as built":** the spec's *(my call)* items, the chosen default model, and the rulings made during the build.

- [ ] **Step 1:** Write a Vitest test for the eval script's pure scoring function (`score(expected, actual)` → counts, false-met, false-not-met) with a small table.
- [ ] **Step 2:** Run it; it should fail.
- [ ] **Step 3:** Implement and write the docs.
- [ ] **Step 4:** Run the gates. Running `aicheck:eval` live is Drew's step, not part of the gates.
- [ ] **Step 5:** Commit `docs: AI check evaluation, runbook and decisions`.
