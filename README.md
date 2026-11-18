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

The seed inserts two published, released solicitations directly: `27-0001` (due in 14 days, bid bond required) and `27-0002`, which closes about 20 minutes after `db:reset` so the opening can be tried locally. They have no RFB or bid-form PDFs in the `published` bucket, so their public download links are absent.
