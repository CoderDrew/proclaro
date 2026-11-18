# Look and Feel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every screen one clean, light and airy look through a small design system of our own (tokens, Inter, shared components, a role-aware app shell), without changing behaviour, copy, server logic or the PDFs.

**Architecture:**
- Plain CSS only. Tokens are CSS custom properties in `src/styles/tokens.css`; component styles are plain `ui-`-prefixed classes in `src/styles/components.css`. Both are `@import`ed by `src/app/globals.css`.
- Shared React components live in `src/components/ui/`. Their pure decisions (status mapping, role navigation, contrast) live in `.ts` files with unit tests. Components spread `data-testid`, `aria-*` and `role` onto the real element, so existing attributes survive the migration verbatim.
- Pages migrate area by area. Each migration touches only `.tsx` files and CSS. No `.ts` logic file, server action, migration or PDF template changes.

**Tech Stack:** Unchanged: Next.js 15 (App Router), React 19, TypeScript, Vitest (node environment, `src/**/*.test.ts`), `playwright-core` + Chromium. Additions: `next/font/google` (part of Next, not a new dependency) and `react-dom/server` `renderToStaticMarkup` in tests (already installed).

**Spec:** `docs/superpowers/specs/2026-11-18-look-and-feel-design.md` (approved, binding). Read it before any task.

## Global Constraints

Copied verbatim from the spec:

- "Behaviour, copy decided earlier (for example "Save Amounts", "Print Blank Bid Form") and server logic don't change."
- "Existing tests keep passing. Tests that assert text keep their exact strings."
- "The generated PDFs (RFB and bid form) are not restyled; they are legal documents with their own templates."
- "**Our own tokens and components in plain CSS (chosen).** No new dependencies, it fits the current setup, and every line is readable."
- "Font: Inter via `next/font/google`, with a system-ui fallback."
- "Every text and background pairing meets WCAG AA contrast."
- "Usable down to tablet width. Tables scroll horizontally on narrow screens rather than breaking."

Also binding from the spec: "Inline `style={{…}}` is removed, except for genuinely one-off layout"; "No dark mode"; and the anti-goals: dense office tables stay scannable, and no styling hides state.

Rules this plan adds so the constraints can be checked:
- Never modify `src/documents/**`, `src/domain/**`, any `logic.ts`, `actions.ts`, `status.ts`, `tabulation.ts`, `history.ts`, `publish.ts`, `guard.ts`, `route.ts`, `src/lib/**`, `src/middleware.ts` or `supabase/**`. A migration task's `git diff --stat` lists only `.tsx` and `.css` files (plus new `src/components/ui/*.ts` and tests).
- Visible strings in `.tsx` stay identical, with two exceptions decided below: solicitation-state badges and the receipt-status parentheses. New text is limited to the nav labels the spec names and the per-row `aria-label`s.
- Never open `source-docs/`. Screenshots and helper scripts go under `.superpowers/look-and-feel/` (git-ignored), never in the repo.

## Review Focus

1. **A disabled or readOnly control that looks enabled.** Examples: a closed bid's amount inputs, Save Amounts with nothing to save, the agency form inside `<fieldset disabled>`, and Print for signature before the amounts are saved. Disabled controls get the disabled fill, the disabled text colour, `cursor: not-allowed`, no shadow and no hover change. `:disabled` also matches controls disabled through a fieldset.
   - Pinned in Task 1 (the contrast test covers the disabled pair).
   - Pinned in Task 2 (markup test: `Button disabled` renders `disabled` and the variant class).
   - Pinned in Task 5 (manual: screenshot the closed bid page).
   - Pinned in Task 6 (manual: screenshot a submitted, read-only solicitation).
2. **A lost `name`, `type="submit"`, `data-testid`, `aria-*` or `role`.** Any of these would break a server action, a form post or a walkthrough script.
   - `Button` makes `type` a required prop.
   - Each migration task runs the attribute-preservation check from Task 1, Step 5. Every attribute at baseline `2cfaf6f` must still be present.
3. **A sealed notice, non-responsive reason, tamper flag or status hidden or softened by styling.**
   - The `sealed` notice stays a `Notice tone="warning"` with `data-testid="sealed"` and its bold text.
   - "Non-responsive" stays a danger badge followed by the database reason, verbatim.
   - The file flags keep `role="alert"`.
   - Pinned in Task 2 (mapping test: `original false` maps to danger, `files` with flags maps to danger with the joined text).
   - Pinned in Task 7 (manual: the bids page before close, and after close on the closing-soon seed).
4. **Nav that shows a role links it can't use.**
   - Pinned in Task 3: `navFor` unit tests per role, checked against the page guards.
   - Pinned in Task 3 and Task 9 (manual): as each seeded user, click every nav link. Each one must land on its own path with no redirect.
5. **Focus that isn't visible.** A global `:focus-visible` ring uses `--color-focus`.
   - Pinned in Task 1: the contrast test requires at least 3:1 against both the surface and the page.
   - Pinned in every migration task (manual): Tab through the page and screenshot a focused button, link and input.

---

## Names decided here (spec "Left to the builder")

- **Tokens** (`src/styles/tokens.css`, on `:root`). Values are starting points; the contrast test is the judge.
  - **Colours:**
    - `--color-page #f5f7fa`, `--color-surface #ffffff`, `--color-border #e3e8ef`, `--color-control-border #7c8799`;
    - `--color-text #1b2330`, `--color-text-muted #5b6576`;
    - `--color-accent #2456d6`, `--color-accent-hover #1c45b0`, `--color-on-accent #ffffff`, `--color-focus #2456d6`;
    - `--color-disabled-bg #eef1f5`, `--color-disabled-text #5b6576`.
  - **Tints**, each a `-bg` and `-text` pair:
    - success: `#e7f6ec` / `#16653a`
    - danger: `#fdecec` / `#b42323`
    - warning: `#fdf3dc` / `#8a5300`
    - neutral: `#eef1f5` / `#424b5a`
    - info: `#e8f0fe` / `#1d4ed8`
  - `--color-danger-solid #b42323` is the danger button's fill.
  - **Spacing:** `--space-1` to `--space-8` = 4, 8, 12, 16, 24, 32, 48, 64px.
  - **Radius:** `--radius-card 12px`, `--radius-control 8px`, `--radius-pill 999px`.
  - **Shadow:** `--shadow-card: 0 1px 2px rgb(16 24 40 / .06), 0 1px 3px rgb(16 24 40 / .10)`.
  - **Type:** `--font-sans: var(--font-inter), system-ui, -apple-system, "Segoe UI", sans-serif`. Sizes: `--text-xs 12px`, `--text-sm 13px`, `--text-base 14px`, `--text-md 16px`, `--text-lg 20px`, `--text-xl 24px`. Weights: `--weight-regular 400`, `--weight-medium 500`, `--weight-semibold 600`.
  - **Layout:** `--content-max 1200px`. The base font size stays 14px so office tables stay dense.
