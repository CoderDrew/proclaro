import { createElement } from "react";
import type { AddendumDocContext } from "./addendumDoc";
import type { BidFill } from "./bidFill";
import type { DocContext } from "./clauses";
import { AddendumDocument } from "./templates/AddendumDocument";
import { BidForm } from "./templates/BidForm";
import { RfbDocument } from "./templates/RfbDocument";

export type { DocContext } from "./clauses";
export type { AddendumDocContext } from "./addendumDoc";

const DOCTYPE = "<!doctype html>";

/**
 * Next's App Router rejects a static `import ... from "react-dom/server"` (build error). A dynamic import
 * is allowed, and `serverExternalPackages: ["react-dom"]` in next.config.ts makes Next load the app's own
 * react-dom from node_modules at runtime. Vitest loads the same package, so tests and the shipped build
 * use the same renderer.
 */
const { renderToStaticMarkup } = await import("react-dom/server");

export function renderRfbHtml(ctx: DocContext, opts: { draft: boolean }): string {
  return DOCTYPE + renderToStaticMarkup(createElement(RfbDocument, { ctx, draft: opts.draft }));
}

/**
 * The standalone bid form. Every page is `<section data-bid-form-page="N">` and ends with
 * `<footer data-footer="final|draft" data-footer-template="...{n}...{total}...">` containing
 * `<span data-page-n>` and `<span data-page-total>` that the PDF step overwrites. With `fill` the bidder's prices,
 * firm details and bid reference are printed (every page carries `<p data-bid-ref>`).
 */
export function renderBidFormHtml(ctx: DocContext, opts: { draft: boolean; fill?: BidFill }): string {
  return DOCTYPE + renderToStaticMarkup(createElement(BidForm, { ctx, draft: opts.draft, fill: opts.fill }));
}

/**
 * The addendum PDF. Its footer is the bid form's (`Solicitation {number} · Version {version} · Page {n} of {total}`),
 * carried by a hidden `<footer data-footer-template>` that renderPdf turns into Chromium's page footer.
 */
export function renderAddendumHtml(ctx: AddendumDocContext): string {
  return DOCTYPE + renderToStaticMarkup(createElement(AddendumDocument, { ctx }));
}
