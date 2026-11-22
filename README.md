# Proclaro

Proclaro replaces a paper- and PDF-driven bidding process with a web portal for a fictional state agency. Vendors find open Requests for Bid, submit required information and documents online, and track their status. Agency staff create solicitations, review sealed bids once bidding closes, and approve which ones advance to award. Deterministic rules check structured fields. An AI model checks uploaded documents against each requirement and cites where it found its evidence. Every determination stays with a human reviewer, and every override is logged.

This is a portfolio project. It's built by AI coding agents under my direction as product engineer, and the design decisions, plans and review history are documented in [docs/](docs/). All agencies, bidders and documents are fictional.

## Development

```bash
npm install
npx playwright-core install chromium   # once, for document rendering (matches the installed playwright-core)
npm run db:start                  # local Supabase; Docker Desktop must be running
npm test                          # Vitest (Chromium tests skip if it is missing)
npm run test:slow                 # Chromium PDF tests only; fails if Chromium is missing
npm run dev
```

**Development-only email sign-in.** Set `DEV_EMAIL_LOGIN=1` in `.env.local` and restart `npm run dev` to sign in at `/login` with just an email address (no password) for any existing user that has a profile; unknown emails get the normal sign-in error and no user is ever created. It works only when `NODE_ENV` is not `production` and `NEXT_PUBLIC_SUPABASE_URL` points at `127.0.0.1` or `localhost`, and the server re-checks this on every sign-in. **Never set it in a hosted environment**: it signs in anyone who knows an email. Remove the line (and restart) to get the password field back.

Other scripts: `db:reset`, `db:test`, and `db:types` (regenerates `src/lib/supabase/database.types.ts`).

## UI components

Shared building blocks (shell, nav, page header, cards, buttons, fields, tables, status badges, notices, money and dates) live in `src/components/ui/`. Colours, spacing, type and radii are tokens in `src/styles/tokens.css`; component rules are in `src/styles/components.css`. Use these rather than inline styles.

## Seeded users

`npm run db:reset` loads fictional users for the State of Calder. Sign in at `/login`. Each user's password is a local seed value defined in `supabase/seed.sql`; it is for the local stack only.

| Role | Email | Home after sign-in |
|---|---|---|
| Agency author (Corrections) | `author.corrections@example.test` | `/agency` |
| Agency author (Parks) | `author.parks@example.test` | `/agency` |
| Procurement reviewer / checker | `reviewer1@example.test` | `/office` |
| Procurement reviewer / checker | `reviewer2@example.test` | `/office` |
| Admin (procurement office) | `admin@example.test` | `/admin` |
| Bidder (Ridgeback Builders LLC) | `bidder.ridgeback@example.test` | `/bidder` |
| Bidder (Granite Mesa Contractors) | `bidder.granite@example.test` | `/bidder` |
| Bidder (Juniper Flats Paving) | `bidder.juniper@example.test` | `/bidder` |
| Bidder (Basalt Creek Builders) | `bidder.basalt@example.test` | `/bidder` |

The two procurement users can each act as reviewer or checker, but never both on the same solicitation.

## Invited users

Staff are invite-only (bidders sign themselves up; see the bid-submission tour below). An admin invites staff from `/admin/users`, and each invited user signs in for the first time like this:

1. The invite email (template `supabase/templates/invite.html`) links to `/auth/confirm?token_hash=...&type=invite`.
2. `/auth/confirm` verifies the one-time token on the server with `@supabase/ssr` (`verifyOtp`). That sets the session cookies and sends the user to `/auth/set-password`.
3. `/auth/set-password` is open only to an invited user whose current session came from that link. After they choose a password (at least 8 characters), they land on their home page. From then on they sign in at `/login`.

Locally, the invite email lands in Mailpit at http://127.0.0.1:54324. The invite link points at `SITE_URL` (`.env.local`, default `http://127.0.0.1:3000`), so set `SITE_URL` when the dev server runs on another port. `additional_redirect_urls` in `supabase/config.toml` allows `/auth/confirm` on any local port. After changing `config.toml` or the template, restart the stack (`npx supabase stop`, then `npm run db:start`). `npm run db:reset` does not reload auth settings, so this applies to `enable_signup` too.

## Tour of the solicitation-setup slice

