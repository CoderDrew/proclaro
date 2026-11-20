import { existsSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { chromium } from "playwright-core";
import { renderBidFormHtml, renderRfbHtml } from "./renderHtml";
import { chromiumRenderer, chromiumFooterHtml, extractFooterTemplate, renderPdf } from "./pdf";
import { ctxWith } from "./testFixtures";

async function pdfPages(bytes: Uint8Array): Promise<string[]> {
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  const doc = await pdfjs.getDocument({ data: new Uint8Array(bytes), useSystemFonts: true }).promise;
  const pages: string[] = [];
  for (let i = 1; i <= doc.numPages; i++) {
    const content = await (await doc.getPage(i)).getTextContent();
    pages.push(content.items.map((it) => ("str" in it ? it.str : "")).join(" ").replace(/\s+/g, " "));
  }
  return pages;
}

describe("footer template handling", () => {
  it("reads the template from the first bid form footer and decodes entities", () => {
    const html = renderBidFormHtml(ctxWith(200_000_00), { draft: false });
    expect(extractFooterTemplate(html)).toBe("Solicitation 27-0001 · Version 1 · Page {n} of {total}");
  });

  it("returns undefined for a document with no bid form footer (the RFB)", () => {
    expect(extractFooterTemplate(renderRfbHtml(ctxWith(200_000_00), { draft: false }))).toBeUndefined();
  });

  it("maps placeholders to Chromium page number classes and escapes the rest", () => {
    const out = chromiumFooterHtml("A <b> & \"q\" · Page {n} of {total}");
    expect(out).toContain('<span class="pageNumber"></span>');
    expect(out).toContain('<span class="totalPages"></span>');
    expect(out).toContain("A &lt;b&gt; &amp; &quot;q&quot;");
    expect(out).not.toContain("<b>");
  });
});

const hasChromium = (() => {
  try { return existsSync(chromium.executablePath()); } catch { return false; }
})();

// `npm test` skips these when Chromium is absent; `npm run test:slow` sets REQUIRE_CHROMIUM and must fail instead.
describe.runIf(process.env.REQUIRE_CHROMIUM === "1" && !hasChromium)("[slow] chromium availability", () => {
  it("Chromium is installed (run: npx playwright-core install chromium)", () => {
    expect(hasChromium).toBe(true);
  });
});

describe.skipIf(!hasChromium)("[slow] chromium PDF rendering", () => {
  it("bid form footer uses the real page count and appears once per page", async () => {
    const html = renderBidFormHtml(ctxWith(200_000_00), { draft: false });
    const pages = await pdfPages(await renderPdf(html, chromiumRenderer()));
    const total = pages.length;
    expect(total).toBeGreaterThanOrEqual(4);
    expect(pages[0]).toContain("Solicitation 27-0001 · Version 1 · Page 1 of");
    pages.forEach((text, i) => {
      const footers = text.match(/Solicitation 27-0001 · Version 1 · Page \d+ of \d+/g) ?? [];
      expect(footers).toEqual([`Solicitation 27-0001 · Version 1 · Page ${i + 1} of ${total}`]);
    });
  }, 60_000);

  it("draft bid form carries the watermark and no number or version", async () => {
    const html = renderBidFormHtml(ctxWith(200_000_00, {}, { number: null, version: null }), { draft: true });
    const pages = await pdfPages(await renderPdf(html, chromiumRenderer()));
    const all = pages.join(" ");
    expect(all).toContain("DRAFT — NOT FOR BIDDING");
    expect(pages[0]).toContain(`DRAFT · Page 1 of ${pages.length}`);
    expect(all).not.toMatch(/Version \d/);
    expect(all).not.toContain("Solicitation 27-0001");
  }, 60_000);

  it("pre-filled bid form PDF shows the reference, version, prices and the slice 1 footer", async () => {
    const ctx = ctxWith(200_000_00, { schedule: { items: [{ name: "A", description: "" }, { name: "B", description: "" }], alternates: [] } });
    const fill = {
      legalName: "Ridge Builders", address: "1 Elm St", contact: "Ana Ridge, 555-0142, ana@example.test",
      residentClaimed: false, residentCertificate: null, reference: "K7QM-2XVD", bidVersion: 2,
      itemCents: [12_500_000, 234_567], alternateCents: [], bidBond: "paper" as const, apprenticeCommitment: null,
    };
    const pages = await pdfPages(await renderPdf(renderBidFormHtml(ctx, { draft: false, fill }), chromiumRenderer()));
    const total = pages.length;
    pages.forEach((text, i) => {
      expect(text).toContain("Bid reference K7QM-2XVD · Bid version 2");
      expect(text).toContain(`Solicitation 27-0001 · Version 1 · Page ${i + 1} of ${total}`);
    });
    const all = pages.join(" ");
    for (const t of ["$125,000.00", "$2,345.67", "$127,345.67", "Ridge Builders", "Paper original mailed"]) expect(all).toContain(t);
  }, 60_000);

  it("renders the RFB without a footer template", async () => {
    const bytes = await renderPdf(renderRfbHtml(ctxWith(200_000_00), { draft: true }), chromiumRenderer());
    const pages = await pdfPages(bytes);
    expect(pages.join(" ")).toContain("DRAFT — NOT FOR BIDDING");
  }, 60_000);
});
