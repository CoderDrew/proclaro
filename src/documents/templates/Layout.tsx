/* eslint-disable @next/next/no-head-element -- these components render standalone HTML documents for PDF, not Next pages */
import type { ReactNode } from "react";
import { clauseBlocks, clauseVars, type DocContext } from "../clauses";

export const WATERMARK_TEXT = "DRAFT — NOT FOR BIDDING";

const CSS = `
@page { size: letter; margin: 0.9in 0.8in 1in 0.8in; }
* { box-sizing: border-box; }
body { font-family: Georgia, "Times New Roman", serif; font-size: 11pt; line-height: 1.4; color: #111; margin: 0; }
h1 { font-size: 22pt; margin: 0 0 12pt; }
h2 { font-size: 15pt; margin: 0 0 8pt; border-bottom: 1px solid #444; padding-bottom: 3pt; }
h3 { font-size: 12pt; margin: 12pt 0 4pt; }
p { margin: 0 0 8pt; }
table { border-collapse: collapse; width: 100%; margin: 6pt 0 12pt; }
th, td { border: 1px solid #555; padding: 4pt 6pt; text-align: left; vertical-align: top; }
th { background: #eee; }
.major { page-break-before: always; }
.cover { text-align: center; padding-top: 1.5in; }
.cover .meta { margin-top: 24pt; }
.toc li { margin: 3pt 0; }
.watermark { position: fixed; top: 38%; left: 0; width: 100%; text-align: center; font-size: 54pt; font-weight: bold;
  color: rgba(180, 0, 0, 0.14); transform: rotate(-30deg); pointer-events: none; z-index: 10; }
.bid-page { page-break-before: always; page-break-inside: avoid; position: relative; min-height: 8.6in; }
.bid-page:first-of-type { page-break-before: auto; }
.bid-page footer { position: absolute; bottom: 0; left: 0; right: 0; border-top: 1px solid #555; padding-top: 4pt;
  font-size: 9pt; text-align: center; }
/* The PDF step prints the real page numbers in Chromium's footer; hide the in-body copy. */
@media print { .bid-page footer { display: none; } }
.write-in { display: inline-block; min-width: 2.5in; border-bottom: 1px solid #111; height: 1em; }
.sig-line { margin-top: 28pt; border-bottom: 1px solid #111; width: 70%; }
.price { text-align: right; width: 2in; }
.muted { color: #555; }
`;

export function Shell({ title, draft, children }: { title: string; draft: boolean; children: ReactNode }) {
  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <title>{title}</title>
        {/* Static CSS constant only; no user text goes through dangerouslySetInnerHTML. */}
        <style dangerouslySetInnerHTML={{ __html: CSS }} />
      </head>
      <body>
        {draft ? <div className="watermark" data-watermark>{WATERMARK_TEXT}</div> : null}
        {children}
      </body>
    </html>
  );
}

/** One admin-maintained clause. Body text and variable values are rendered as escaped React text. */
export function Clause({ ctx, k }: { ctx: DocContext; k: string }) {
  const body = ctx.clauses[k];
  if (body === undefined) throw new Error(`MissingClause: ${k}`);
  return (
    <section data-clause={k}>
      {clauseBlocks(body, clauseVars(ctx)).map((b, i) =>
        b.kind === "heading" ? <h3 key={i}>{b.text}</h3> : <p key={i}>{b.text}</p>,
      )}
    </section>
  );
}

/** A user-written free-text block; blank lines make paragraphs. Escaped by React. */
export function FreeText({ text }: { text: string }) {
  const paras = text.split(/\n\s*\n/).map((s) => s.trim()).filter(Boolean);
  return <>{paras.map((p, i) => <p key={i}>{p}</p>)}</>;
}