1. **`/agency`**: an agency author starts a draft, fills in the solicitation (autosaved), uploads attachments, previews the RFB and bid form as drafts, and submits it for office review. Problems block submission; warnings must be acknowledged.
2. **`/office`**: the review queue. A procurement reviewer starts review, can edit fields (each edit needs a reason), returns the solicitation to the agency with comments, or sends it to check. A second person checks it and approves, or disagrees and sends it back to the reviewer. If no checker is available, the reviewer can approve alone, which is recorded. The history on each solicitation lists every step.
3. **`/office/solicitations/<id>`**: after approval, the reviewer or checker publishes. Publishing renders the final RFB and bid form and freezes the solicitation; the number (`YY-NNNN`) was already assigned at first submission. If the release date passes before publishing, the reviewer or checker reopens the review with a reason, the reviewer corrects the dates, and it goes through the check again.
4. **`/solicitations`**: the public listing. A published solicitation appears here, and at `/solicitations/<number>` with its PDFs and attachments, from its release date. Before then only office staff can see it.
5. **`/admin`**: admins manage users, organizations, standard clauses, holidays, and settings (state and office names, time zone, fiscal-year start).

## Tour of the bid-submission slice

Self-signup is on (`enable_signup = true`). Changing it needs `npx supabase stop` and then `npm run db:start`, because `db:reset` doesn't reload auth. Email confirmation is off locally.

1. **`/signup`**: a bidder creates an account (email and password). It gets no agency or office role.
2. **`/register`**: the new account registers its company (legal name, address, contact, optional resident claim). This creates a bidder organization and sends the user to `/bidder`. The seeded bidders are already registered.
3. **`/bidder`**: open solicitations and "My bids".
4. **`/bidder/solicitations/{id}`**: start a bid, enter prices, upload the required files, choose the bid bond option when one is required, print the pre-filled bid form, and submit. Afterwards the page shows receipts (time, reference, version, no prices) and lets the bidder replace or withdraw until close.
5. **`/office`**: the "Published" table links each published solicitation to **`/office/solicitations/{id}/bids`**. Before the bid due time the office sees only references, versions and statuses, and can log mailed originals (and void a mistaken entry). After it, the same page shows the internal tabulation, each bid's prices and files, tamper flags and any non-responsive reason.

## Seeded solicitations

The seed inserts five published, released solicitations directly (all fictional). Each has the `rfb_path` and `bid_form_path` that publishing would set, so its public page renders, but no PDF is uploaded, so the documents show as unavailable.