- **Navigation labels and targets.** Admin links are added after the org-kind links when `isAdmin`.

  | Who | Links |
  |---|---|
  | Signed out | Solicitations `/solicitations`, Sign in `/login` |
  | Bidder | My bids `/bidder#my-bids`, Open solicitations `/bidder` |
  | Agency | My solicitations `/agency` |
  | Office | Review queue `/office`, Published `/office#published` |
  | Admin (adds) | Users `/admin/users`, Organizations `/admin/organizations`, Clauses `/admin/clauses`, Holidays `/admin/holidays`, Settings `/admin/settings` |

  The wordmark links to `homePathFor(ctx)`, or to `/` when signed out, exactly as today. The `/admin` home stays reachable through the wordmark for admins.
- **Spec ambiguities resolved:**
  - **Solicitation-state badges** show the labels the office already uses ("Submitted", "In review", "In check", "Approved", "Published", and "Draft" for draft). The agency list and form previously showed the raw enum (`in_review`). ReviewPanel keeps its own "Draft (with the agency)" through the badge's `label` override. The agency read-only sentence ("…while it is in review.") is unchanged.
  - **Receipt statuses keep their exact lowercase text** ("current", "superseded", "withdrawn {time}"). When shown as a badge, the badge replaces the surrounding parentheses.
  - **Office "Published" link** targets an anchor on `/office`. Its `<h2>` gets `id="published"`. The bidder's `<h2>My bids</h2>` gets `id="my-bids"`.
  - **Signed in without a profile** (on `/register`), the shell shows the signed-out nav, as today. This is not changed here.
  - **The bidder home's own Sign out button** stays, restyled as a secondary button, because removing it would change behaviour.

---

### Task 1: Tokens, Inter, globals.css, and the screenshot and attribute tooling

**Files:**
- Create:
  - `src/styles/tokens.css`, `src/styles/components.css` (empty placeholder with a header comment; filled in Task 2)
  - `src/styles/contrast.ts`
  - `.superpowers/look-and-feel/shoot.mjs` (git-ignored, not committed)
- Modify:
  - `src/app/globals.css`: rewrite on tokens; `@import "../styles/tokens.css";` and `@import "../styles/components.css";` at the top
  - `src/app/layout.tsx`: font only; the header markup changes in Task 3
- Test: `src/styles/contrast.test.ts`

**Interfaces:**
- Produces:
  - every token above;
  - `contrastRatio(fg: string, bg: string): number` (WCAG 2.x relative luminance; `#rrggbb` only);
  - `readTokens(css: string): Record<string, string>` (parses `--name: #hex;`);
  - the base element styles that every later task relies on.
- Base styles in `globals.css`:
  - `body` uses the page background, `--font-sans`, `--text-base` and `--color-text`. Links use `--color-accent`.
  - Headings use these sizes: `h1` `--text-xl`/600, `h2` `--text-md`/600, `h3` `--text-base`/600.
  - **Native controls** (`input:not([type=checkbox]):not([type=radio]):not([type=file])`, `select`, `textarea`): white fill, `--color-control-border`, `--radius-control`, 8px 10px padding, inheriting the font.
  - **`:disabled` and `[readonly]`** use the disabled tokens and `cursor: not-allowed`.
  - **`:focus-visible`** gets a 2px solid `--color-focus` outline with 2px offset on `a, button, input, select, textarea, summary, [tabindex]`.
  - `.tabular { font-variant-numeric: tabular-nums; }`, `.visually-hidden`.
  - The existing legacy classes (`.sol-layout`, `.sol-form`, `.sol-side`, `.issues*`, `.field-comment`, `.upload-*`, `.link-button`, `.muted`, `.error`, `.status-pill`, `table.list`, `.shell-*`) are re-expressed with tokens, so unmigrated pages stay coherent until their task. `.sol-layout` collapses to one column below 900px, where `.sol-side` stops being sticky.
- `layout.tsx`:
  - `const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" })` from `next/font/google`;
  - `<html lang="en" className={inter.variable}>`.

- [ ] **Step 1: Capture the baseline before any change.**
  1. Create `shoot.mjs`. Usage: `node .superpowers/look-and-feel/shoot.mjs <set> [--user public|bidder|author|reviewer|admin]`.
     - It drives `playwright-core` Chromium against `http://localhost:3000`.
     - It signs in through `/login` with the seeded email and password `proclaro-dev`.
     - It writes `.superpowers/look-and-feel/shots/<set>/<user>-<screen>-<1280|768>.png` as full-page shots at widths 1280 and 768.
  2. Screens:
     - **public:** `/solicitations`; the first `/solicitations/<number>` link, if it loads; `/login`; `/signup`; `/auth/link-invalid`; `/register` (after signing up a throwaway `shots-<timestamp>@example.test`).
     - **bidder** (`bidder.ridgeback@example.test`): `/bidder`; the first "Prepare a bid" link.
     - **author** (`author.parks@example.test`): `/agency`; the first `/agency/solicitations/` link.
     - **reviewer** (`reviewer1@example.test`): `/office`; the first `/office/solicitations/<id>` link that is not `/bids`; the first "Originals log and tabulation" link.
     - **admin** (`admin@example.test`): `/admin` and its five subpages.
  3. The executor runs `npm run db:reset` and `npm run dev` itself. Then run `node .superpowers/look-and-feel/shoot.mjs 00-baseline` and check that every screen produced two PNGs.
