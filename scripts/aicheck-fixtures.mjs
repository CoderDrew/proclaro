// Generates fictional documents for the AI document check: filled bid forms, insurance certificates, bid bonds and
// section documents, rendered with Chromium and rasterized to image-only PDFs (like scans: no text layer). Writes
// fixtures/aicheck/*.pdf and fixtures/aicheck/manifest.json (what each file is, the facts to check it against, and
// the expected result per checklist item). All names are fictional (State of Calder).
//
//   npm run aicheck:fixtures
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { chromium } from "playwright-core";
import { PDFDocument } from "pdf-lib";

const OUT = join(process.cwd(), "fixtures", "aicheck");
const AGENCY = "Calder Department of Corrections";
const DUE = "2026-12-01";
const SIGN = `<svg width="220" height="50" viewBox="0 0 220 50"><path d="M5 35 C 25 5, 40 45, 60 20 S 95 40, 110 15 S 150 45, 170 22 S 200 30, 215 18" stroke="#123" stroke-width="2.4" fill="none"/></svg>`;
const HAND = "font-family: 'Comic Sans MS', 'Segoe Print', cursive; color: #1a2a6c; font-size: 15px;";

const css = `
  body { margin: 0; font-family: 'Times New Roman', serif; }
  .page { width: 816px; height: 1056px; box-sizing: border-box; padding: 64px 72px; position: relative;
          background: #fbfaf6; filter: grayscale(0.4) contrast(1.05); transform: rotate(0.35deg); }
  h1 { font-size: 20px; text-align: center; margin: 0 0 18px; }
  table { width: 100%; border-collapse: collapse; margin: 10px 0; }
  td, th { border: 1px solid #333; padding: 6px 8px; font-size: 13px; vertical-align: top; }
  .line { border-bottom: 1px solid #333; display: inline-block; min-width: 260px; padding: 0 6px; }
  .hand { ${HAND} }
  .foot { position: absolute; bottom: 36px; left: 72px; right: 72px; font-size: 11px; text-align: center; color: #333; }
  p { font-size: 14px; line-height: 1.45; }
`;

function bidForm({ bidder, number, version, words, figures, addenda, signed, certificate }) {
  const foot = (i) => `<div class="foot">Solicitation ${number} · Version ${version} · Page ${i} of 3</div>`;
  return [
    `<div class="page"><h1>Bid Form, Section 1</h1>
      <p>Bidder: <span class="line">${bidder}</span></p>
      <p>Solicitation: ${number}, Maintenance Building Expansion</p>
      <table><tr><th>Line</th><th>Description</th><th>Amount</th></tr>
        <tr><td>Base total</td><td>Base bid and Item 2</td><td class="hand">${figures}</td></tr></table>
      <p>Total bid amount in words:</p><p class="line hand" style="min-width:600px">${words}</p>
      ${foot(1)}</div>`,
    `<div class="page"><h1>Bid Form, Section 2</h1>
      <p>Addenda acknowledged (list numbers): <span class="line hand">${addenda}</span></p>
      <p>Resident bidder certificate number (if claimed): <span class="line hand">${certificate ?? ""}</span></p>
      <p>☑ The bidder has read the solicitation and the general conditions.</p>
      ${foot(2)}</div>`,
    `<div class="page"><h1>Signature Page</h1>
      <p>The undersigned offers to perform the work for the amounts stated in this bid.</p>
      <p>Bidder: <span class="line">${bidder}</span></p>
      <p>Signature: <span class="line" style="height:52px">${signed ? SIGN : ""}</span></p>
      <p>Name and title: <span class="line hand">${signed ? "Authorized Officer, President" : ""}</span></p>
      ${foot(3)}</div>`,
  ];
}

function insurance({ insured, from, to }) {
  return [`<div class="page"><h1>Certificate of Liability Insurance</h1>
    <p>Producer: Calder Mutual Agency, 3 Market Street, Calderton</p>
    <p>Insured: <span class="line">${insured}</span></p>
    <table><tr><th>Type of insurance</th><th>Policy number</th><th>Effective</th><th>Expires</th><th>Limits</th></tr>
      <tr><td>Commercial general liability</td><td>CGL-55120</td><td>${from}</td><td>${to}</td><td>$1,000,000 each occurrence</td></tr></table>
    <p>Certificate holder: ${AGENCY}</p></div>`];
}

function bond({ principal, obligee, suretySigned }) {
  return [`<div class="page"><h1>Bid Bond</h1>
    <p>Know all persons by these presents that <span class="line">${principal}</span>, as Principal, and Calder Surety
       Company, as Surety, are held and firmly bound unto <span class="line">${obligee}</span>, as Obligee, in the sum of
       five percent (5%) of the amount bid.</p>
    <p>Principal signature: <span class="line" style="height:52px">${SIGN}</span></p>
    <p>Surety (attorney-in-fact) signature: <span class="line" style="height:52px">${suretySigned ? SIGN : ""}</span></p>
    </div>`];
}