| Number | What it is for |
|---|---|
| `27-0001` | Due in 14 days, bid bond required. Its Addendum 1 is a draft by the Corrections author that moves the bid due date 7 days later, for walking an addendum through submit, review, check and publish. The seeded solicitation has no attachments, so add the required ones (plans, specifications, sample contract, prevailing wage) to the addendum before submitting it. |
| `27-0002` | Closes about 20 minutes after `db:reset`, so the opening can be tried locally. No bid bond. |
| `27-0003` | Closed an hour before `db:reset`, with funding of $1,250,000.00 and two additive alternates. It has four sealed paper-bond bids for walking bid review, the recap and the award. Basalt's bond was not logged, so its bid is pending cure until 17:00 on the next business day after the `db:reset` (the cure deadline is frozen when the bid is first reviewed). Ridgeback claims residency (certificate `CR-0042`), and Granite commits apprentices. With every bid accepted and Ridgeback verified, the recap takes alternate 1 and ranks Ridgeback first by resident preference, then Granite, Juniper and Basalt. Without the verification, Granite ranks first. |
| `27-0004` | Open for 14 days with a $1.5M estimate, so a bidder sees the apprentice commitment question. Addendum 1, published a day before `db:reset`, adds Item 3 to the bid schedule, so the solicitation is at version 2 (version 1 is still listed; neither version's PDFs exist). Granite submitted at version 1, so its bid shows resubmit required. Ridgeback has a draft priced against version 2 and has not acknowledged Addendum 1. The Q&A board has a question in every status: Ridgeback's, answered in Addendum 1; Granite's open one; and Granite's duplicate, closed by Reviewer One. |
| `27-0005` | Closes about 20 minutes after `db:reset`, bid bond required. Juniper's paper-bond bid has no bond original logged, so its cure starts live at close. |

Only `27-0003` has a funding amount set at publish. `27-0004`'s Addendum 1 froze its estimate as the funding amount for version 2, as publishing any addendum does; the others fall back to their estimate.

## The advisory AI document check

After close, office staff can run an AI check of each bid's documents on the bid review page. It reports met, not met or unclear for each checklist item, with the page and an excerpt, and the reviewer confirms or overrides each item. It never sets an outcome.

**Setup (server environment only):**

- `OPENAI_API_KEY`: a project-scoped key used only by this app. Never put it in a `NEXT_PUBLIC_` variable or commit it.
- `OPENAI_MODEL` (optional): the model. The default is set in `src/server/aicheck/openai.ts`.
- `AI_CHECK_ENABLED=1` turns live checks on. Anything else hides "Run check"; recorded results still show.
- In the OpenAI dashboard, set a monthly spend limit on the project.
- On any hosted site where a visitor could reach an office login, leave `AI_CHECK_ENABLED` unset.

**Caps** (in `settings`, admin-editable): 3 runs per bid, 50 document checks per office user per day, 200 per day in total.

**Seeded results:** after `npm run db:reset`, run `npm run seed:files` (local only) to upload the fictional documents for `27-0003`'s recorded results. Planted findings: Granite's insurance ends before the bid due date; Juniper's amount in words differs from its total; Basalt lists an addendum 27-0003 doesn't have; Basalt's bond scan isn't attached.

**Evaluation:** `npm run aicheck:eval` checks every document in `fixtures/aicheck` with the live API (one call each; it costs money), reports the false-met rate separately from the false-not-met rate, and writes `docs/evaluation/YYYY-MM-DD-aicheck.md`. `npm run aicheck:fixtures` regenerates the documents; regenerating changes the insurance files, so update their sizes and MD5s in `supabase/seed.sql` (a test fails until you do).

## Tour of the bid review and award slice

1. **`/bidder/solicitations/{id}`** after close: a bidder whose bond is missing sees "Bid bond cure" with the deadline and can upload only the bond. After the recap or memo is posted, each bidder sees its own outcome.
2. **`/office/solicitations/{id}/review`**: a procurement reviewer sets each bid's outcome (with a note), verifies resident certificates and sends flagged bids to the agency. Then they send the recap (or the all-bids-rejected memo) to check, and a second office user, who did not review these bids, posts it. After the agency picks the award, the office sends it to check and a second user posts it. Every post asks for confirmation. The sender can recall a recap or award under check (for example when nobody else may check it) and then post it alone, which is recorded. Once the recap is sent to check, originals can't be voided or logged and cure bonds can't be uploaded.
3. **`/agency/solicitations/{id}/bids`**: the agency author decides each flagged bid (reference, reviewer's note and base total only) and picks the award from the posted recap, with a reason when the pick isn't the expected award.
4. **`/solicitations/{number}`**: the posted recap or memo and the award are public.

## Hosting

The hosted site runs on Vercel (the Next.js app) and Supabase Cloud (database, storage, auth). On Vercel, PDF rendering
uses the serverless Chromium package `@sparticuz/chromium`; everywhere else it uses the Chromium from
`npx playwright-core install chromium`.

**Demo accounts.** The hosted database uses the seeded users, but not the public local password:
`npm run hosted:reset` seeds from a temporary copy of `supabase/seed.sql` with `DEMO_PASSWORD` in its place.

**Vercel environment.** Set `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
and `SITE_URL` (the site's origin). Also set:

- `DEMO_PASSWORD` to the same password as `.env.hosted`, so the sign-in page lists the demo accounts;
- `SIGNUP_CLOSED=1`, so no one can create an account.

Never set `DEV_EMAIL_LOGIN`. Leave `AI_CHECK_ENABLED` unset, because every visitor can reach an office login.

**Supabase Auth settings (dashboard).**

- Turn off "Allow new users to sign up".
- Set Site URL to the site's origin.
- Add `<origin>/auth/confirm` to the redirect URLs.

**Reset.** Visitors share the data. To restore the seed:

1. Link the project once with `npx supabase link`.
2. Put `HOSTED_SUPABASE_URL`, `HOSTED_ANON_KEY`, `HOSTED_SERVICE_ROLE_KEY` and `DEMO_PASSWORD` in `.env.hosted`
   (git-ignored).
3. Run `npm run hosted:reset`.

The reset reruns the migrations and the seed, uploads the seed files, and fails loudly if the public local password
still signs in.
