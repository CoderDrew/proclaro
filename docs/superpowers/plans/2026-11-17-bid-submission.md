# Bid Submission (Slice 2a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bidders sign up, register a company, and prepare a bid against an open solicitation (prices, uploads, bid bond). They print a pre-filled bid form, then submit, replace or withdraw before the deadline. Every submitted bid stays sealed from everyone until `bid_due_at`. The office logs mailed originals. At close, the office sees an internal tabulation computed from the stored cents, with a non-responsive flag derived from the originals log.

**Architecture:** Same model as slice 1.
- Guarantees live in Postgres. Sealed tables have no read path for any API role, including `service_role`. The sealed bucket has none for `anon` or `authenticated` before close, but `service_role` can read, replace or delete its objects and read their metadata (Ruling 3: Supabase's storage admin grants `service_role` full access to `storage.objects`, and a migration cannot revoke it). The only reads of bid tables go through security-definer functions that check `now() >= bid_due_at`.
- "Closed" is derived from the clock. It is never stored, and no scheduled job runs.
- Each state change follows one pattern: lock → own-org check → time gate → state check → guarded write → one audit row.
- Bid audit rows go to a new `bid_audit_log`, not `audit_log`. The `audit_log_read` policy from 0001 shows the owning agency every row for its solicitation, so writing there would leak who bid and when (an anti-goal).
- Pure TypeScript validation mirrors the database check, for messages. The database stays the final gate.
- The pre-filled form reuses the slice 1 `BidForm` template and Chromium renderer.

**Tech Stack:** Unchanged from slice 1: Next.js 15, React 19, TypeScript, Supabase (Postgres, Auth, Storage; `@supabase/ssr`), Zod, date-fns 4 + `@date-fns/tz`, Vitest, pgTAP, `playwright-core` + Chromium.

**Spec:** `docs/superpowers/specs/2026-11-17-bid-submission-design.md` (approved, binding). Read it before any task. Slice 1 rules are recorded in `docs/decisions.md` under "Solicitation setup slice, as built".

## Global Constraints

- **No real data.** The setting is the fictional State of Calder only. Never open or copy anything under `source-docs/`.
- **Money:** integer cents (`Cents = number`, `bigint` in SQL), never floats. Totals are computed from stored cents and never entered.
- **Time:** deadlines are shown and entered in the configured time zone (`settings.timezone`, default `America/Denver`) and stored as UTC `timestamptz`. Calendar "today" is `app.today()`.
- **Closed** is `now() >= bid_due_at`, evaluated in Postgres with `now()` (the transaction start time, never the client clock). Bid writers also refuse when the database `clock_timestamp() >= bid_due_at` after taking the bid lock. Both clocks are the database's. Closed is never stored. There is no override and no manual open step.
- **Bidding is allowed only while the solicitation is published, released (`release_date <= app.today()`) and not closed.** Submit, replace and withdraw are refused at or after `bid_due_at`.
- **Sealed from everyone, including the bidder, until the bid due time.** Bid tables are sealed from `service_role` too. Known limits: a Postgres superuser with direct database access, and the service-role key's access to `bid-files` objects in Storage (Ruling 3: read, replace or delete files, read `storage.objects.owner` and `created_at`, update the bucket row). App code never touches bid files with the admin client.
- **Agency author and anon see nothing, before or after close.** The posted recap (2b) is the only public disclosure.
- **A self-signed-up account gets no agency or office role.** Staff remain invite-only.
- **Bidder home path:** `/bidder`.
- **Bid bond, when required (estimate ≥ $150K, i.e. `estimateCents >= 15_000_000`):** either an uploaded electronic surety bond, or "paper original mailed".
- **Receipt:** time, bid reference and version number. No prices.
- **Pre-filled bid form:** bidder's prices, legal name, bid reference, and the version the draft will become. The footer keeps the slice 1 format `Solicitation {number} · Version {version} · Page {n} of {total}`. The PDF is never stored.
- **Originals log:** the received-at timestamp defaults to now and can't be in the future. Entries are append-only. A correction is a new entry that voids an earlier one, with a reason.
- **Non-responsive reason (verbatim):** `signed original not received by the bid due time`.
- **Audit rows** for submit, replace, withdrawal, original-log entry, void, and the close-time non-responsive determination.
- **Published rows are frozen.** No code path in this slice writes to `solicitations`.
- **Append-only:** `audit_log`, `bid_audit_log`, `bid_versions`, `bid_version_files`, `bid_withdrawals` and `bid_original_log` reject update, delete and truncate for every role, by trigger and by revoke.
- **New SQL only in new migrations (0007+).** Never edit 0001–0006. Use `create or replace` or drop/create a policy in a new file when an old object must change.
- **pgTAP for every policy and function.** Each new policy, `app.*` helper and `public` function has at least one assertion.
- **Definer functions:** `security definer`, `set search_path = ''`, fully qualified names, `revoke all … from public, anon, authenticated, service_role`, then `grant execute … to authenticated` only.
- **Errors** are `raise exception '<code>' using errcode = 'P0001'`. New codes: `already_registered`, `name_taken`, `not_open`, `bids_closed`, `sealed`, `invalid_bid`, `unknown_bid`, `received_in_future`, `already_voided`. Reused codes: `not_authorized`, `not_found`, `invalid_state`, `invalid_data`, `reason_required`.

## Review Focus

1. **A submit, replace or withdraw at exactly `bid_due_at`, and one second before it.** With `bid_due_at = now()`, `submit_bid`, `replace_bid`, `withdraw_bid` and `start_bid` each raise `bids_closed`. With `bid_due_at = now() + interval '1 second'`, each succeeds. Pinned in Task 4.
2. **`service_role` or the office reading a sealed bid before close.**
   - As `service_role`, any `select` on `bid_versions`, `bid_version_files`, `bid_drafts` or `bid_audit_log` raises 42501. (`storage.objects` stays readable to it: Ruling 3.)
   - Before close, office storage reads of a submitted file return 0 rows (Task 3), and `opened_bids` raises `sealed` (Task 9).
   - At exactly `bid_due_at`, both work for the office.
3. **An original logged for an older version must not count for the latest version.** v1 and v2 are submitted and a signed form is logged for v1 only. At close, the bid opens at version 2 with `original_received = false` and the verbatim reason. Pinned in Task 9.
4. **The replaced version's original.**
   - A replace that was started but never submitted leaves v1 current, and v1's logged original still counts.
   - Once v2 is submitted, v1's original is still accepted into the log (it records the mail) but counts for nothing; v2's own original counts.

   Pinned in Task 9.
5. **A bidder probing other bidders' receipts.** Bidder B calling `my_bid_receipts`, `submit_bid`, `replace_bid` or `withdraw_bid` with bidder A's bid id gets `not_found`. B's `select` on A's `bids` row returns 0 rows, and any `select` on `bid_versions` raises 42501. Pinned in Task 4.

---

## Names decided here (spec "Left to the builder")

- **Bid reference:** `XXXX-XXXX`, made of 8 characters from Crockford base32 (`0123456789ABCDEFGHJKMNPQRSTVWXYZ`, no I, L, O or U).
  - Check: `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`.
  - Generated from `extensions.gen_random_bytes(5)` (40 bits). It is unique per bid and constant across versions.
  - Office input is normalized by `app.normalize_bid_reference`: uppercase; strip spaces and hyphens; map O→0 and I/L→1; then re-hyphenate.
- **Storage:** private bucket `bid-files` (100 MB file limit). Objects live at `bids/{bid_id}/{upload_uuid}/{safe_file_name}`, keyed by uuids, never by reference or number.
- **Closed:** `app.bids_closed(p_solicitation_id) = (state = 'published' and now() >= bid_due_at)`. **Open:** `app.bidding_open(p_solicitation_id) = (state = 'published' and release_date <= app.today() and now() < bid_due_at)`.
- **Sealing for `service_role`:**
  - Revoke every table privilege on the sealed tables from `service_role`, as slice 1 did for `audit_log` updates.
  - ~~Revoke `select, insert, update, delete` on `storage.objects` from `service_role`.~~ Not possible (Task 3 BLOCKED): `storage.objects` is owned by `supabase_storage_admin`, whose grant to `service_role` a migration cannot revoke. Ruling 3 accepts it as a known limit: the service-role key can read, replace or delete `bid-files` objects and read their metadata (`owner`, `created_at`). Tamper evidence (Ruling 5) catches replacements and deletions made through the Storage API, not direct writes to the backing object store. The app never uses `service_role` for Storage: `createAdminClient` is confined to user invites.
  - Office reads of files go through the `bid_files_read` policy, gated on close, using signed URLs created with the office user's own client.
- **The version the draft will become** is stored on the draft as `bid_drafts.version` (the version the draft will become, not a lock counter). `start_bid` sets it to 1 and `replace_bid` to latest + 1. `submit_bid` asserts it equals latest + 1. The PDF reads it from the draft.
- **The close-time non-responsive determination is derived, not stored.** `app.original_received(bid_id, version, due)` counts a signed-form receipt only when all of these hold:
  - its `received_at <= bid_due_at`;
  - its `logged_at <= bid_due_at`;
  - it has not been voided.

  The determination is frozen at close, except that a void can still apply after close. A void can only make a bid less responsive, so it never accepts a late original. The audit row is written by `opened_bids` the first time it computes the result for a bid, and again only if the derived value later changes.
- **Role:** a bidder's "role" is its organization kind `bidder`, as staff roles are `agency` and `office`. No new profile column.

## File Structure

```
supabase/migrations/0007_bidder_kind.sql      enum value only (a new enum value can't be used in the same transaction)
supabase/migrations/0008_registration.sql     bidder_companies, register_bidder, agency-only solicitation policies, org visibility
supabase/migrations/0009_bids_schema.sql      bid tables, privileges, RLS, bid-files bucket and policies, bid_audit_log
supabase/migrations/0010_bid_lifecycle.sql    start/replace/submit/withdraw, receipts, office index
supabase/migrations/0011_originals_log.sql    bid_original_log, log/void, app.original_received
supabase/migrations/0012_opening.sql          opened_bids, opened_bid_files, determination audit
supabase/tests/{registration,bids_schema,bids,originals,opening}.test.sql
src/domain/bid/{types,validate}.ts            BidDraft, UploadSlot, requiredUploadSlots, validateBidDraft
src/documents/bidFill.ts, loadPublishedDocContext.ts
src/app/signup/…, src/app/register/…, src/app/bidder/…, src/app/api/bids/[bidId]/form/route.ts
src/app/office/solicitations/[id]/bids/…      originals log and tabulation
```

---

### Task 1: Bidder organization kind, registration and agency-only policies

**Files:**
- Create: `supabase/migrations/0007_bidder_kind.sql`, `supabase/migrations/0008_registration.sql`, `supabase/tests/registration.test.sql`
- Modify: `supabase/tests/00_helpers.sql`, `src/lib/supabase/database.types.ts` (generated)

**Interfaces:**
- Consumes: `app.my_org()`, `app.is_office()`, `public.organizations`, `public.profiles`, `auth.users.invited_at`.
- Produces:
  - `0007`: `alter type public.org_kind add value 'bidder';`, and nothing else in that file.
  - Table `public.bidder_companies`:
    - `org_id uuid primary key references organizations`;
    - `address`, `contact_name`, `contact_phone`, `contact_email` (all `text not null`, non-blank);
    - `resident_claimed boolean not null default false`;
    - `resident_certificate text null`, with a check that it is present (non-blank) if and only if `resident_claimed`;
    - `created_at`.

    The legal name is `organizations.name`, which is already unique.
  - `app.my_org_kind() returns public.org_kind`, `app.is_agency() returns boolean`, `app.is_bidder() returns boolean`.
  - `public.register_bidder(p_legal_name text, p_address text, p_contact_name text, p_contact_phone text, p_contact_email text, p_resident_claimed boolean, p_resident_certificate text) returns uuid`. It returns the new org id. In one transaction it inserts the organization (`kind = 'bidder'`), the `bidder_companies` row, and the profile (`display_name = contact name`, `is_admin = false`). Check order and errors:
    - no `auth.uid()`, or `auth.users.invited_at` is set → `not_authorized`;
    - a profile already exists → `already_registered`, including a unique violation on `profiles` from a concurrent call;
    - any blank field, or a claim without a certificate → `invalid_data`;
    - a unique violation on `organizations.name` → `name_taken`.
  - Policy changes:
    - Drop and recreate `solicitations_insert_draft` and `solicitations_update_draft` with `(select app.is_agency())` in place of `not (select app.is_office())`. Without this, a bidder could insert a draft with `agency_id` set to its own org.
    - Drop and recreate `organizations_read`: `kind <> 'bidder' or id = (select app.my_org()) or (select app.is_office())`. Registered bidders are not a public list.
    - `bidder_companies`: `select` for its own org's members or office staff; no write grants, so registration goes through the function only.
  - Test helpers:
    - `tests.make_auth_user(p_email text, p_invited boolean default false) returns uuid`: an auth user with no profile.
    - `tests.make_bidder(p_email text, p_org_name text) returns uuid`: a bidder org, its company row, and a user.
    - `tests.act_as_service_role()`.

- [ ] **Step 1: Write failing pgTAP tests** in `registration.test.sql`:
  - An unregistered user calling `register_bidder('Ridgeback Builders LLC', '12 Quarry Rd, Calder City', 'Ana Ridge', '555-0142', 'ana@ridgeback.example.test', true, 'CR-0042')` gets a uuid. That org's `kind = 'bidder'`, the caller's profile has that `org_id` and `is_admin = false`, and the `bidder_companies` row stores `CR-0042`.
  - Calling it again raises `already_registered`. So does a call from a seeded agency user.
  - An invited user (`invited_at` set, no profile) gets `not_authorized`. Anon gets 42501.
  - `p_legal_name = '  '` gives `invalid_data`. `p_resident_claimed = true` with a null certificate gives `invalid_data`. A legal name equal to an existing org's name gives `name_taken`.
  - Calling as a bidder:
    - `insert into solicitations (agency_id, created_by, data)` with its own org id throws 42501;
    - it sees 0 agency drafts;
    - `submit_solicitation` on an agency draft raises `not_authorized`.
  - Anon sees the office and agency orgs but 0 bidder orgs. Bidder A sees its own org and not bidder B's; the office sees both.
  - `bidder_companies`: bidder A sees 1 row (its own); the office sees 2; agency users see 0; anon throws 42501.
  - `app.is_agency()` is false for a bidder and true for an agency author.
- [ ] **Step 2:** Run `npm run db:reset && npm run db:test`; expect failures.
- [ ] **Step 3:** Write `0007` and `0008`.
- [ ] **Step 4:** Run `npm run db:reset && npm run db:test`; expect all to pass, including every slice 1 file. Run `npm run db:types`.
- [ ] **Step 5:** Commit: `feat(db): bidder organizations and registration`.

---

### Task 2: Self-signup, "Register your company" and the bidder home

**Files:**
- Create:
  - `src/app/signup/page.tsx`, `src/app/signup/actions.ts`, `src/app/signup/logic.ts`
  - `src/app/register/page.tsx`, `src/app/register/actions.ts`, `src/app/register/logic.ts`
  - `src/app/bidder/guard.ts`, `src/app/bidder/page.tsx`
- Modify: `supabase/config.toml` (`enable_signup = true`), `src/lib/session.ts`, `src/middleware.ts`, `src/app/login/actions.ts`, `src/app/login/page.tsx` (add a "Create an account" link), `src/app/page.tsx`
- Test: `src/lib/session.test.ts`, `src/app/signup/logic.test.ts`, `src/app/register/logic.test.ts`

**Interfaces:**
- Consumes: `register_bidder` (Task 1), `validateNewPassword` (`src/app/auth/logic.ts`), `onlyPublic` and `bidStatus` (`src/app/solicitations/status.ts`).
- Produces:
  - `SessionContext.orgKind: "agency" | "office" | "bidder"`. `homePathFor` returns `/bidder` for a bidder; an admin still goes to `/admin` first.
  - `type AuthState = { status: "signed_out" } | { status: "unregistered"; userId: string; invited: boolean } | { status: "member"; ctx: NonNullable<SessionContext> }`
  - `getAuthState(): Promise<AuthState>`. `getSessionContext()` keeps its contract and returns null for an unregistered user.
  - `landingPathFor(s: AuthState): string`. It returns `/login` for signed out, `/register` for unregistered and not invited, `/login` for unregistered and invited, and otherwise `homePathFor(ctx)`.
  - `validateSignup(email: unknown, password: unknown, confirm: unknown): { email: string; password: string } | { error: string }`. It reuses `validateNewPassword`.
  - `parseRegistration(form: Record<string, unknown>): { ok: true; value: RegistrationInput } | { ok: false; message: string }`, where `RegistrationInput` mirrors the `register_bidder` parameters.
  - `signUp(prev, formData)` server action: `supabase.auth.signUp`, then redirect to `/register`. If no session comes back (email confirmation turned on later), show "Check your email to confirm your account."
  - `registerCompany(prev, formData)` server action. It maps `name_taken` to "A company with that legal name is already registered." and `already_registered` to a redirect to the home path.
  - `requireBidderPage()` / `requireBidderAction()`, following the agency guard pattern.
  - Login: a user with no profile is redirected to `/register` instead of being signed out, unless invited, which keeps the existing message. Middleware adds `/bidder` and `/register` to `PROTECTED`.
  - `/bidder` lists released, open solicitations (`onlyPublic(...)` plus `bid_due_at > now`), showing the number, title, bid due (local time) and a "Prepare a bid" link to `/bidder/solicitations/{id}`.

- [ ] **Step 1: Write failing tests:**
  - `homePathFor({ ...ctx, orgKind: "bidder", isAdmin: false })` is `/bidder`.
  - `landingPathFor({ status: "unregistered", userId: "u", invited: false })` is `/register`; with `invited: true` it is `/login`.
  - `validateSignup("a@b.test", "short", "short")` gives the 8-character error. Mismatched confirm gives "The passwords do not match."
  - `parseRegistration`:
    - a blank legal name gives "Enter the company's legal name.";
    - `residentClaimed: "on"` with no certificate gives "Enter the resident certificate number.";
    - trimmed values pass through.
- [ ] **Step 2:** Run `npm test -- session signup register`; expect FAIL. Implement; expect PASS.
- [ ] **Step 3:** Flip `enable_signup = true`. Email confirmations stay off locally, as now. Build the screens.
- [ ] **Step 4: Verify manually** (`npm run dev`, after `npm run db:reset`):
  - Sign up `new.bidder@example.test`, land on `/register`, register "Granite Mesa Contractors", land on `/bidder`.
  - Signing in again goes straight to `/bidder`.
  - `/agency` and `/office` redirect to `/bidder`.
- [ ] **Step 5:** Commit: `feat(app): bidder self-signup, registration and home`.

---

### Task 3: Bid tables, sealing privileges and the sealed bucket

**Files:**
- Create: `supabase/migrations/0009_bids_schema.sql`, `supabase/tests/bids_schema.test.sql`
- Modify: `supabase/tests/00_helpers.sql`, `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: Task 1 helpers, `app.reject_change()`, `app.today()`.
- Produces:
  - Types: `public.bid_bond_choice` (`electronic`, `paper`) and `public.bid_upload_slot` (`insurance`, `qualifications`, `references`, `current_work`, `bid_bond`).
  - Tables:
    - `bids`: `id uuid pk`, `solicitation_id`, `bidder_org_id`, `reference text unique not null` (with the reference check), `created_by`, `created_at`, `unique (solicitation_id, bidder_org_id)`.
    - `bid_drafts`: `bid_id uuid pk references bids on delete cascade`, `version int not null check (version > 0)`, `item_cents bigint[] not null default '{}'`, `alternate_cents bigint[] not null default '{}'`, `bid_bond_choice null`, `updated_at`. Check `0 <= all(x) and 999999999999 >= all(x)` on both arrays; nulls are allowed while drafting.
    - `bid_draft_files`: `bid_id references bid_drafts on delete cascade`, `slot bid_upload_slot`, `path text unique not null`, `file_name text not null`, `primary key (bid_id, slot)`.
    - `bid_versions`: `id uuid pk`, `bid_id`, `version int`, `submitted_at timestamptz default now()`, `submitted_by`, `item_cents bigint[] not null`, `alternate_cents bigint[] not null`, `bid_bond_choice null`, `unique (bid_id, version)`. Same range check as drafts, plus `array_position(x, null) is null`.
    - `bid_version_files`: `version_id`, `slot`, `path text unique`, `file_name`, `primary key (version_id, slot)`.
    - `bid_withdrawals`: `bid_id`, `version`, `withdrawn_at default now()`, `withdrawn_by`, `primary key (bid_id, version)`, with a foreign key to `bid_versions (bid_id, version)`.
    - `bid_audit_log`: `id bigserial`, `solicitation_id not null`, `bid_id null`, `actor_id`, `action text`, `detail jsonb`, `created_at`.
  - Helpers (`stable security definer`):
    - `app.bidding_open(uuid)` and `app.bids_closed(uuid)`, as defined above;
    - `app.latest_version(p_bid_id uuid) returns int` (null if none);
    - `app.is_withdrawn(p_bid_id uuid, p_version int) returns boolean`;
    - `app.path_bid_id(p_name text) returns uuid`, which matches `^bids/{uuid}/{uuid}/[^/]+$` and rejects `..`.
  - Privileges:
    - `revoke all` on every table above from `anon, authenticated, service_role`.
    - Grant back to `authenticated` only:
      - `select` on `bids`, `bid_drafts`, `bid_draft_files` and `bid_audit_log`;
      - `update (item_cents, alternate_cents, bid_bond_choice)` on `bid_drafts`;
      - `insert (bid_id, slot, path, file_name), delete` on `bid_draft_files`.
    - No privileges on `bid_versions`, `bid_version_files` or `bid_withdrawals` for any API role.
    - ~~`revoke select, insert, update, delete on storage.objects from service_role`~~ (not possible; Ruling 3 accepts the limit).
  - Append-only triggers (`app.reject_change`) for update and delete on `bid_versions`, `bid_version_files`, `bid_withdrawals` and `bid_audit_log`, plus a truncate trigger on `bid_audit_log`.
  - RLS policies:
    - `bids_read_own`, `bid_drafts_read_own` and `bid_draft_files_read_own`: `bidder_org_id = app.my_org()`, through the bid.
    - `bid_drafts_update_own`: own org and `app.bidding_open(solicitation)`.
    - `bid_draft_files_insert_own` / `_delete_own`: own org and bidding open. The insert check also requires `path like 'bids/' || bid_id || '/%'` and `app.path_bid_id(path) = bid_id`.
    - `bid_audit_log_read`: `app.is_office() and app.bids_closed(solicitation_id)`.
  - Bucket `bid-files` (private, 104857600). Storage policies:
    - `bid_files_insert` via `app.can_upload_bid_file(name)`: own bid and bidding open.
    - `bid_files_read` via `app.can_read_bid_file(name)`: either (a) own org, the path is in that bid's `bid_draft_files`, and it is not in any `bid_version_files`; or (b) office, `bids_closed`, and the path belongs to the bid's latest version, which is not withdrawn.
    - `bid_files_delete` via `app.can_delete_bid_file(name)`: own org, bidding open, and not in `bid_version_files`.
  - Test helpers:
    - `tests.make_published_solicitation(p_agency uuid, p_author uuid, p_bid_due_at timestamptz, p_overrides jsonb default '{}') returns uuid`. It inserts the row directly as `published`, which the frozen trigger allows because it only fires on update and delete. It sets `release_date = app.today()`, `version = 1`, a number, and `published_snapshot = {data, clauses: {}, settings: {}}`. The default data has two schedule items, one deductive alternate, `estimateCents = 15000000` and `optionalSections = ["references"]`.
    - `tests.set_bid_due(p_id uuid, p_at timestamptz)`. It disables `solicitations_published_frozen`, updates, then re-enables the trigger. It is used only inside a rolled-back test transaction.

- [ ] **Step 1: Write failing pgTAP tests** in `bids_schema.test.sql`. Insert bids and a submitted version directly as the test superuser; the functions come in Task 4.
  - Bidder A sees its own `bids`, `bid_drafts` and `bid_draft_files` rows. Bidder B, the office and an agency author each see 0. Anon `select` on `bids` throws 42501.
  - **Review Focus 2:**
    - As bidder A, as office, and as `tests.act_as_service_role()`, a `select` on `bid_versions`, `bid_version_files` or `bid_withdrawals` throws 42501.
    - As `service_role`, a `select` on `bid_drafts`, `bids` or `bid_audit_log` throws 42501. (`storage.objects` is readable to it: Ruling 3.)
  - Bidder A's `update bid_drafts set item_cents = '{12500000,234567}'` changes 1 row while open. After `tests.set_bid_due(sol, now())`, the same update changes 0 rows. `update bid_drafts set version = 9` throws 42501. Setting `item_cents = '{-1}'` throws 23514.
  - Storage:
    - Bidder A can insert `bids/{A}/{uuid}/q.pdf` while open. Inserting under `bids/{B}/…` throws, and so does inserting after close.
    - Bidder A reads its draft-referenced object (1 row). Once that path is also in `bid_version_files`, bidder A reads 0 rows.
    - The office reads 0 rows before close. After close it reads 1 row for the latest version's file. It reads 0 if that version is withdrawn, and 0 for a superseded version's file.
  - Inserting `bid_draft_files` with a path already in `bid_version_files` fails (unique). A path outside `bids/{bid_id}/` fails RLS.
  - Every role, the superuser included, gets an error on `update` or `delete` of `bid_versions`, `bid_version_files`, `bid_withdrawals` and `bid_audit_log`, and on `truncate bid_audit_log`.
  - `bid_audit_log`: the office reads 0 rows before close and sees the rows after close. An agency author sees 0, and bidder A sees 0.
- [ ] **Step 2:** Run `npm run db:reset && npm run db:test`; expect failures.
- [ ] **Step 3:** Write `0009_bids_schema.sql`.
- [ ] **Step 4:** Run `npm run db:reset && npm run db:test`; expect PASS. If the `storage.objects` revoke does not survive `db reset` (the Storage service re-granting on boot), **stop and report to Drew. Do not work around it.** The fallback, sealed files as `bytea` in a revoked table, is a design change. Run `npm run db:types`.
- [ ] **Step 5:** Commit: `feat(db): sealed bid tables, privileges and bid-files bucket`.

---

### Task 4: Bid lifecycle functions: start, replace, submit, withdraw, receipts

**Files:**
- Create: `supabase/migrations/0010_bid_lifecycle.sql`, `supabase/tests/bids.test.sql`
- Modify: `src/lib/supabase/database.types.ts`

**Interfaces:**
- Consumes: Task 3.
- Produces:
  - Helpers (`app`, revoked from all API roles):
    - `app.new_bid_reference() returns text`, which retries on collision up to 5 times;
    - `app.normalize_bid_reference(text) returns text`;
    - `app.lock_bid(p_bid_id uuid) returns public.bids` (`for update`, otherwise `not_found`);
    - `app.bonds_required(p_snapshot jsonb) returns boolean` (`(data->>'estimateCents')::bigint >= 15000000`);
    - `app.required_bid_slots(p_snapshot jsonb, p_choice public.bid_bond_choice) returns public.bid_upload_slot[]`. It returns `insurance`, then each `optionalSections` entry in snapshot order, then `bid_bond` when bonds are required and the choice is `electronic`;
    - `app.bid_draft_problems(p_bid_id uuid) returns text[]`. Its codes match TypeScript `BidIssueCode` (Task 5): `price_count`, `price_missing`, `upload_missing`, `file_missing` (no `storage.objects` row for a draft path), `bond_choice_missing`, `bond_not_required`.
  - Public functions (`grant execute to authenticated` only). Check order:
    1. bidder org kind (`not_authorized`);
    2. lock the bid; another org's bid gives `not_found`;
    3. `bids_closed` gives `bids_closed`;
    4. not published or not released gives `not_open`;
    5. state (`invalid_state`);
    6. `invalid_bid`.
  - `start_bid(p_solicitation_id uuid) returns uuid`. It creates the bid (with a new reference) and a draft with `version = 1`. It is idempotent while that draft exists. If the bid already has versions, it raises `invalid_state` (use replace). No audit row, since a draft is not on the spec's audit list.
  - `replace_bid(p_bid_id uuid) returns void`. It needs a submitted version (withdrawn is fine) and no draft. It inserts an empty draft with `version = latest + 1`. Audit `replace_bid` with `{from_version, draft_version}`.
  - `submit_bid(p_bid_id uuid) returns table (reference text, version int, submitted_at timestamptz)`. It needs a draft whose `version = coalesce(latest, 0) + 1` and empty `bid_draft_problems`; otherwise it raises `invalid_bid`, with the codes in the exception `detail`. It inserts the `bid_versions` row and the file rows, then deletes the draft. Audit `submit_bid` with `{reference, version, supersedes}`. **Never include prices in audit detail.**
  - `withdraw_bid(p_bid_id uuid) returns void`. The latest version must exist and not already be withdrawn. It inserts into `bid_withdrawals` and leaves any draft in place. Audit `withdraw_bid` with `{version}`.
  - `my_bid_receipts(p_bid_id uuid) returns table (reference text, version int, submitted_at timestamptz, withdrawn_at timestamptz, is_current boolean)`. Own org only; otherwise `not_found`. No prices or files.
  - `office_bid_index(p_solicitation_id uuid) returns table (reference text, version int, status text)`. Office only. `status` is one of `current`, `superseded` or `withdrawn`. No org, time or prices. Before close, this is the whole of what the office can see.

- [ ] **Step 1: Write failing pgTAP tests** in `bids.test.sql`. Use `tests.make_published_solicitation` due in 1 day, and seed draft objects into `bid-files` as the bidder.
  - `start_bid` returns an id; the reference matches the reference check and the draft has `version = 1`. A second call returns the same id. An agency or office caller gets `not_authorized`. An unreleased solicitation (`release_date = app.today() + 1`) gives `not_open`.
  - `app.normalize_bid_reference(' k7qm 2xvo ')` is `K7QM-2XV0`.
  - `submit_bid` on an empty draft raises `invalid_bid`, and `app.bid_draft_problems` contains `price_missing` and `upload_missing`.
  - After filling prices `{12500000,234567}` / `{1500000}`, choosing `paper`, and attaching `insurance` and `references`:
    - `submit_bid` returns version 1 with `submitted_at = now()`;
    - the draft is gone;
    - there is 1 `submit_bid` audit row, and its `detail` has no key containing `cents`;
    - a second `submit_bid` raises `invalid_state`.
  - Choosing `electronic` without a `bid_bond` file gives `upload_missing`. A draft row whose path has no storage object gives `file_missing`.
  - `replace_bid` creates draft version 2. A second `replace_bid` raises `invalid_state`. After submitting v2, the receipts show v1 `is_current = false` and v2 `is_current = true`.
  - `withdraw_bid`:
    - v2 gets `withdrawn_at`, and a second withdraw raises `invalid_state`;
    - `office_bid_index` returns v1 `superseded` and v2 `withdrawn`;
    - `replace_bid` then yields draft v3, which submits as current.
  - **Review Focus 1:**
    - With `tests.set_bid_due(sol, now() + interval '1 second')`, `submit_bid`, `withdraw_bid`, `replace_bid` and `start_bid` (each on its own fixture bid) all succeed.
    - After `tests.set_bid_due(sol, now())`, each raises `bids_closed`.
  - **Review Focus 5:**
    - Bidder B calling `my_bid_receipts`, `submit_bid`, `replace_bid` or `withdraw_bid` with A's bid id raises `not_found`.
    - B's `select * from bids where id = A` returns 0 rows.
    - The office calling `my_bid_receipts` gets `not_authorized`, and a bidder calling `office_bid_index` gets `not_authorized`.
  - Anon and `service_role` calling any of the six functions get 42501.
- [ ] **Step 2:** Run `npm run db:test`; expect failures.
- [ ] **Step 3:** Write `0010_bid_lifecycle.sql`.
- [ ] **Step 4:** Run `npm run db:reset && npm run db:test`; expect PASS. Run `npm run db:types`.
- [ ] **Step 5:** Commit: `feat(db): time-gated bid submit, replace, withdraw and receipts`.

---

### Task 5: Bid domain rules and the bidder draft screen

**Files:**
- Create:
  - `src/domain/bid/types.ts`, `src/domain/bid/validate.ts`
  - `src/app/bidder/solicitations/[id]/page.tsx`, `BidDraftForm.tsx`, `actions.ts`, `logic.ts`
  - `src/components/BidFileUploader.tsx`
- Modify: `supabase/seed.sql` (the bidder and solicitation seed described in Task 10, added here so this and later tasks can be walked manually)
- Test: `src/domain/bid/validate.test.ts`, `src/app/bidder/solicitations/[id]/logic.test.ts`

**Interfaces:**
- Consumes: `Cents`, `parseMoney`, `formatMoney`, `deriveRequirements`, `BONDS_AT`, `SECTION_LABELS`, `safeFileName` (agency logic), `parseStoredData`, `start_bid`, the Task 3 tables.
- Produces:

```ts
type UploadSlot = "insurance" | "qualifications" | "references" | "current_work" | "bid_bond";
type BidBondChoice = "electronic" | "paper";
interface BidDraft {
  bidId: string; reference: string; version: number;          // version = the version it will become
  itemCents: (Cents | null)[]; alternateCents: (Cents | null)[];
  bidBondChoice: BidBondChoice | null;
  files: { slot: UploadSlot; path: string; fileName: string }[];
}
type BidIssueCode = "price_count" | "price_missing" | "upload_missing" | "file_missing" | "bond_choice_missing" | "bond_not_required";
interface BidIssue { code: BidIssueCode; field: string; message: string }   // field e.g. "items.1", "uploads.references"
const MAX_PRICE_CENTS = 999_999_999_999;
requiredUploadSlots(data: SolicitationData, choice: BidBondChoice | null): UploadSlot[]
validateBidDraft(draft: BidDraft, data: SolicitationData): BidIssue[]   // file_missing is database-only
baseTotalCents(itemCents: Cents[]): Cents
```

- `logic.ts`:
  - `parsePriceInputs(inputs: string[], expected: number): { ok: true; cents: (Cents | null)[] } | { ok: false; message: string }`. A blank input becomes null.
  - `bidUploadPath(bidId: string, uploadId: string, fileName: string): string`
  - `assertOwnBidPath(bidId: string, path: string): void`, which throws `invalid_upload_path`.
  - `type BidActionResult<T = object> = ({ ok: true } & T) | { ok: false; message: string }`
  - `bidMessageFor(e: unknown): string`. It maps `bids_closed` to "Bidding on this solicitation has closed.", plus `not_open`, `invalid_state`, `invalid_bid` and `not_found`.
- `actions.ts` (server actions; RLS and policies do the enforcing):
  - `startBid(solicitationId)`
  - `saveBidPrices(bidId, { items: string[]; alternates: string[] })`
  - `setBidBondChoice(bidId, choice: BidBondChoice | null)`
  - `createBidUploadUrl(bidId, slot, fileName): Promise<{ path; token }>`. Files go browser → Storage, never through an action body.
  - `attachBidFile(bidId, slot, path, fileName)`, which deletes then inserts the slot row
  - `removeBidFile(bidId, slot)`
- The page shows:
  - a price row per schedule item and alternate, in bid form order, with alternates labelled "Alternate {n} (add|deduct)";
  - the computed base total;
  - one upload slot per required section;
  - the bond choice, only when `bonds`;
  - the reference and "This draft will be submitted as version {n}";
  - the bid due time (local).

  Everything is read-only when closed.

- [ ] **Step 1: Write failing tests.** The fixture solicitation has 2 items, 1 deductive alternate, an estimate of $150,000.00 and `optionalSections: ["references"]`, matching the pgTAP fixture.
  - `requiredUploadSlots(data, "paper")` is `["insurance", "references"]`; with `"electronic"` it is `["insurance", "references", "bid_bond"]`.
  - At `estimateCents: 14_999_999`, choice `null`, it is `["insurance", "references"]`, and choosing `"paper"` gives `bond_not_required`.
  - A complete draft has zero issues. A null `itemCents[1]` gives `{ code: "price_missing", field: "items.1" }`. Three item prices give `price_count`. No choice at $150,000.00 gives `bond_choice_missing`.
  - `baseTotalCents([12_500_000, 234_567])` is `12_734_567`.
  - `parsePriceInputs(["$125,000", "2,345.67"], 2)` gives `[12_500_000, 234_567]`. `["12.345", ""]` gives `{ ok: false, message: "Item 1: enter a dollar amount like 12,500.00" }`. `["", ""]` gives `[null, null]`.
  - `assertOwnBidPath("b1…", "bids/other/…/x.pdf")` throws `invalid_upload_path`.
- [ ] **Step 2:** Run `npm test -- bid`; expect FAIL. Implement; expect PASS.
- [ ] **Step 3:** Build the page, form and uploader.
- [ ] **Step 4: Verify manually:** after `npm run db:reset`, as `bidder.ridgeback@example.test` on the seeded open solicitation, enter prices, upload insurance and references, and choose the bond option. Reload and everything persists. Another bidder's URL shows nothing of it.
- [ ] **Step 5:** Commit: `feat(bidder): bid draft with prices, uploads and bid bond choice`.

---

### Task 6: Pre-filled bid form PDF from the draft

**Files:**
- Create: `src/documents/bidFill.ts`, `src/documents/loadPublishedDocContext.ts`, `src/app/api/bids/[bidId]/form/route.ts`
- Modify: `src/documents/templates/BidForm.tsx`, `src/documents/templates/BidFormSections.tsx`, `src/documents/renderHtml.ts`
- Test: `src/documents/renderHtml.test.ts`, `src/documents/bidFill.test.ts`, `src/documents/loadPublishedDocContext.test.ts`

**Interfaces:**
- Consumes: `renderBidFormHtml`, `renderPdf`, `chromiumRenderer`, `footerTemplate`, `formatMoney`, `baseTotalCents`, `BidDraft`, `bidder_companies`.
- Produces:

```ts
interface BidFill {
  legalName: string; address: string; contact: string;        // "Ana Ridge, 555-0142, ana@…"
  residentClaimed: boolean; residentCertificate: string | null;
  reference: string; bidVersion: number;
  itemCents: Cents[]; alternateCents: Cents[];                // complete; no nulls
  bidBond: BidBondChoice | null;
}
toBidFill(company: BidderCompany, legalName: string, draft: BidDraft): BidFill | { incomplete: true }  // any null price → incomplete
renderBidFormHtml(ctx: DocContext, opts: { draft: boolean; fill?: BidFill }): string
loadPublishedDocContext(supabase, solicitationId): Promise<DocContext>   // number, version and published_snapshot {data, clauses, settings}
```

- The published snapshot's clauses are used, never the live latest clauses: clause locks are invisible to bidders, and clauses may have changed since publishing.
- With `fill`:
  - every page carries `<p data-bid-ref>Bid reference {reference} · Bid version {n}</p>`;
  - each `data-bid-schedule` and `data-bid-alternates` price cell shows `formatMoney`;
  - `data-bid-total` shows `formatMoney(baseTotalCents)`;
  - the bond line reads "Electronic surety bond uploaded" or "Paper original mailed";
  - the page 3 firm name, address, contact and resident claim are filled. License numbers and addenda stay blank write-ins (2c).
- The footer is unchanged: `footerTemplate({ draft: false, number, version })`, the solicitation version.
- `GET /api/bids/{bidId}/form`:
  - the caller's own client reads the draft (RLS, so another org's draft gives 404);
  - no draft gives 404;
  - an incomplete fill gives 409 "Enter every price before printing the bid form.";
  - otherwise it streams `application/pdf` with `Cache-Control: private, no-store` and stores nothing.

- [ ] **Step 1: Write failing tests:**
  - Render with fill `{ legalName: "R&D Builders <Calder>", reference: "K7QM-2XVD", bidVersion: 2, itemCents: [12_500_000, 234_567], alternateCents: [1_500_000], bidBond: "paper", … }`:
    - the HTML contains `R&amp;D Builders &lt;Calder&gt;`;
    - the schedule cells read `$125,000.00` and `$2,345.67` in that order, the alternate cell reads `$15,000.00`, and the total reads `$127,345.67`;
    - there are 4 `data-bid-ref` elements reading `Bid reference K7QM-2XVD · Bid version 2`;
    - `extractFooterTemplate(html)` is exactly `Solicitation 27-0001 · Version 1 · Page {n} of {total}`;
    - the bond line contains `Paper original mailed`.
  - Without `fill`, the output is byte-identical to the current slice 1 render for the same ctx (snapshot test).
  - `toBidFill` with a null price gives `{ incomplete: true }`.
  - `loadPublishedDocContext`, with a stub client, uses `published_snapshot.clauses` even when the `clauses` table holds a newer version.
- [ ] **Step 2:** Run `npm test -- documents`; expect FAIL. Implement; expect PASS.
- [ ] **Step 3:** Add a "Print bid form (version {n})" link to the draft page.
- [ ] **Step 4: Verify manually:** download the PDF from the draft page. The prices and total match the screen, the page footer reads `Solicitation … · Version 1 · Page 1 of 4`, and each page shows the bid reference and version.
- [ ] **Step 5:** Commit: `feat(documents): pre-filled bid form from the bid draft`.

---

### Task 7: Submit, replace, withdraw and receipts in the bidder UI

**Files:**
- Modify: `src/app/bidder/solicitations/[id]/page.tsx`, `actions.ts`, `logic.ts`, `src/app/bidder/page.tsx` (show "My bids" with each bid's current receipt)
- Test: `src/app/bidder/solicitations/[id]/logic.test.ts`

**Interfaces:**
- Consumes: `submit_bid`, `replace_bid`, `withdraw_bid`, `my_bid_receipts`, `validateBidDraft`, `formatInstant`.
- Produces:
  - `interface BidReceipt { reference: string; version: number; submittedAt: string; withdrawnAt: string | null; isCurrent: boolean }`
  - `interface SubmitBidDeps { loadDraft(bidId: string): Promise<{ draft: BidDraft; data: SolicitationData } | null>; submit(bidId: string): Promise<BidReceipt> }`
  - `runSubmitBid(bidId: string, deps: SubmitBidDeps): Promise<BidActionResult<{ receipt: BidReceipt }> | { ok: false; message: string; issues: BidIssue[] }>`. It re-validates the stored draft, never client data, before calling the database.
  - Server actions `submitBid(bidId)`, `replaceBid(bidId)` and `withdrawBid(bidId)`, each returning `BidActionResult`.
  - The receipt panel lists every version: "Version {n} · submitted {local time} · reference {ref}", marked "current", "superseded" or "withdrawn {local time}". Never prices.
  - After submit: "Mail the signed bid form showing bid version {n}. It must be received by {bid due, local}."
  - The replace confirmation reads: "Replacing starts a new, empty draft. Version {n} still counts until you submit the replacement, which needs its own signed form." The withdraw confirmation reads: "Withdraw version {n}? It will not be opened. You can still submit a new version before {due}."

- [ ] **Step 1: Write failing tests:**
  - `runSubmitBid` with a draft missing a price returns the issues and never calls `submit`.
  - With a clean draft it calls `submit` once and returns the receipt.
  - `submit` throwing `Error("bids_closed")` returns `{ ok: false, message: "Bidding on this solicitation has closed." }`.
  - `Error("invalid_bid")` returns "The bid is incomplete. Reload the page and check every item."
- [ ] **Step 2:** Run; expect FAIL. Implement; expect PASS.
- [ ] **Step 3:** Build the buttons and the receipt panel. Hide submit, replace and withdraw when closed; the database refuses regardless.
- [ ] **Step 4: Verify manually:**
  - Submit, and the receipt shows v1 with no prices; the draft prices are gone.
  - Replace, and the new draft is empty and labelled version 2; the printed form shows "Bid version 2".
  - Submit v2, withdraw it, then submit v3.
  - Running `select * from bid_versions` with the bidder's JWT through the REST API fails with 42501.
- [ ] **Step 5:** Commit: `feat(bidder): submit, replace, withdraw and receipts`.

---

### Task 8: Office originals log with voids

**Files:**
- Create:
  - `supabase/migrations/0011_originals_log.sql`, `supabase/tests/originals.test.sql`
  - `src/app/office/solicitations/[id]/bids/page.tsx`, `actions.ts`, `logic.ts`
- Modify: `src/app/office/solicitations/[id]/page.tsx` (link to "Bids" for published rows), `src/lib/supabase/database.types.ts`
- Test: `src/app/office/solicitations/[id]/bids/logic.test.ts`

**Interfaces:**
- Consumes: `office_bid_index`, `app.normalize_bid_reference`, `app.bids_closed`, `toUtc`, `formatInstant`, `requireOfficeAction`.
- Produces:
  - Type `public.original_item` (`signed_form`, `bid_bond`).
  - Table `bid_original_log`:
    - columns: `id uuid pk`, `solicitation_id`, `bid_id`, `reference`, `version`, `item original_item not null`, `received_at timestamptz null`, `voids_entry_id uuid null unique references bid_original_log`, `reason text null`, `logged_by`, `logged_at timestamptz not null default now()`;
    - check: either a receipt (`voids_entry_id is null and received_at is not null and reason is null`) or a void (`voids_entry_id is not null and received_at is null and btrim(reason) <> ''`);
    - append-only by trigger and revoke;
    - `select` granted to `authenticated` with policy `app.is_office()`; nothing for `service_role`.
  - `public.log_bid_original(p_solicitation_id uuid, p_reference text, p_version int, p_item public.original_item, p_received_at timestamptz default null) returns uuid`.
    - It is office only.
    - The normalized reference and version must be an existing `bid_versions` row of a bid on that solicitation (superseded and withdrawn versions included); otherwise `unknown_bid`.
    - `p_received_at > now()` gives `received_in_future`, and null means `now()`.
    - Logging after close is allowed. The entry is recorded and audited, but Task 9 does not count it.
    - Audit `log_bid_original` with `{entry_id, reference, version, item, received_at}`.
  - `public.void_bid_original(p_entry_id uuid, p_reason text) returns uuid`.
    - It is office only. A missing entry gives `not_found`, a blank reason gives `reason_required`, a target that is itself a void gives `invalid_state`, and an already-voided target gives `already_voided`.
    - It inserts a void row copying `bid_id`, `reference`, `version` and `item` from the target.
    - Audit `void_bid_original` with `{entry_id, voids_entry_id, reason}`.
  - `app.original_received(p_bid_id uuid, p_version int, p_due timestamptz) returns boolean`. It is true when there is a `signed_form` receipt for that version with `received_at <= p_due` and `logged_at <= p_due`, which has no void row (a void made at any time counts).
  - `logic.ts`:
    - `parseReceivedAt(local: string, tz: string, now: Date): { ok: true; at: Date | null } | { ok: false; message: string }`. Blank becomes null; a future time gives "The received time can't be in the future."
    - `parseVersion(s: string): number | null`
    - `runLogOriginal(solicitationId, input, deps)` and `runVoidOriginal(entryId, reason, deps)`, which return `ActionResult`. Message for `unknown_bid`: "No submitted bid {reference} version {v} on this solicitation."
  - Page `/office/solicitations/{id}/bids`:
    - the `office_bid_index` table (reference, version, status);
    - the log form: reference, version, item, and received at (`datetime-local` in the configured zone, defaulting to now);
    - entries, newest first, with void buttons that ask for a reason. Voided entries are struck through.

- [ ] **Step 1: Write failing tests.**
  - pgTAP, `originals.test.sql`:
    - The office logs `(' k7qm 2xvd ', 1, 'signed_form')` and gets a uuid. The stored reference is `K7QM-2XVD`, `received_at = now()`, and there is 1 `log_bid_original` audit row.
    - Errors from logging:
      - an unknown reference, version 3 when only 2 exist, and another solicitation's reference each give `unknown_bid`;
      - `p_received_at = now() + interval '1 second'` gives `received_in_future`;
      - a bidder or agency caller gets `not_authorized`;
      - anon and `service_role` get 42501.
    - Voids:
      - a void with reason `''` gives `reason_required`;
      - a valid void writes a row and a `void_bid_original` audit row;
      - voiding it again gives `already_voided`, and voiding the void gives `invalid_state`.
    - Visibility: a bidder or agency author sees 0 log rows, and the office sees all of them. `update` and `delete` throw for every role.
    - After `tests.set_bid_due(sol, now() - interval '1 second')`, logging still succeeds.
    - `app.original_received`, using direct inserts with explicit timestamps and `due = '2026-08-31 19:00Z'`:
      - received and logged at exactly the due time → true;
      - received at `due + 1 second` → false;
      - received at `due - 1 hour` but logged at `due + 1 minute` (backdated after close) → false;
      - voided before the due time → false;
      - voided after the due time → false;
      - a `bid_bond` receipt alone → false.
  - Vitest:
    - `parseReceivedAt("2026-08-31T12:59", "America/Denver", new Date("2026-08-31T19:30:00Z"))` gives `2026-08-31T18:59:00.000Z`;
    - with now `2026-08-31T18:58:00Z` it is refused;
    - `parseVersion("0")` and `parseVersion("x")` are null;
    - `runVoidOriginal` with a blank reason never calls the database.
- [ ] **Step 2:** Run `npm run db:test` and `npm test -- bids/logic`; expect FAIL.
- [ ] **Step 3:** Write the migration and the logic; build the page.
- [ ] **Step 4:** Run `npm run db:reset && npm run db:test && npm test`; expect PASS. Run `npm run db:types`. Verify manually: before close, the office page shows only references, versions and statuses, and logging and voiding work.
- [ ] **Step 5:** Commit: `feat(office): originals log with voids`.

---

### Task 9: Close, the derived non-responsive rule, and the internal tabulation

**Files:**
- Create: `supabase/migrations/0012_opening.sql`, `supabase/tests/opening.test.sql`, `src/app/office/solicitations/[id]/bids/tabulation.ts`
- Modify: `src/app/office/solicitations/[id]/bids/page.tsx`, `src/lib/supabase/database.types.ts`
- Test: `src/app/office/solicitations/[id]/bids/tabulation.test.ts`

**Interfaces:**
- Consumes: `app.bids_closed`, `app.latest_version`, `app.is_withdrawn`, `app.original_received`, `bid_audit_log`, the `bid_files_read` policy (Task 3).
- Produces:
  - `public.opened_bids(p_solicitation_id uuid) returns table (bid_id uuid, reference text, version int, submitted_at timestamptz, bidder_org_id uuid, bidder_name text, item_cents bigint[], alternate_cents bigint[], base_total_cents bigint, bid_bond_choice public.bid_bond_choice, original_received boolean, non_responsive_reason text)`.
    - It is office only (`not_authorized`). An unknown solicitation gives `not_found`; before close it raises `sealed`.
    - It returns one row per bid at its latest version and excludes withdrawn bids.
    - `base_total_cents = (select sum(x) from unnest(item_cents) x)::bigint`.
    - `non_responsive_reason` is `'signed original not received by the bid due time'` when `original_received` is false, otherwise null.
    - Rows are ordered by `base_total_cents, reference`.
    - It is volatile. After `pg_advisory_xact_lock(hashtext(p_solicitation_id::text))`, it inserts a `bid_close_determination` audit row with `{version, original_received, reason}` for each bid whose latest determination row is missing or differs.
  - `public.opened_bid_files(p_solicitation_id uuid) returns table (bid_id uuid, slot public.bid_upload_slot, path text, file_name text)`. Same gates; latest, non-withdrawn versions only.
  - `tabulation.ts`:
    - `interface TabulationRow { reference; bidderName; version; baseTotal: string; alternates: string[]; originalReceived: boolean; reason: string | null }`
    - `toTabulation(rows: OpenedBid[], alternates: SolicitationData["schedule"]["alternates"]): { headers: string[]; rows: TabulationRow[] }`. Headers read "Alternate {n} (add|deduct)". Money comes only from `formatMoney` of stored cents.
  - Page, after close:
    - the tabulation table, with non-responsive rows flagged and their reason;
    - per-bid file links (signed URLs from the office user's client, 300 s);
    - the full submitted prices per bid.

    Before close: "Bids are sealed until {bid due, local}." There is no open button.

- [ ] **Step 1: Write failing tests.**
  - pgTAP, `opening.test.sql`. Fixture: one solicitation due `now() + interval '1 hour'`. Build bids A–E through the Task 4 functions and log originals through Task 8, then `tests.set_bid_due(sol, now())`.
    - **Review Focus 2:** before the due change, `opened_bids` and `opened_bid_files` raise `sealed` for the office. At `bid_due_at = now()` exactly, they return rows. An agency author, a bidder, and an admin whose org is an agency get `not_authorized`. `service_role` and anon get 42501.
    - **Review Focus 3:** bid A has v1 and v2 submitted and a signed form logged for v1 only. Its row has `version = 2`, `original_received = false` and `non_responsive_reason = 'signed original not received by the bid due time'`.
    - **Review Focus 4:**
      - Bid B has v1 submitted and its original logged; `replace_bid` was called but never submitted. Its row has `version = 1` and `original_received = true`.
      - Bid C has v1's original logged, then v2 submitted with its own original logged. Its row has `version = 2` and `original_received = true`.
    - Bid D, withdrawn, is absent. Bid E's original was logged and then voided before close, so it is non-responsive.
    - Bid C: `item_cents = {12500000,234567}`, `base_total_cents = 12734567`, `alternate_cents = {1500000}`.
    - The first call writes exactly 4 `bid_close_determination` rows; a second call writes 0.
    - After voiding bid C's v2 original (post-close) and calling again, C's row has `original_received = false`, and exactly 1 new determination row is written for C.
    - `opened_bid_files` returns bid B's v1 files and no files for D or for A's v1.
    - An agency author's `select` on `bid_audit_log` returns 0 rows after close.
  - Vitest: `toTabulation` with alternates `[{kind: "deductive"}]` gives the header `Alternate 1 (deduct)`, `baseTotal` `$127,345.67`, and passes `reason` through verbatim.
- [ ] **Step 2:** Run; expect FAIL.
- [ ] **Step 3:** Write `0012_opening.sql`, `tabulation.ts` and the page section.
- [ ] **Step 4:** Run `npm run db:reset && npm run db:test && npm test`; expect PASS. Run `npm run db:types`.
- [ ] **Step 5:** Commit: `feat: sealed opening at bid due time and internal tabulation`.

---

### Task 10: Seed, end-to-end verification and docs

**Files:**
- Modify: `supabase/seed.sql`, `README.md` (seed users, bidder flow), `docs/decisions.md` (add "Bid-submission slice, as built")

**Interfaces:**
- Seed (added in Task 5; confirm it here), all fictional:
  - Bidder orgs "Ridgeback Builders LLC" and "Granite Mesa Contractors", with company rows and users `bidder.ridgeback@example.test` and `bidder.granite@example.test` (password `proclaro-dev`).
  - Two published, released solicitations, inserted directly as slice 1 publishing can't produce a released row in under 3 days:
    - one due in 14 days at 13:00 local;
    - one due `date_trunc('minute', now()) + interval '20 minutes'` (so about 20 minutes after reset), for walking through close.

    Each has a `published_snapshot` built from the latest clauses and the settings. These rows have no RFB or bid-form files in `published`, so their public download links are absent; note this in the README.

- [ ] **Step 1:** Run `npm run lint && npm test && npm run db:reset && npm run db:test && npm run build`; expect all green.
- [ ] **Step 2: Walk the flow** on the "closing soon" solicitation:
  - A new self-signup registers and bids.
  - Ridgeback submits v1, replaces and submits v2.
  - Granite submits v1 and withdraws.
  - The office logs Ridgeback's v1 original, then its v2 original, and voids a mistaken entry.
  - Before the due time, the office page shows only references, versions and statuses.
  - After the due time, the tabulation shows Ridgeback at v2, responsive, with the right total, and Granite absent.
  - The agency author and a signed-out visitor see nothing new.
  - Run a REST `select` on `bid_versions` with the service-role key; expect a permission error. Download a sealed object with the service-role key before close; expect an error.
- [ ] **Step 3:** Record in `docs/decisions.md`:
  - the names chosen above (reference format, bucket layout, the derived determination and its logged-by-deadline rule, `bid_drafts.version`);
  - the separate `bid_audit_log` and why;
  - known gaps:
    - `service_role` keeps full access to `bid-files` objects in Storage (Ruling 3), including `owner` and `created_at`; tamper evidence covers changes made through the Storage API only;
    - email confirmation is off for self-signup locally and must be on before hosting;
    - a superuser can still read bids (approach 2 is deferred).
- [ ] **Step 4:** Search the repo for the real-world names listed in the git-ignored source-docs notes; expect no matches. Do not open `source-docs/` itself; use the existing search list the slice 1 build used.
- [ ] **Step 5:** Commit: `docs: bid submission slice complete`.

---

## Spec coverage

| Spec section | Task |
|---|---|
| Registration: self-signup, register screen, bidder org, `/bidder` | 1, 2 |
| The bid: one per pair, prices, sections, bid bond | 3, 5 |
| Lifecycle: draft, submit, replace; time gates | 4, 7 |
| Pre-filled bid form PDF | 6 |
| Paper originals log, voids, audit | 8 |
| Close: derived closed, opening, original-received check, tabulation | 9 |
| Access rules table (bidder, office, agency, admin, anon, plus `service_role`) | 1, 3, 4, 9 |
| Audit list | 4 (submit, replace, withdraw), 8 (log, void), 9 (determination) |
| Settled: any bidder may bid; withdrawal before close; new version after withdrawal | 4, 7 |