- [ ] **Step 2: Write `contrast.test.ts`.** It reads `src/styles/tokens.css` with `fs` and checks the following.
  - At least 4.5:1: text on surface and on page; text-muted on surface and on page; accent on surface and on page; on-accent on accent and on accent-hover; on-accent on danger-solid; disabled-text on disabled-bg; and each tint's `-text` on its own `-bg` (success, danger, warning, neutral, info).
  - At least 3:1: focus on surface and on page; control-border on surface.
  - `contrastRatio("#000000", "#ffffff")` is `21` (to 2 dp), and `contrastRatio("#777777", "#ffffff")` is about `4.48`.
- [ ] **Step 3:** Run `npm test -- contrast` and expect it to FAIL (no module). Implement `contrast.ts`, `tokens.css`, the `globals.css` rewrite and the `layout.tsx` font. Expect PASS. If a pair fails, adjust that token, never the threshold.
- [ ] **Step 4: Gates.** Run `npm test`, `npx tsc --noEmit`, `npm run lint` and `npm run build`; all must be green. `build` downloads Inter, so it needs network.
- [ ] **Step 5: Attribute-preservation check.** Every later task reuses this check.

  ```bash
  attrs() { git grep -ohE '(data-testid|name|aria-label|aria-invalid|aria-describedby|role|type|htmlFor|id)=("[^"]*"|\{[^}]*\})' "$@" -- src/app src/components | sort; }
  attrs 2cfaf6f > .superpowers/look-and-feel/attrs-base.txt
  git add -N . && attrs > .superpowers/look-and-feel/attrs-now.txt
  comm -23 .superpowers/look-and-feel/attrs-base.txt .superpowers/look-and-feel/attrs-now.txt   # expect no output
  ```

  `git grep` without a revision reads the working tree. The `git add -N` makes new files visible to it.
- [ ] **Step 6: Manual check.** Run `shoot.mjs 01-tokens`.
  - Pages now show the gray page, Inter and restyled controls, with no layout breakage against `00-baseline`.
  - Tab to an input and a button on `/login`; the focus ring is visible.
- [ ] **Step 7: Commit:** `style: design tokens, Inter and token-based globals`.

---

### Task 2: Core UI components and the status mapping

**Files:**
- Create in `src/components/ui/`:
  - `Button.tsx`, `Card.tsx` (`Card`, `Section`), `Field.tsx` (`Field`, `FieldGrid`, `Choice`, `MoneyInput`), `Notice.tsx`, `StatusBadge.tsx`, `status.ts`, `Money.tsx`, `DateTime.tsx`, `Table.tsx` (`Table`, `Th`, `Td`, `EmptyState`), `PageHeader.tsx` (`PageHeader`, `Page`), `index.ts` (re-exports)
- Modify: `src/styles/components.css` (all `ui-*` classes)
- Test: `src/components/ui/status.test.ts`, `src/components/ui/components.test.ts`

**Interfaces:**
- Consumes: the tokens; `formatMoney`, `Cents` from `@/domain/money`; `formatInstant` from `@/app/solicitations/status`.
- Produces, all exported from `src/components/ui/index.ts` (types too: `ButtonVariant`, `NoticeTone`, `StatusTone`, `DomainStatus`). Every component also accepts and spreads `"data-testid"?: string` onto its root element (onto the `<table>` for `Table`).

```ts
// Button.tsx
type ButtonVariant = "primary" | "secondary" | "danger" | "link";
Button(props: Omit<ButtonHTMLAttributes<HTMLButtonElement>, "type"> &
  { type: "button" | "submit"; variant?: ButtonVariant /* default "secondary" */; loading?: boolean })
// className `ui-button ui-button--{variant}`; loading ⇒ disabled + aria-busy="true"; children (label) untouched.

// Card.tsx
Card(props: { title?: ReactNode; titleId?: string; as?: "section" | "div" | "aside"; className?: string; children; "data-testid"?; role?; "aria-label"? })
// title renders <h2 className="ui-card-title" id={titleId}>.
Section(props: { title?: ReactNode; children; className? })        // <div className="ui-section"> with <h3>.

// Field.tsx (controls stay native elements, so name, value and handlers pass through untouched)
Field(props: { label: ReactNode; hint?: ReactNode; error?: ReactNode; wide?: boolean; children })
// <label className="ui-field"><span className="ui-field-label">…</span>{children}{hint}{error}</label>: implicit association.
FieldGrid(props: { children; columns?: "auto" | 1 | 2 })             // responsive grid of Fields
Choice(props: { label: ReactNode; children /* one radio or checkbox */ })  // <label className="ui-choice">
MoneyInput(props: InputHTMLAttributes<HTMLInputElement>)            // <span className="ui-money-input"><span aria-hidden="true">$</span><input inputMode="decimal" className="tabular" …/></span>

// Notice.tsx
type NoticeTone = "info" | "success" | "warning" | "error";
Notice(props: { tone: NoticeTone; title?: ReactNode; role?: "alert" | "status" | "alertdialog"; "aria-label"?; children; "data-testid"? })
// No default role: callers keep exactly the role they have today.

// status.ts
type StatusTone = "success" | "danger" | "warning" | "neutral";
type DomainStatus =
  | { kind: "solicitation"; state: string }                          // solicitation_state enum, or an unknown string
  | { kind: "bidding"; status: "Open" | "Closed" }                   // BidStatus
  | { kind: "bidVersion"; status: string }                         // current | superseded | withdrawn (office_bid_index), else neutral
  | { kind: "original"; received: boolean }                          // tabulation "Signed original"
  | { kind: "files"; flags: string[] }                               // TabulationRow.fileFlags
  | { kind: "file"; status: string }                                 // opened_bid_files.file_status
  | { kind: "logEntry"; flag: "afterDue" };
statusBadge(s: DomainStatus): { tone: StatusTone; label: string }

// StatusBadge.tsx
StatusBadge(props: { status: DomainStatus; label?: string /* overrides the label, never the tone */; role?: "alert" | "status"; "data-testid"? })
// <span className="ui-badge ui-badge--{tone}" role={role}>{label}</span>

// Money.tsx
Money(props: { cents: Cents })                                      // <span className="ui-money tabular">{formatMoney(cents)}</span>
// DateTime.tsx
DateTime(props: { iso: string; tz: string })                        // <time dateTime={iso}>{formatInstant(iso, tz)}</time>

// Table.tsx
Table(props: TableHTMLAttributes<HTMLTableElement> & { "data-testid"? })   // <div className="ui-table-scroll"><table className="ui-table" …/></div>
Th(props: ThHTMLAttributes<HTMLTableCellElement> & { numeric?: boolean })
Td(props: TdHTMLAttributes<HTMLTableCellElement> & { numeric?: boolean })  // numeric ⇒ className "ui-num tabular" (right-aligned)
EmptyState(props: { children })                                     // <p className="ui-empty">: same text callers already show

// PageHeader.tsx
PageHeader(props: { crumbs?: ReactNode; eyebrow?: ReactNode; title: ReactNode; actions?: ReactNode })
// crumbs = the existing back links; title renders the page's single <h1>.
Page(props: { width?: "narrow" | "medium" | "full" /* 400 / 640 / --content-max */; children })  // renders <main className="ui-page ui-page--{width}">
```