function section({ title, body }) {
  return [`<div class="page"><h1>${title}</h1><p>${body}</p></div>`];
}

const OBLIGEE = `State of Calder, ${AGENCY}`;
const base = (legalName, baseTotalCents, residentCertificate = null) => ({
  legalName, baseTotalCents, publishedAddenda: [], submittedFormVersion: 1, residentCertificate, agencyName: AGENCY,
  dueLocalDate: DUE,
});
const allMet = (codes) => Object.fromEntries(codes.map((c) => [c, "met"]));
const FORM = ["signature_present", "amount_in_words", "addenda_listed", "form_version"];
const INS = ["insured_name", "coverage_dates"];
const BOND = ["principal_name", "obligee", "surety_signature"];

const R = base("Ridgeback Builders LLC", 120000000, "CR-0042");
const G = base("Granite Mesa Contractors", 118000000);
const J = base("Juniper Flats Paving", 117500000);
const B = base("Basalt Creek Builders", 119000000);

// seed: which 27-0003 bidder (and document) the seed uses this file for; null = evaluation only.
const DOCS = [
  { file: "ridgeback-signed-form.pdf", kind: "signed_form", seed: "ridgeback", facts: R,
    pages: bidForm({ bidder: "Ridgeback Builders LLC", number: "27-0003", version: 1, figures: "$1,200,000.00",
      words: "One Million Two Hundred Thousand and 00/100 Dollars", addenda: "None", signed: true, certificate: "CR-0042" }),
    expected: { ...allMet(FORM), resident_certificate: "met" } },
  { file: "ridgeback-insurance.pdf", kind: "insurance", seed: "ridgeback", facts: R,
    pages: insurance({ insured: "Ridgeback Builders, L.L.C.", from: "01/01/2026", to: "12/31/2027" }), expected: allMet(INS) },
  { file: "ridgeback-bond.pdf", kind: "bid_bond_scan", seed: "ridgeback", facts: R,
    pages: bond({ principal: "Ridgeback Builders LLC", obligee: OBLIGEE, suretySigned: true }), expected: allMet(BOND) },

  { file: "granite-signed-form.pdf", kind: "signed_form", seed: "granite", facts: G,
    pages: bidForm({ bidder: "Granite Mesa Contractors", number: "27-0003", version: 1, figures: "$1,180,000.00",
      words: "One Million One Hundred Eighty Thousand Dollars and 00/100", addenda: "None", signed: true }),
    expected: allMet(FORM) },
  { file: "granite-insurance.pdf", kind: "insurance", seed: "granite", facts: G,
    pages: insurance({ insured: "Granite Mesa Contractors", from: "07/01/2025", to: "06/30/2026" }),
    expected: { insured_name: "met", coverage_dates: "not_met" }, defect: "Insurance expires before the bid due date." },
  { file: "granite-bond.pdf", kind: "bid_bond_scan", seed: "granite", facts: G,
    pages: bond({ principal: "Granite Mesa Contractors", obligee: OBLIGEE, suretySigned: true }), expected: allMet(BOND) },

  { file: "juniper-signed-form.pdf", kind: "signed_form", seed: "juniper", facts: J,
    pages: bidForm({ bidder: "Juniper Flats Paving", number: "27-0003", version: 1, figures: "$1,175,000.00",
      words: "One Million One Hundred Fifty-Seven Thousand Five Hundred Dollars", addenda: "None", signed: true }),
    expected: { ...allMet(FORM), amount_in_words: "not_met" }, defect: "Amount in words differs from the portal total." },
  { file: "juniper-insurance.pdf", kind: "insurance", seed: "juniper", facts: J,
    pages: insurance({ insured: "Juniper Flats Paving", from: "2026-03-01", to: "2027-03-01" }), expected: allMet(INS) },
  { file: "juniper-bond.pdf", kind: "bid_bond_scan", seed: "juniper", facts: J,
    pages: bond({ principal: "Juniper Flats Paving", obligee: OBLIGEE, suretySigned: true }), expected: allMet(BOND) },

  { file: "basalt-signed-form.pdf", kind: "signed_form", seed: "basalt", facts: B,
    pages: bidForm({ bidder: "Basalt Creek Builders", number: "27-0003", version: 1, figures: "$1,190,000.00",
      words: "One Million One Hundred Ninety Thousand Dollars", addenda: "1", signed: true }),
    expected: { ...allMet(FORM), addenda_listed: "not_met" }, defect: "Lists Addendum 1, but 27-0003 has no addenda." },
  { file: "basalt-insurance.pdf", kind: "insurance", seed: "basalt", facts: B,
    pages: insurance({ insured: "Basalt Creek Builders", from: "2026-01-15", to: "2027-01-15" }), expected: allMet(INS) },

  // Evaluation only.
  { file: "eval-unsigned-form.pdf", kind: "signed_form", seed: null, facts: R,
    pages: bidForm({ bidder: "Ridgeback Builders LLC", number: "27-0003", version: 1, figures: "$1,200,000.00",
      words: "One Million Two Hundred Thousand Dollars", addenda: "None", signed: false, certificate: "CR-0042" }),
    expected: { ...allMet(FORM), signature_present: "not_met", resident_certificate: "met" }, defect: "Unsigned." },
  { file: "eval-wrong-version-form.pdf", kind: "signed_form", seed: null, facts: { ...G, submittedFormVersion: 2 },
    pages: bidForm({ bidder: "Granite Mesa Contractors", number: "27-0003", version: 1, figures: "$1,180,000.00",
      words: "One Million One Hundred Eighty Thousand Dollars", addenda: "None", signed: true }),
    expected: { ...allMet(FORM), form_version: "not_met" }, defect: "Version 1 form for a version 2 bid." },
  { file: "eval-wrong-certificate-form.pdf", kind: "signed_form", seed: null, facts: R,
    pages: bidForm({ bidder: "Ridgeback Builders LLC", number: "27-0003", version: 1, figures: "$1,200,000.00",
      words: "One Million Two Hundred Thousand Dollars", addenda: "None", signed: true, certificate: "CR-0420" }),
    expected: { ...allMet(FORM), resident_certificate: "not_met" }, defect: "Certificate number differs from the claim." },
  { file: "eval-wrong-insured.pdf", kind: "insurance", seed: null, facts: J,
    pages: insurance({ insured: "Juniper Ridge Excavation Inc.", from: "2026-01-01", to: "2027-12-31" }),
    expected: { insured_name: "not_met", coverage_dates: "met" }, defect: "Insured is another company." },
  { file: "eval-wrong-principal-bond.pdf", kind: "bid_bond", seed: null, facts: B,
    pages: bond({ principal: "Basalt Ridge Masonry", obligee: OBLIGEE, suretySigned: true }),
    expected: { principal_name: "not_met", obligee: "met", surety_signature: "met" }, defect: "Principal is another company." },
  { file: "eval-wrong-obligee-bond.pdf", kind: "bid_bond", seed: null, facts: G,
    pages: bond({ principal: "Granite Mesa Contractors", obligee: "Calder County School District", suretySigned: true }),
    expected: { principal_name: "met", obligee: "not_met", surety_signature: "met" }, defect: "Obligee is not the agency." },
  { file: "eval-unsigned-surety-bond.pdf", kind: "bid_bond", seed: null, facts: B,
    pages: bond({ principal: "Basalt Creek Builders", obligee: OBLIGEE, suretySigned: false }),
    expected: { principal_name: "met", obligee: "met", surety_signature: "not_met" }, defect: "No surety signature." },
  { file: "eval-qualifications.pdf", kind: "qualifications", seed: null, facts: R,
    pages: section({ title: "Statement of Qualifications", body: "Ridgeback Builders LLC has completed fourteen public works projects in Calder since 2015, including three maintenance facilities. Key staff: project manager (18 years), superintendent (22 years). Bonding capacity: $8,000,000." }),
    expected: { document_matches_slot: "met" } },
  { file: "eval-wrong-qualifications.pdf", kind: "qualifications", seed: null, facts: R,
    pages: section({ title: "Invoice 4471", body: "Calder Lumber Supply. Bill to: Ridgeback Builders LLC. 40 sheets plywood, $1,840.00. Payment due in 30 days." }),
    expected: { document_matches_slot: "not_met" }, defect: "An invoice uploaded as qualifications." },
];

async function main() {
  mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 816, height: 1056 } });
    for (const d of DOCS) {
      const pdf = await PDFDocument.create();
      for (const html of d.pages) {
        await page.setContent(`<html><head><style>${css}</style></head><body>${html}</body></html>`, { waitUntil: "load" });
        const png = await page.screenshot({ type: "png", clip: { x: 0, y: 0, width: 816, height: 1056 } });
        const img = await pdf.embedPng(png);
        const p = pdf.addPage([612, 792]);
        p.drawImage(img, { x: 0, y: 0, width: 612, height: 792 });
      }
      writeFileSync(join(OUT, d.file), await pdf.save());
    }
  } finally {
    await browser.close();
  }
  const manifest = DOCS.map((d) => Object.fromEntries(Object.entries(d).filter(([k]) => k !== "pages")));
  writeFileSync(join(OUT, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  console.log(`Wrote ${DOCS.length} documents and manifest.json to fixtures/aicheck/`);
}

main().catch((e) => { console.error(e); process.exit(1); });
