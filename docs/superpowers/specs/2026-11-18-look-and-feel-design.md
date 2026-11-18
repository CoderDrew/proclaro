# Look and feel: a small design system for every screen

Status: Approved by Drew, 2026-11-18.

## Intent
On first sight, someone watching a walkthrough should say: "Wow, this looks clean, sleek, and modern" (Drew).

Today the app is close to bare HTML. There is one 91-line `globals.css`, about 100 ad-hoc class names, 22 files with inline styles, and no shared components. Each screen styles its buttons, tables and fields on its own.

This work gives every screen one consistent look. Slices 2b and 2c then come out styled by default, and a later visual change happens in one place.

## Direction (picked by Drew from mockups: "A · Light and airy")
- A soft gray page background, with content on white cards with rounded corners and subtle shadows.
- One blue accent for primary actions and links.
- Pill-shaped status badges in soft tints: green for good, red for problems, amber for waiting, gray for neutral.
- Generous spacing, clear hierarchy, and a modern sans-serif font.

## Approach (picked by Drew: a small design system of our own)
Considered:
1. **Our own tokens and components in plain CSS (chosen).** No new dependencies, it fits the current setup, and every line is readable.
2. **Tailwind.** It adds a build dependency and utility-class noise, and shared components would still be needed.
3. **shadcn/ui on Tailwind and Radix.** Polished out of the box, but heavy for forms and tables, with many generated files.

## Design
### Tokens (`src/styles/tokens.css`, imported by `globals.css`)
- CSS custom properties:
  - colors: page, surface, border, text, muted text, accent and accent-hover, and success, danger, warning and neutral tints, each with readable text colors;
  - spacing scale, radius (cards 12px, controls 8px, badges pill), shadow, font sizes and weights.
- Font: Inter via `next/font/google`, with a system-ui fallback. *(My call.)*
- Every text and background pairing meets WCAG AA contrast.

### Shared components (`src/components/ui/`)
- **AppShell:** a top bar with the Proclaro wordmark, role-aware navigation, and the signed-in user and Sign out. It also provides a centered content column with a sensible max width.
  - Bidder: My bids, Open solicitations.
  - Agency: My solicitations.
  - Office: Review queue, Published.
  - Admin: the admin sections.
  - Public, signed out: Solicitations and Sign in.
- **PageHeader:** an eyebrow line (for example "27-0002 · Calder Parks Division"), a title, and an optional actions area.
- **Card:** a white surface with an optional title. A **Section** groups related fields within a card.
- **Button:** variants primary, secondary and danger, plus a link-styled variant. Disabled and loading states, and a visible focus ring.
- **Field:** label, control, hint and error message in one wrapper. Text, number, money, date, time, select, textarea, radio group and checkbox controls all share one style.
- **Table:** light header, row dividers, right-aligned numeric columns with tabular figures, and an empty state.
- **StatusBadge:** one place that maps every domain status (solicitation state, bid status, Received, Non-responsive, tamper flags, and so on) to a tint and a label.
- **Notice:** info, success, warning or error, used for sealed notices, deadline messages, unsaved changes and validation summaries.
- **Money:** formatted cents with tabular figures, aligned right.
- **DateTime:** shows the configured time zone consistently.

### Migration
- Every page moves onto these components:
  - public listing and detail;
  - login, signup and register;
  - invite confirm, set password and link-invalid;
  - bidder home and bid page;
  - agency list and solicitation form;
  - office queues, review panel, and bids/tabulation;
  - all admin pages.
- Inline `style={{…}}` is removed, except for genuinely one-off layout.
- Behaviour, copy decided earlier (for example "Save Amounts", "Print Blank Bid Form") and server logic don't change.
- Existing tests keep passing. Tests that assert text keep their exact strings.

### Responsive and accessible
- Usable down to tablet width. Tables scroll horizontally on narrow screens rather than breaking.
- Visible focus states, labels tied to controls, and `aria-label`s where a button's text repeats per row. The reviewer flagged the upload buttons for this.

## Non-goals
- The generated PDFs (RFB and bid form) are not restyled; they are legal documents with their own templates.
- No dark mode.
- No new features, flows or copy beyond what styling needs.
- No logo design; a text wordmark is enough.

## Anti-goals
- A look that's pretty but slower to use. Dense office tables must stay scannable.
- Styling that hides state, for example a disabled button that looks enabled, or a sealed notice that looks like decoration.

## Left to the builder
- Exact token values within the chosen direction.
- Component APIs.
- Where in each page the shell's actions go.

## Verification
- Screenshot each main screen before and after, as bidder, agency author, reviewer and admin, and include them in the report.
- Run the existing gates: npm test, test:slow, tsc, lint, build. pgTAP isn't affected, since there are no database changes.