**`statusBadge` mapping** (exact):

| Input | Tone | Label |
|---|---|---|
| solicitation `draft` | neutral | Draft |
| solicitation `submitted` | warning | Submitted |
| solicitation `in_review` | warning | In review |
| solicitation `in_check` | warning | In check |
| solicitation `approved` | success | Approved |
| solicitation `published` | success | Published |
| solicitation, any other string | neutral | the string as given |
| bidding `Open` | success | Open |
| bidding `Closed` | neutral | Closed |
| bidVersion `current` | success | current |
| bidVersion `superseded` | neutral | superseded |
| bidVersion `withdrawn` | neutral | withdrawn |
| bidVersion, any other string | neutral | the string as given |
| original `true` | success | Received |
| original `false` | danger | Non-responsive |
| files `[]` | success | Unaltered |
| files `[a, b]` | danger | `a; b` |
| file `ok` | success | Unaltered |
| file `missing`, `changed` or any other value | danger | `{status} since submission` |
| logEntry `afterDue` | warning | after the bid due time |

- [ ] **Step 1: Write `status.test.ts`.** It has one `it` per row of the table above, asserting `{ tone, label }` exactly. It also asserts that every returned label is non-empty and that no input returns a tone outside `StatusTone`.
- [ ] **Step 2: Write `components.test.ts`** using `renderToStaticMarkup(createElement(...))`:
  - `Button` with `{ type: "submit", disabled: true, variant: "primary" }` contains `type="submit"`, `disabled=""` and `ui-button--primary`. With `loading: true`, it contains `disabled=""` and `aria-busy="true"` and keeps the child text.
  - `Field` with `{ label: "Email" }` wrapping `<input name="email">` renders the input inside the `<label>`, and `name="email"` survives.
  - `Table` with `data-testid="tabulation"` puts `data-testid` on the `<table>` and wraps it in `ui-table-scroll`. `Td numeric` has `ui-num`.
  - `Notice` with `{ tone: "warning", "data-testid": "sealed" }` keeps `data-testid="sealed"` and renders no `role` attribute. With `role: "alert"`, it renders `role="alert"`.
  - `StatusBadge` with `{ kind: "original", received: false }` and `role="alert"` renders `ui-badge--danger`, `role="alert"` and `Non-responsive`.
  - `Money` with `12_734_567` renders `$127,345.67` with `tabular`.
- [ ] **Step 3:** Run `npm test -- ui/` and expect FAIL. Implement the components and the `components.css` rules. Expect PASS.
  - Badges: pill, `--text-xs`, 2px 8px padding, tint background and text.
  - Buttons: 8px 14px, `--radius-control`. Primary is accent on on-accent; secondary is surface with a control border; danger is danger-solid; link has no box. Disabled uses the disabled tokens.
  - Cards: surface, `--radius-card`, `--shadow-card`, 24px padding, 16px gap between cards.
  - Tables: header row `--color-page` with muted 600 text, a `--color-border` divider per row, and 8px 12px cells. `.ui-table-scroll { overflow-x: auto }`.
  - Notices: tint background, a 4px left border in the tint's text colour, and `--radius-control`.
- [ ] **Step 4: Gates.** Run `npm test`, `npx tsc --noEmit` and `npm run lint`.
- [ ] **Step 5: Commit:** `feat(ui): core components and status badge mapping`.

---

### Task 3: AppShell with role-aware navigation

**Files:**
- Create: `src/components/ui/nav.ts`, `src/components/ui/AppShell.tsx` (server), `src/components/ui/AppNav.tsx` (`"use client"`)
- Modify: `src/app/layout.tsx` (the header becomes `<AppShell>`), `src/app/globals.css` (delete `.shell-header`, `.spacer`, `.shell-body`)
- Test: `src/components/ui/nav.test.ts`

**Interfaces:**
- Consumes: `SessionContext` and `homePathFor` from `@/lib/session`; `signOut` from `@/app/login/actions`; `Button`.
- Produces:

