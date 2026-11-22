import { baseTotalCents } from "../../domain/bid/validate";
import { formatMoney } from "../../domain/money";
import type { Requirements } from "../../domain/solicitation/types";
import type { BidFill } from "../bidFill";
import type { DocContext } from "../clauses";
import { Clause } from "./Layout";
import { SECTION_LABELS } from "./RfbSections";

export interface FooterSpec { draft: boolean; number: string | null; version: number | null }

/** Footer template text; {n} and {total} are filled in by the PDF step. */
export function footerTemplate(f: FooterSpec): string {
  if (f.draft) return "DRAFT · Page {n} of {total}";
  if (f.number === null || f.version === null) {
    throw new Error("A final bid form needs a solicitation number and version");
  }
  return `Solicitation ${f.number} · Version ${f.version} · Page {n} of {total}`;
}

function Footer({ footer, n, total }: { footer: FooterSpec; n: number; total: number }) {
  const tpl = footerTemplate(footer);
  const [before, rest] = tpl.split("{n}");
  const [between] = rest.split("{total}");
  return (
    <footer data-footer={footer.draft ? "draft" : "final"} data-footer-template={tpl}>
      {before}<span data-page-n>{n}</span>{between}<span data-page-total>{total}</span>
    </footer>
  );
}

function Page({ footer, n, total, fill, children }: {
  footer: FooterSpec | null; n: number; total: number; fill?: BidFill; children: React.ReactNode;
}) {
  if (!footer) return <section className="bid-page">{children}</section>;
  return (
    <section data-bid-form-page={n} className="bid-page">
      {fill ? <p data-bid-ref className="muted">{`Bid reference ${fill.reference} · Bid version ${fill.bidVersion}`}</p> : null}
      {children}
      <Footer footer={footer} n={n} total={total} />
    </section>
  );
}

const blank = <span className="write-in" />;

/**
 * The bid form pages. With `footer` (standalone bid form PDF) every page is marked
 * data-bid-form-page and carries the footer; without it (embedded in the RFB) pages are plain.
 */
export function BidFormPages({ ctx, req, footer, id, fill }: {
  ctx: DocContext; req: Requirements; footer: FooterSpec | null; id?: string; fill?: BidFill;
}) {
  const { data } = ctx;
  const total = 4;
  const sections = req.requiredSections.map((s) => SECTION_LABELS[s]);
  return (
    <>
      <Page fill={fill} footer={footer} n={1} total={total}>
        <h2 id={id}>Bid Form Instructions</h2>
        <Clause ctx={ctx} k="bid_form_instructions" />
        <h3>Items to submit</h3>
        <ul>{sections.map((s) => <li key={s}>{s}</li>)}</ul>
      </Page>

      <Page fill={fill} footer={footer} n={2} total={total}>
        <h2>Bid Form Section 1: Bid Prices</h2>
        <p>Project: {data.longTitle || data.shortTitle}</p>
        <table data-bid-schedule>
          <thead><tr><th>Item</th><th>Description</th><th className="price">Lump-sum price</th></tr></thead>
          <tbody>
            {data.schedule.items.map((it, i) => (
              <tr key={i}><td>{it.name}</td><td>{it.description}</td><td className="price">{fill ? formatMoney(fill.itemCents[i]) : "$"}</td></tr>
            ))}
          </tbody>
        </table>
        {data.schedule.alternates.length > 0 ? (
          <table data-bid-alternates>
            <thead><tr><th>Alternate</th><th>Description</th><th className="price">Amount to add or deduct</th></tr></thead>
            <tbody>
              {data.schedule.alternates.map((a, i) => (
                <tr key={i}>
                  <td>Alternate {i + 1} ({a.kind === "additive" ? "add" : "deduct"})</td>
                  <td>{a.description}</td>
                  <td className="price">{fill ? formatMoney(fill.alternateCents[i]) : "$"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}
        {data.schedule.alternates.length > 0 ? (
          <p data-alternates-order>
            The alternates above will be taken into account in the order listed, Alternate 1 first.
          </p>
        ) : null}
        <table data-bid-total>
          <tbody><tr><th>TOTAL BID (all items above, excluding alternates)</th><td className="price">{fill ? formatMoney(baseTotalCents(fill.itemCents)) : "$"}</td></tr></tbody>
        </table>
        {req.bonds ? (
          <p data-bond-line>
            {fill
              ? <>Bid bond for ten percent of the total bid: {fill.bidBond === "electronic" ? "Electronic surety bond uploaded" : fill.bidBond === "paper" ? "Paper original mailed" : blank}</>
              : <>Bid bond for ten percent of the total bid is attached: Yes {blank} No {blank}</>}
          </p>
        ) : null}
        {req.federalClauses ? (
          <p data-federal-ack>
            The bidder states that it will comply with the federal funding and domestic content requirements
            of this solicitation. Yes {blank}
          </p>
        ) : null}
        {req.apprenticeCredit ? (
          <p data-apprentice-line>
            The bidder commits apprentices to at least 10% of the labor hours on this project:{" "}
            {fill
              ? (fill.apprenticeCommitment === true ? "Yes" : fill.apprenticeCommitment === false ? "No" : blank)
              : <>Yes {blank} No {blank}</>}
          </p>
        ) : null}
      </Page>

      <Page fill={fill} footer={footer} n={3} total={total}>
        <h2>Bid Form Section 2: Bidder Information and Terms</h2>
        <table>
          <tbody>
            <tr><th>Firm name</th><td>{fill ? fill.legalName : blank}</td></tr>
            <tr><th>Address</th><td>{fill ? fill.address : blank}</td></tr>
            <tr><th>Contact person, phone and email</th><td>{fill ? fill.contact : blank}</td></tr>
            <tr><th>License and registration numbers</th><td>{blank}</td></tr>
            <tr><th>Addenda acknowledged (list numbers)</th><td>{fill && fill.acknowledgedAddenda.length > 0 ? fill.acknowledgedAddenda.join(", ") : blank}</td></tr>
            <tr><th>Claim resident preference?</th><td>
              {fill
                ? (fill.residentClaimed ? `Yes (certificate ${fill.residentCertificate ?? ""})` : "No")
                : <>Yes {blank} No {blank}</>}
            </td></tr>
          </tbody>
        </table>
        <Clause ctx={ctx} k="bid_form_terms" />
      </Page>

      <Page fill={fill} footer={footer} n={4} total={total}>
        <h2>Signature Page</h2>
        <Clause ctx={ctx} k="signature_certifications" />
        <div className="sig-line" />
        <p>Authorized signature</p>
        <p>Printed name and title: {blank}</p>
        <p>Date: {blank}</p>
      </Page>
    </>
  );
}
