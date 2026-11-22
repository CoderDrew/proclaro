import { chromium } from "playwright-core";
import { escapeHtml } from "./clauses";

export interface PdfRenderer {
  render(html: string, opts: { footerTemplate?: string }): Promise<Uint8Array>;
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e: string) => {
    if (e[0] === "#") {
      const code = e[1].toLowerCase() === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : m;
    }
    return ENTITIES[e.toLowerCase()] ?? m;
  });
}

/** The plain-text footer template (with {n} and {total}) from the first bid form footer, if any. */
export function extractFooterTemplate(html: string): string | undefined {
  const m = /<footer[^>]*\sdata-footer-template="([^"]*)"/.exec(html);
  return m ? decodeEntities(m[1]) : undefined;
}

/**
 * Chromium footerTemplate markup. The template text is HTML-escaped first; only then are the
 * {n}/{total} placeholders replaced with Chromium's page-number spans.
 */
export function chromiumFooterHtml(template: string): string {
  const text = escapeHtml(template)
    .replace("{n}", '<span class="pageNumber"></span>')
    .replace("{total}", '<span class="totalPages"></span>');
  return `<div style="width:100%;font-size:9px;font-family:Georgia,serif;text-align:center;color:#111;">${text}</div>`;
}

/** Renders HTML to PDF. A bid form's page numbers come from Chromium, so they match the real page count. */
export async function renderPdf(html: string, renderer: PdfRenderer): Promise<Uint8Array> {
  const template = extractFooterTemplate(html);
  return renderer.render(html, { footerTemplate: template ? chromiumFooterHtml(template) : undefined });
}

/**
 * On Vercel (no browser in the function image) launch the serverless Chromium build; everywhere else, the Chromium
 * installed by `npx playwright-core install chromium`.
 */
export function onServerless(env: Record<string, string | undefined> = process.env): boolean {
  return env.VERCEL === "1" || !!env.AWS_LAMBDA_FUNCTION_NAME;
}

async function launchBrowser() {
  if (!onServerless()) return chromium.launch();
  const { default: serverless } = await import("@sparticuz/chromium");
  return chromium.launch({ executablePath: await serverless.executablePath(), args: serverless.args, headless: true });
}

export function chromiumRenderer(): PdfRenderer {
  return {
    async render(html, { footerTemplate }) {
      const browser = await launchBrowser();
      try {
        const page = await browser.newPage();
        await page.setContent(html, { waitUntil: "load" });
        const pdf = await page.pdf({
          format: "Letter",
          printBackground: true,
          displayHeaderFooter: !!footerTemplate,
          headerTemplate: "<span></span>",
          footerTemplate,
          preferCSSPageSize: true,
        });
        return new Uint8Array(pdf);
      } finally {
        await browser.close();
      }
    },
  };
}
