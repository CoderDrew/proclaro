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

Other scripts: `db:reset`, `db:test`, and `db:types` (regenerates `src/lib/supabase/database.types.ts`).

## Seeded users

`npm run db:reset` loads fictional users for the State of Calder. Sign in at `/login`. Each user's password is a local seed value defined in `supabase/seed.sql`; it is for the local stack only.

| Role | Email | Home after sign-in |
|---|---|---|
| Agency author (Corrections) | `author.corrections@example.test` | `/agency` |
| Agency author (Parks) | `author.parks@example.test` | `/agency` |
| Procurement reviewer / checker | `reviewer1@example.test` | `/office` |
| Procurement reviewer / checker | `reviewer2@example.test` | `/office` |
| Admin (procurement office) | `admin@example.test` | `/admin` |

The two procurement users can each act as reviewer or checker, but never both on the same solicitation.

## Tour of the solicitation-setup slice

1. **`/agency`**: an agency author starts a draft, fills in the solicitation (autosaved), uploads attachments, previews the RFB and bid form as drafts, and submits it for office review. Problems block submission; warnings must be acknowledged.
2. **`/office`**: the review queue. A procurement reviewer starts review, can edit fields (each edit needs a reason), returns the solicitation to the agency with comments, or sends it to check. A second person checks it and approves, or disagrees and sends it back to the reviewer. If no checker is available, the reviewer can approve alone, which is recorded. The history on each solicitation lists every step.
3. **`/office/solicitations/<id>`**: after approval, the reviewer or checker publishes. Publishing renders the final RFB and bid form and freezes the solicitation; the number (`YY-NNNN`) was already assigned at first submission. If the release date passes before publishing, the reviewer or checker reopens the review with a reason, the reviewer corrects the dates, and it goes through the check again.
4. **`/solicitations`**: the public listing. A published solicitation appears here, and at `/solicitations/<number>` with its PDFs and attachments, from its release date. Before then only office staff can see it.
5. **`/admin`**: admins manage users, organizations, standard clauses, holidays, and settings (state and office names, time zone, fiscal-year start).