```ts
interface NavLink { href: string; label: string }
navFor(ctx: SessionContext): NavLink[]                 // exactly the "Navigation labels and targets" table
AppShell(props: { ctx: SessionContext; orgName: string; children })
// <header className="ui-topbar">: wordmark <a href={ctx ? homePathFor(ctx) : "/"}><strong>Proclaro</strong></a>,
// <AppNav links={navFor(ctx)} />, then signed in: "{displayName} · {orgName}{ · admin}" + <form action={signOut}><Button type="submit">Sign out</Button></form>.
// Signed-out "Sign in" comes from navFor, so it is not rendered twice.
// <div className="ui-content"> (max-width --content-max, centered, 24px gutters; 16px below 768px) wraps children; pages own <main>.
AppNav(props: { links: NavLink[] })   // <nav aria-label="Main">; usePathname(); aria-current="page" on links with no hash whose href === pathname; hash links (`#my-bids`, `#published`) are never marked
```

- `layout.tsx` keeps its existing `getSessionContext()` and organization-name query unchanged and passes both to `AppShell`.

- [ ] **Step 1: Write `nav.test.ts`.** Build fixture contexts.
  - `null` gives `[Solicitations /solicitations, Sign in /login]`.
  - A bidder gives `[My bids /bidder#my-bids, Open solicitations /bidder]`.
  - An agency member gives `[My solicitations /agency]`.
  - An office member gives `[Review queue /office, Published /office#published]`.
  - An office admin gives the office links followed by the five admin links in the order Users, Organizations, Clauses, Holidays, Settings.
  - An agency admin gives `/agency` followed by the five admin links.
  - **Guard consistency** (Review Focus 4):
    - for every non-admin context, no href starts with `/admin`;
    - no bidder href starts with `/office` or `/agency`;
    - no office or agency href starts with `/bidder`;
    - no agency href starts with `/office`.
- [ ] **Step 2:** Run `npm test -- nav` and expect FAIL. Implement. Expect PASS.
- [ ] **Step 3: Gates.** Run `npm test`, `npx tsc --noEmit`, `npm run lint` and the attribute check from Task 1, Step 5.
- [ ] **Step 4: Manual check.** Run `shoot.mjs 03-shell` for all users.
  - As each of the four seeded users and signed out, click every nav link. Each lands on its own path with no redirect, and the active link is marked.
  - At 768px the top bar wraps without horizontal scroll.
  - Tab from the wordmark through the nav to Sign out; every stop shows the focus ring.
- [ ] **Step 5: Commit:** `feat(ui): app shell with role-aware navigation`.

---

### Task 4: Migrate public and auth pages

**Files:**
- Modify:
  - `src/app/solicitations/page.tsx`, `src/app/solicitations/[number]/page.tsx`
  - `src/app/login/page.tsx`, `src/app/signup/page.tsx`, `src/app/signup/SignUpForm.tsx`, `src/app/register/page.tsx`, `src/app/register/RegisterForm.tsx`
  - `src/app/auth/link-invalid/page.tsx`, `src/app/auth/set-password/page.tsx`, `src/app/auth/set-password/SetPasswordForm.tsx`
- Test: none new (no logic changes). The gates, the attribute check and screenshots verify this task.

**Interfaces:**
- Consumes: `Page`, `PageHeader`, `Card`, `Field`, `Choice`, `Button`, `Notice`, `StatusBadge`, `DateTime`, `Table`/`Th`/`Td`/`EmptyState` (Task 2).
- **Listing:**
  - `Page width="full"`.
  - The status cell is `<StatusBadge status={{ kind: "bidding", status: bidStatus(...) }} />`.
  - The bid-due cell is `<DateTime iso tz />` when `bid_due_at` is set, otherwise "-".
- **Detail:**
  - `PageHeader`:
    - crumbs: the existing "All solicitations" link;
    - eyebrow: `{number} · {agency name}`;
    - title: `data.longTitle`;
    - status: the bidding badge.
  - Summary, Key dates and Documents each become a `Card` with the existing `<h2>` text as `title`.
  - Key dates keeps `<th scope="row">`.
- **Auth forms:**
  - `Page width="narrow"` with one `Card` holding the existing `<h1>` (via `PageHeader`), the paragraphs and the form.
  - Each `<label>` + `<input>` becomes `Field` with the same input element: the same `name`, `type`, `autoComplete`, `minLength` and `required`.
  - Submit buttons become `<Button type="submit" variant="primary" loading={pending}>`, keeping the same pending text.
  - Error paragraphs become `<Notice tone="error" role="alert">` with the same text. The signup notice becomes `<Notice tone="success" role="status">`.
  - The resident checkbox becomes a `Choice`.
  - The hidden `username` input in `SetPasswordForm` stays exactly as is.

- [ ] **Step 1: Before.** Run `shoot.mjs 04-before --user public`.
- [ ] **Step 2:** Migrate the ten files. Every `style={{…}}` in them is removed.
- [ ] **Step 3: Gates.**
  - Run `npm test`, `npx tsc --noEmit`, `npm run lint` and the attribute check.
  - `git diff --stat` lists only these `.tsx` files (and CSS if needed).
  - `git grep -c "style={{" -- src/app/solicitations src/app/login src/app/signup src/app/register src/app/auth` prints nothing.
- [ ] **Step 4: After.** Run `shoot.mjs 04-after --user public`. Compare with `04-before`; copy must read identically.
  - Sign in with a wrong password; the error Notice appears.
  - At 768px the Key dates table and the listing scroll horizontally inside their card, and the page does not.
  - Tab focus is visible on the inputs and the primary button.
  - `set-password` can't be reached without an invite email. Review it by reading the diff against `SignUpForm`, and record that it was not screenshotted.
- [ ] **Step 5: Commit:** `style: public and sign-in pages on the design system`.

---

### Task 5: Migrate bidder pages

**Files:**
- Modify:
  - `src/app/bidder/page.tsx`
  - `src/app/bidder/solicitations/[id]/page.tsx`, `src/app/bidder/solicitations/[id]/BidDraftForm.tsx`, `src/app/bidder/solicitations/[id]/ReceiptPanel.tsx`
  - `src/components/BidFileUploader.tsx`
  - `src/app/globals.css` (delete `.tight`, `.radio-line`, `.upload-*` and `.link-button` once unused)

**Interfaces:**
- Consumes: the Task 2 components; `statusBadge` kinds `bidVersion`.
- **Bidder home:**
  - `PageHeader` title "Open solicitations". "Signed in as …" stays as a muted paragraph.
  - Two `Card`s: one holding the open table, and one with `title="My bids"` and `titleId="my-bids"`.
  - The "Latest receipt" cell shows `{line}` followed by `<StatusBadge status={{ kind: "bidVersion", status }} label={status} />`, where `status` is the `describeReceipt` text. The kind comes from the receipt: withdrawn, current or superseded. When there is no receipt, the cell keeps "Draft, not yet submitted".
  - The existing Sign out form stays: `<Button type="submit">Sign out</Button>`.
- **Bid page:**
  - `PageHeader`: crumbs are the existing "Open solicitations" link; the title is unchanged; `actions` holds `PrintBlankFormButton` when open.
  - The "could not be read" message becomes `Notice tone="error" role="alert"`.
- **ReceiptPanel:**
  - A `Card` titled "Receipts" keeps `data-testid="receipts"`. Each receipt `li` keeps its `data-testid` and shows the line plus a `StatusBadge`; the `<strong>(…)</strong>` becomes the badge.
  - `mail-notice` becomes `Notice tone="info"` and keeps `data-testid`. "Your latest version is withdrawn…" becomes `Notice tone="warning"`.
  - Withdraw is `variant="danger"`; Replace and Start are `secondary`.
  - The confirm `div role="alertdialog"` becomes `Notice tone="warning" role="alertdialog" aria-label=… data-testid="receipt-confirm"`. "Yes, withdraw" is `danger`; "Yes, start a new draft" is `primary`; Cancel is `secondary`.
- **BidDraftForm:**
  - Cards: "Amounts", "Bid bond" (keep the `fieldset`/`legend` inside), "Required uploads", "Print for signature" and "Before you can submit".
  - Amount inputs become `MoneyInput`, keeping `aria-label`, `aria-invalid`, `value`, `disabled` and `onChange`. The amount column uses `Td numeric`. The base total is `<Td numeric data-testid="base-total"><Money cents={total} /></Td>`.
  - Buttons:
    - Save Amounts: `primary`;
    - `unsaved-notice` stays a `span` that keeps `data-testid`, `role="status"` and the text "Unsaved changes", with `className="ui-badge ui-badge--warning"`;
    - Print Bid Form for Signature: `secondary`;
    - Submit bid: `primary`;
    - `submit-confirm`: `Notice tone="warning" role="alertdialog"`.
  - The `bid-issues` list goes inside `Notice tone="warning"`; `bid-ready` becomes `Notice tone="success"`. Both `data-testid`s stay on their current elements.
  - The status/alert message becomes a `Notice` with `success` or `error` and the same role.
- **BidFileUploader:**
  - The upload button gets an `aria-label`: `` `${current ? "Replace file" : "Upload file"}: ${title}` ``.
  - Remove becomes `<Button type="button" variant="link" aria-label={`Remove ${title}`}>Remove</Button>`.
  - The row grid moves to a `ui-upload-*` set in `components.css`.

- [ ] **Step 1: Before.** Run `shoot.mjs 05-before --user bidder`.
- [ ] **Step 2:** Migrate the five files.
- [ ] **Step 3: Gates.**
  - Run `npm test` (the `logic.test.ts` strings are untouched), `npx tsc --noEmit`, `npm run lint` and the attribute check.
  - `git grep -c "style={{" -- src/app/bidder src/components/BidFileUploader.tsx` prints nothing.
- [ ] **Step 4: After.** As `bidder.ridgeback@example.test`, run `shoot.mjs 05-after --user bidder`.
  1. **Draft flow:** on the 14-day solicitation, start a bid. Type an amount and screenshot the "Unsaved changes" state, with Save Amounts enabled and visibly primary. Save, then screenshot Save Amounts disabled; it must look disabled.
  2. **Upload and submit:** upload a file and check that the Replace/Remove buttons announce the slot name (read `aria-label` in DevTools). Submit, and screenshot the receipts with the current badge.
  3. **Closed bid** (Review Focus 1): once the closing-soon seed is past due (about 20 minutes after reset), open it from My bids. Screenshot the read-only amounts: they show the disabled fill, and there is no Save Amounts button.
  4. **Narrow screens and focus:** at 768px the amounts table scrolls inside its card. Tab focus is visible on a MoneyInput and the Submit button.
- [ ] **Step 5: Commit:** `style: bidder pages on the design system`.

---

### Task 6: Migrate agency pages and the shared solicitation form components

**Files:**
- Modify:
  - `src/app/agency/page.tsx`
  - `src/app/agency/solicitations/[id]/page.tsx`, `src/app/agency/solicitations/[id]/SolicitationForm.tsx`
  - `src/components/SolicitationFields.tsx`, `src/components/AttachmentUploader.tsx`, `src/components/IssueList.tsx`, `src/components/RequirementsList.tsx`
  - `src/app/globals.css`, where the `.sol-*`, `.issues*` and `.field-comment` rules move onto tokens or are replaced by `ui-*` classes

**Interfaces:**
- Consumes: the Task 2 components; `statusBadge` kind `solicitation`.
- **Agency list:**
  - `PageHeader` title "My solicitations"; `actions` holds the existing `<form action={create}>` with `<Button type="submit" variant="primary">New solicitation</Button>`.
  - The state cell is `<StatusBadge status={{ kind: "solicitation", state: r.state }} />`.
- **Solicitation page:**
  - `PageHeader`: crumbs are "My solicitations"; the title is unchanged.
  - The unreadable-data message becomes `Notice tone="error" role="alert"`.
- **SolicitationForm sidebar:**
  - Each `<section>` becomes a `Card as="section"` with the existing `<h2>` text as `title`, inside `aside.sol-side`.
  - The status badge is `kind: "solicitation"`. The read-only sentence stays verbatim.
  - Buttons: Save is `secondary`; Submit for review is `primary`.
  - "The server did not accept the submission." becomes `Notice tone="error" role="alert"`.
  - Office comments become `Notice tone="warning"` items.
- **SolicitationFields:**
  - The outer `<fieldset disabled={!editable}>` stays, and its inline style moves to class `ui-fieldset-reset`.
  - Each inner `fieldset` + `legend` keeps its element and is styled as a card section (`.sol-form fieldset` on tokens).
  - The private `Field` keeps its name and context logic. It renders the ui `Field`, imported `as UiField`, around `{children}`.
  - Every Remove button in a repeated row gets an `aria-label`:
    - `Remove item ${i + 1}`;
    - `Remove alternate ${i + 1}`;
    - in AttachmentUploader, `Remove ${a.label || title}`.
  - IssueList's Acknowledge gets ``aria-label={`Acknowledge: ${i.message}`}``.
  - The `h4` and `p` inline margins become classes. RequirementsList's inline styles become `ui-plain-list`.

- [ ] **Step 1: Before.** Run `shoot.mjs 06-before --user author`.
- [ ] **Step 2:** Migrate the seven files.
- [ ] **Step 3: Gates.**
  - Run `npm test` (`fieldComments.test.ts` and `agency actions.test.ts` are untouched), `npx tsc --noEmit`, `npm run lint` and the attribute check.
  - `git grep -c "style={{" -- src/app/agency src/components` prints nothing.
- [ ] **Step 4: After.** As `author.parks@example.test`, run `shoot.mjs 06-after --user author`.
  1. **Draft solicitation:** open a draft and edit a field. Check the autosave text, then the warnings with Acknowledge, then the problems count.
  2. **Read-only solicitation** (Review Focus 1): open a submitted one if the seed has one; otherwise submit the edited draft. Screenshot it: every input shows the disabled fill, and there is no Save or Submit button.
  3. **Narrow screens and focus:** at 768px the sidebar drops below the form. Tab focus is visible inside the fieldsets.
- [ ] **Step 5: Commit:** `style: agency pages and solicitation form on the design system`.

---

### Task 7: Migrate office pages (queues, review, bids and tabulation)

**Files:**
- Modify:
  - `src/app/office/page.tsx`
  - `src/app/office/solicitations/[id]/page.tsx`, `src/app/office/solicitations/[id]/ReviewPanel.tsx`, `src/app/office/solicitations/[id]/InvalidDataPanel.tsx`
  - `src/app/office/solicitations/[id]/bids/page.tsx`, `src/app/office/solicitations/[id]/bids/OriginalsPanel.tsx`

**Interfaces:**
- Consumes: the Task 2 components; `statusBadge` kinds `solicitation`, `bidVersion`, `original`, `files`, `file`, `logEntry`; the Task 6 restyled shared components.
- **Queues (`/office`):**
  - `PageHeader` title "Procurement office".
  - Each queue is a `Card` titled with its existing `<h2>` text. The Published card has `titleId="published"`.
  - The Mine · All switch keeps its links and `<strong>`, styled as a segmented control (`ui-segmented`), with `aria-current="page"` on the active one.
  - Tables use `Table`. The empty texts become `EmptyState`. `data-testid="published"` stays on the table.
- **Review page and ReviewPanel:**
  - `PageHeader`: crumbs are the existing "Office queues · Bids" links; the eyebrow is `{number} · {agencyName}` when numbered; the title is unchanged.
  - The sidebar sections become `Card`s, with the status as `<StatusBadge status={{ kind: "solicitation", state }} label={STATE_LABELS[state] ?? state} />`.
  - Buttons, by their existing labels:
    - `primary`: Start review, Save changes, Send to check, Approve, Publish;
    - `danger`: Return, Disagree;
    - `secondary`: Edit, Cancel, Approve alone, Confirm approve alone, Reopen to correct dates, Reassign, Add another comment, the preview toggle.
  - The `field-comment` alertdialogs become `Notice tone="warning" role="alertdialog"`.
  - Comment `select`/`textarea` keep their `aria-label`s and lose `style={{ width: "100%" }}` (the global control style is full width inside a Field). Each comment Remove gets `aria-label={`Remove comment ${i + 1}`}`.
  - History becomes a `ui-timeline` list.
  - The two preview iframes keep one-off inline sizing, which is allowed as genuinely one-off layout. Their wrapper grid moves to a class.
- **InvalidDataPanel:**
  - `INVALID_STORED_DATA` becomes `Notice tone="error" role="alert"`.
  - Return is a `danger` button; the textarea becomes a `Field`.
- **Bids page:**
  - `PageHeader`: crumbs are the existing links; the title is "Bids: {title}". The due paragraph is unchanged.
  - The sealed notice becomes `<Notice tone="warning" data-testid="sealed"><strong>Bids are sealed until {dueLocal}.</strong></Notice>` (Review Focus 3).
  - "Only office staff…" and "not published" become `Notice tone="info"`.
- **Tabulation:**
  - A `Card` titled "Tabulation (internal)", with the note as muted text.
  - Money cells use `Td numeric`. The row with a `reason` gets `className="is-danger"`, a danger-bg row tint replacing the inline background.
  - Signed original: `<StatusBadge status={{ kind: "original", received: !r.reason }} />` and then, when there is a reason, `: {r.reason}` as text. The reason is never truncated.
  - Files: `<StatusBadge status={{ kind: "files", flags: r.fileFlags }} role={r.fileFlags.length ? "alert" : undefined} />`.
  - Bond stays text.
- **Opened bid sections:**
  - A `Card` each, keeping `data-testid={`opened-${b.reference}`}`.
  - Prices use `<Td numeric><Money cents={c} /></Td>`, and the Base total row stays bold.
  - The per-file suffix becomes `<StatusBadge status={{ kind: "file", status: f.file_status }} />` when not `ok`.
- **OriginalsPanel:**
  - Cards: "Submitted bids", "Log a mailed original" and "Originals log".
  - The index status cell is `<StatusBadge status={{ kind: "bidVersion", status: r.status }} />`.
  - The log form uses a `FieldGrid` of `Field`s and keeps every `value` and `onChange`. The version input loses `style={{ width: 80 }}` for class `ui-input-narrow`.
  - Log is `primary`. The help line is muted text.
  - Struck cells use `className="is-voided"` (line-through and muted). "Voided. Reason: …" stays visible text.
  - "(after the bid due time)" becomes `<StatusBadge status={{ kind: "logEntry", flag: "afterDue" }} />`.
  - Void becomes `<Button type="button" variant="danger" aria-label={`Void entry ${shortId(e.id)}`}>Void</Button>`, and the confirm becomes `Notice tone="warning" role="alertdialog" aria-label="Confirm void"`.

- [ ] **Step 1: Before.** Run `shoot.mjs 07-before --user reviewer`.
- [ ] **Step 2:** Migrate the six files.
- [ ] **Step 3: Gates.**
  - Run `npm test` (the `tabulation`, `history`, `publish`, office `actions` and bids `logic` tests are untouched), `npx tsc --noEmit`, `npm run lint` and the attribute check.
  - `git grep -n "style={{" -- src/app/office` shows only the two iframe lines.
- [ ] **Step 4: After.** As `reviewer1@example.test`, run `shoot.mjs 07-after --user reviewer`.
  1. **Review flow:** start a review on a submitted solicitation. Screenshot the actions card, the warnings and the history.
  2. **Bids before close:** on the 14-day published solicitation, screenshot the sealed Notice; it must read as a warning, not decoration. Log an original, void it with a reason, and screenshot the struck row.
  3. **Bids after close:** on the closing-soon seed after its due time, screenshot the tabulation.
     - The money is right-aligned in tabular figures.
     - Any non-responsive row shows the danger badge and the full verbatim reason.
     - The files column shows "Unaltered" or the flags.
  4. **Density, narrow screens and focus:** at 1280px the queue tables keep one line per row for typical titles. At 768px the tabulation scrolls horizontally inside its card. Tab focus is visible on Void and the log inputs.
- [ ] **Step 5: Commit:** `style: office queues, review and bids on the design system`.

---

### Task 8: Migrate admin pages

**Files:**
- Modify:
  - `src/app/admin/page.tsx`, `src/app/admin/ActionForm.tsx`
  - `src/app/admin/users/page.tsx`, `src/app/admin/organizations/page.tsx`, `src/app/admin/clauses/page.tsx`, `src/app/admin/holidays/page.tsx`, `src/app/admin/settings/page.tsx`

**Interfaces:**
- Consumes: the Task 2 components.
- **`ActionForm`** gains `submitVariant?: ButtonVariant` (default `"primary"`) and `submitAriaLabel?: string`. Its button becomes `<Button type="submit" variant={submitVariant} loading={pending} aria-label={submitAriaLabel}>`, with the same "Working..." and label text. The result `span` keeps its `role` and text, and uses classes `ui-inline-status ui-inline-status--{success|error}` instead of the inline colours.
- **Admin home:** `PageHeader` title "Administration". The link list becomes a grid of link `Card`s with the same name and blurb text.
- **Subpages:**
  - `PageHeader` with crumbs "Administration" and the existing `<h1>` text.
  - Forms sit in `Card`s using `FieldGrid` and `Field`, with every `name`, `type`, `required` and `defaultValue` kept. The checkbox becomes a `Choice`.
  - Tables use `Table`.
  - Per-row submit buttons get `submitVariant="secondary"` and an `aria-label`:
    - Holidays: Remove, with ``submitAriaLabel={`Remove holiday ${h.day}`}`` and `submitVariant="danger"`;
    - Organizations: Rename, with ``submitAriaLabel={`Rename ${o.name}`}``.
- **Clauses:**
  - Each clause is a `Card` titled with the existing `<h2 id={key}>`, passed through `titleId={key}`. The version label is a muted `small`.
  - The textarea keeps `name` and `aria-label`.
  - The `pre` and `code` inline styles move to classes `ui-pre` and `ui-code-list`.

- [ ] **Step 1: Before.** Run `shoot.mjs 08-before --user admin`.
- [ ] **Step 2:** Migrate the seven files.
- [ ] **Step 3: Gates.**
  - Run `npm test` (`admin.test.ts` and `clauses/actions.test.ts` are untouched), `npx tsc --noEmit`, `npm run lint` and the attribute check.
  - `git grep -c "style={{" -- src/app/admin` prints nothing.
- [ ] **Step 4: After.** As `admin@example.test`, run `shoot.mjs 08-after --user admin`.
  1. **Holidays:** add a holiday and see the success status; remove it and see the danger button.
  2. **Clauses:** save a clause version and see the new version label.
  3. **Nav:** every admin nav link and the office links are present and land without redirect.
  4. **Narrow screens and focus:** at 768px the users table scrolls. Tab focus is visible on the per-row buttons.
- [ ] **Step 5: Commit:** `style: admin pages on the design system`.

---

### Task 9: Final screenshot pass, legacy CSS cleanup and docs

**Files:**
- Modify:
  - `src/app/globals.css`: delete every legacy class with no remaining user. Check each with `git grep -n "<class>" -- src`.
  - `docs/decisions.md`: add "## 2026-11-18 — Look and feel, as built"
  - `README.md`: a short "UI components" note pointing to `src/components/ui/` and `src/styles/tokens.css`

- [ ] **Step 1: Inline style audit.** `git grep -n "style={{" -- src/app src/components` lists only the two ReviewPanel iframes. `git grep -n "status-pill\|className=\"list\"\|link-button\|shell-header" -- src` prints nothing.
- [ ] **Step 2: Full gates.** Run `npm test`, `npm run test:slow`, `npx tsc --noEmit`, `npm run lint` and `npm run build`; all must be green.
  - `test:slow` proves the PDFs are untouched; `src/documents/__snapshots__` has no diff.
  - `git diff 2cfaf6f --stat -- src/documents src/domain src/lib src/middleware.ts supabase` is empty.
  - The attribute check prints nothing.
- [ ] **Step 3: Final screenshots.**
  - After `npm run db:reset`, run `shoot.mjs 09-final` for all five users.
  - Build `.superpowers/look-and-feel/report.md`: for each main screen, the `00-baseline` and `09-final` images side by side at 1280, with 768 for tables. These are the screenshots the spec's report requires.
  - Re-walk the Review Focus manual checks once:
    - a disabled control;
    - the sealed notice;
    - the non-responsive row;
    - the nav per user;
    - focus.
- [ ] **Step 4: Record in `docs/decisions.md`:**
  - the token set and where it lives;
  - the component list;
  - the nav table;
  - the two copy decisions (solicitation-state labels, receipt-status badges without parentheses);
  - the allowed inline styles (the preview iframes);
  - Known gaps:
    - set-password not screenshotted;
    - unregistered users see the signed-out nav;
    - no dark mode (spec non-goal).
- [ ] **Step 5: Commit:** `docs: look and feel complete`.

---

## Spec coverage

| Spec section | Task |
|---|---|
| Direction: soft gray page, white cards, one blue accent, tinted pill badges, modern sans | 1, 2 |
| Tokens file, Inter via `next/font/google`, WCAG AA | 1 |
| AppShell and role-aware nav (bidder, agency, office, admin, public) | 3 |
| PageHeader, Card/Section, Button, Field family, Table, StatusBadge, Notice, Money, DateTime | 2 |
| Migration: public listing and detail; login, signup, register; invite confirm, set password, link-invalid | 4 (invite confirm is `auth/confirm/route.ts`, a redirect with no UI) |
| Migration: bidder home and bid page | 5 |
| Migration: agency list and solicitation form | 6 |
| Migration: office queues, review panel, bids/tabulation | 7 |
| Migration: all admin pages | 8 |
| Inline styles removed except one-offs | 4–8, audited in 9 |
| Behaviour, copy and server logic unchanged; tests keep exact strings | Global Constraints; the attribute check and `git diff --stat` in every task |
| Responsive to tablet; tables scroll horizontally | 1 (`.sol-layout`), 2 (`ui-table-scroll`), 768px shots in 4–9 |
| Visible focus, labels tied to controls, per-row `aria-label`s (upload buttons) | 1, 2, 5 (uploads), 6, 7, 8 |
| Non-goals: PDFs, dark mode, logo | 9 (`test:slow`, no documents diff) |
| Anti-goals: dense office tables, no hidden state | Review Focus 1 and 3; 7 |
| Verification: before/after screenshots per role; gates | 1 (baseline), 4–8, 9 |
