import { describe, expect, it } from "vitest";
import type { SolicitationData } from "../domain/solicitation/types";
import { renderAddendumHtml, renderBidFormHtml, renderRfbHtml, type AddendumDocContext } from "./renderHtml";
import { ctxWith } from "./testFixtures";
import type { BidFill } from "./bidFill";
import { extractFooterTemplate } from "./pdf";

const html = (est: number, extra: Partial<SolicitationData> = {}) =>
  renderRfbHtml(ctxWith(est, extra), { draft: false });

function checklistRows(h: string): string[] {
  return [...h.matchAll(/<tr data-checklist-row[^>]*><td[^>]*>(.*?)<\/td>/g)].map((m) => m[1]);
}

const twoItemsOneAlternate: Partial<SolicitationData> = {
  schedule: {
    items: [
      { name: "Dormitory A", description: "Roof" },
      { name: "Dormitory B", description: "" },
    ],
    alternates: [{ kind: "additive", description: "Add gutters" }],
  },
};

describe("RFB conditional sections", () => {
  it("bid deposit and bonds at the bonds band", () => {
    expect(html(16_000_000)).toContain('data-clause="bid_deposit"');
    expect(html(14_999_999)).not.toContain('data-clause="bid_deposit"');
    expect(html(16_000_000)).toContain('data-clause="performance_bond"');
    expect(html(14_999_999)).not.toContain('data-clause="performance_bond"');
  });
  it("prevailing wage at its band", () => {
    expect(html(9_999_999)).not.toContain('data-clause="prevailing_wage"');
    expect(html(10_000_000)).toContain('data-clause="prevailing_wage"');
  });
  it("apprentice credit at its band", () => {
    expect(html(99_999_999)).not.toContain('data-clause="apprentice_credit"');
    expect(html(100_000_000)).toContain('data-clause="apprentice_credit"');
  });
  it("federal clauses", () => {
    expect(html(16_000_000, { federalFunds: true })).toContain('data-clause="federal_domestic_content"');
    expect(html(16_000_000, { federalFunds: false })).not.toContain('data-clause="federal_domestic_content"');
  });
  it("pre-bid and background check clauses", () => {
    expect(html(16_000_000)).not.toContain('data-clause="prebid_meeting"');
    expect(html(16_000_000)).not.toContain('data-clause="background_check"');
    const withMeeting = html(16_000_000, {
      preBid: { kind: "mandatory", format: "in_person", date: "2027-05-10", time: "10:00", location: "Room 4" },
      backgroundCheck: { required: true, contact: "Site Security", leadDays: 10 },
    });
    expect(withMeeting).toContain('data-clause="prebid_meeting"');
    expect(withMeeting).toContain('data-clause="background_check"');
    expect(withMeeting).toContain("Room 4");
  });
});

describe("escaping", () => {
  it("escapes free text", () => {
    expect(html(16_000_000, { projectDescription: "<script>alert(1)</script> R&D" }))
      .toContain("&lt;script&gt;alert(1)&lt;/script&gt; R&amp;D");
    const h = html(16_000_000, {
      summary: "<img src=x>", scopeNotes: "<i>n</i>", specialProvisions: "<u>p</u>",
      longTitle: "<b>T</b>", location: { address: "<a>", city: "c", county: "d" },
    });
    for (const raw of ["<img src=x>", "<i>n</i>", "<u>p</u>", "<b>T</b>", "<a>"]) expect(h).not.toContain(raw);
  });
});

describe("draft marking", () => {
  it("RFB draft carries the watermark", () => {
    expect(renderRfbHtml(ctxWith(16_000_000), { draft: true })).toContain("DRAFT — NOT FOR BIDDING");
    expect(html(16_000_000)).not.toContain("DRAFT — NOT FOR BIDDING");
  });
});

describe("evaluation checklist", () => {
  it("lists exactly the required sections", () => {
    expect(checklistRows(html(16_000_000, { optionalSections: ["references"] }))).toEqual(
      ["Bid Form Section 1", "Bid Form Section 2", "Signature Page", "Proof of Insurance", "References"]);
  });
  it("prints page limits", () => {
    expect(html(16_000_000, { optionalSections: ["references"], pageLimits: { references: 3 } }))
      .toContain("3 pages");
  });
});

describe("bid form", () => {
  const form = (extra: Partial<SolicitationData> = {}, est = 16_000_000) =>
    renderBidFormHtml(ctxWith(est, extra), { draft: false });

  it("lists items, then alternates, then the total", () => {
    expect(form(twoItemsOneAlternate)).toMatch(/Dormitory A[\s\S]*Dormitory B[\s\S]*Alternate 1[\s\S]*TOTAL/);
  });
  it("final footer", () => {
    const h = form();
    expect(h).toContain("Solicitation 27-0001 · Version 1");
    expect(h).toContain('data-footer-template="Solicitation 27-0001 · Version 1 · Page {n} of {total}"');
    expect(h).toContain("data-page-n");
    expect(h).toContain("data-page-total");
  });
  it("every page is marked and has a footer", () => {
    const h = form();
    const pages = (h.match(/<section data-bid-form-page/g) ?? []).length;
    expect(pages).toBeGreaterThanOrEqual(3);
    expect((h.match(/<footer data-footer/g) ?? []).length).toBe(pages);
  });
  it("draft footer has no number or version", () => {
    const h = renderBidFormHtml(ctxWith(16_000_000, {}, { number: null, version: null }), { draft: true });
    expect(h).toContain("DRAFT");
    expect(h).toContain("DRAFT · Page");
    expect(h).not.toContain("Version");
    expect(h).not.toContain("27-0001");
  });
  it("bond line and apprentice commitment line follow the bands", () => {
    expect(form()).toContain("data-bond-line");
    expect(form({}, 14_999_999)).not.toContain("data-bond-line");
    expect(form({}, 100_000_000)).toContain("data-apprentice-line");
    expect(form({}, 99_999_999)).not.toContain("data-apprentice-line");
    expect(form({}, 15_000_000)).not.toContain("data-apprentice-line");
    expect(form({}, 100_000_000)).not.toContain("data-apprentice-question");
  });
  it("the blank $1,000,000.00 form asks for the commitment with two write-in blanks", () => {
    const line = /<p data-apprentice-line[^>]*>([\s\S]*?)<\/p>/.exec(form({}, 100_000_000))?.[1];
    expect(line).toBe(
      "The bidder commits apprentices to at least 10% of the labor hours on this project: Yes " +
      '<span class="write-in"></span> No <span class="write-in"></span>');
  });
  it("federal compliance acknowledgment follows federalFunds", () => {
    expect(form({ federalFunds: true })).toContain("data-federal-ack");
    expect(form({ federalFunds: false })).not.toContain("data-federal-ack");
  });
  it("states the alternates order only when alternates exist", () => {
    const h = form(twoItemsOneAlternate);
    expect(h).toContain("data-alternates-order");
    expect(h).toMatch(/in the order listed/);
    expect(form()).not.toContain("data-alternates-order");
  });
  it("escapes item names", () => {
    expect(form({ schedule: { items: [{ name: "<b>x</b>", description: "" }], alternates: [] } }))
      .not.toContain("<b>x</b>");
  });
});

describe("bid form fill", () => {
  const fill: BidFill = {
    legalName: "R&D Builders <Calder>", address: "1 Elm St, Calder City", contact: "Ana Ridge, 555-0142, ana@example.test",
    residentClaimed: true, residentCertificate: "RC-123", reference: "K7QM-2XVD", bidVersion: 2,
    itemCents: [12_500_000, 234_567], alternateCents: [1_500_000], bidBond: "paper", apprenticeCommitment: null,
    acknowledgedAddenda: [],
  };
  const ctx = ctxWith(16_000_000, {
    schedule: {
      items: [{ name: "Dormitory A", description: "Roof" }, { name: "Dormitory B", description: "" }],
      alternates: [{ kind: "additive", description: "Add gutters" }],
    },
  });
  const filled = renderBidFormHtml(ctx, { draft: false, fill });
  const cells = (attr: string) =>
    [...(new RegExp(String.raw`<table data-${attr}[\s\S]*?</table>`).exec(filled)?.[0] ?? "").matchAll(/<td class="price">([^<]*)<\/td>/g)].map((m) => m[1]);

  it("escapes and shows the legal name, address, contact and resident claim", () => {
    expect(filled).toContain("R&amp;D Builders &lt;Calder&gt;");
    expect(filled).not.toContain("R&D Builders <Calder>");
    expect(filled).toContain("1 Elm St, Calder City");
    expect(filled).toContain("Ana Ridge, 555-0142, ana@example.test");
    expect(filled).toContain("RC-123");
  });
  it("prices in snapshot order, from cents, with the total", () => {
    expect(cells("bid-schedule")).toEqual(["$125,000.00", "$2,345.67"]);
    expect(cells("bid-alternates")).toEqual(["$15,000.00"]);
    expect(cells("bid-total")).toEqual(["$127,345.67"]);
  });
  it("every page carries the bid reference and version", () => {
    const refs = [...filled.matchAll(/<p data-bid-ref[^>]*>([^<]*)<\/p>/g)].map((m) => m[1]);
    expect(refs).toEqual(Array(4).fill("Bid reference K7QM-2XVD · Bid version 2"));
  });
  it("footer is the slice 1 final footer", () => {
    expect(extractFooterTemplate(filled)).toBe("Solicitation 27-0001 · Version 1 · Page {n} of {total}");
  });
  it("bond line reflects the choice", () => {
    expect(filled).toContain("Paper original mailed");
    expect(renderBidFormHtml(ctx, { draft: false, fill: { ...fill, bidBond: "electronic" } })).toContain("Electronic surety bond uploaded");
  });
  it("prints the apprentice answer on a $1,000,000.00 filled form", () => {
    const big = ctxWith(100_000_000, { schedule: ctx.data.schedule });
    const line = (f: BidFill) =>
      /<p data-apprentice-line[^>]*>([\s\S]*?)<\/p>/.exec(renderBidFormHtml(big, { draft: false, fill: f }))?.[1];
    expect(line({ ...fill, apprenticeCommitment: true }))
      .toBe("The bidder commits apprentices to at least 10% of the labor hours on this project: Yes");
    expect(line({ ...fill, apprenticeCommitment: false }))
      .toBe("The bidder commits apprentices to at least 10% of the labor hours on this project: No");
  });
  it("a $160,000.00 filled form has no apprentice line", () => {
    expect(filled).not.toContain("data-apprentice-line");
  });
  it("without a fill the output is unchanged from slice 1", () => {
    expect(renderBidFormHtml(ctx, { draft: false })).toMatchSnapshot();
    expect(renderBidFormHtml(ctx, { draft: true })).toMatchSnapshot();
  });
});

describe("addendum PDF", () => {
  const ctx: AddendumDocContext = {
    number: 1,
    version: 2,
    solicitationNumber: "27-0001",
    title: "Dormitory Roof Repair",
    publishedOn: "2027-06-10",
    narrative: "Adds a third dormitory.\n\nMoves the bid due date one week later.",
    changes: [
      { kind: "item", change: "added", position: 3, after: "Dormitory C: Roof" },
      { kind: "alternate", change: "changed", position: 1, before: "Additive: Add gutters", after: "Additive: Add <gutters> & downspouts" },
    ],
    dateChanges: [{ field: "Bids due", before: "July 1, 2027, 1:00 PM MDT", after: "July 8, 2027, 1:00 PM MDT" }],
    answers: [{ publishedQuestion: "Is the roof membrane specified?", answer: "Yes, see section 07 54 00." }],
  };
  const out = renderAddendumHtml(ctx);

  it("matches the snapshot", () => {
    expect(out).toMatchSnapshot();
  });
  it("prints the narrative, the schedule changes, the dates and the answered question", () => {
    expect(out).toContain("<p>Adds a third dormitory.</p>");
    expect(out).toContain("<p>Moves the bid due date one week later.</p>");
    expect(out).toContain("Item 3 added: Dormitory C: Roof");
    expect(out).toContain("Add &lt;gutters&gt; &amp; downspouts");
    expect(out).toContain("July 8, 2027, 1:00 PM MDT");
    expect(out).toContain("Is the roof membrane specified?");
    expect(out).toContain("Yes, see section 07 54 00.");
    expect(out).toContain("Version 2");
    expect(out).toContain("June 10, 2027");
  });
  it("uses the bid form footer mechanism with the solicitation number and version", () => {
    expect(extractFooterTemplate(out)).toBe("Solicitation 27-0001 · Version 2 · Page {n} of {total}");
  });
  it("says so when nothing changed and nothing was answered", () => {
    const empty = renderAddendumHtml({ ...ctx, changes: [], dateChanges: [], answers: [] });
    expect(empty).toContain("This addendum does not change the bid schedule.");
    expect(empty).toContain("This addendum does not change the key dates.");
    expect(empty).toContain("This addendum does not answer any questions.");
  });
});

describe("addenda acknowledged on the bid form", () => {
  const ctx = ctxWith(16_000_000);
  const fill: BidFill = {
    legalName: "Ridge Builders", address: "1 Elm St", contact: "Ana Ridge, 555-0142, ana@example.test",
    residentClaimed: false, residentCertificate: null, reference: "K7QM-2XVD", bidVersion: 1,
    itemCents: [12_500_000], alternateCents: [], bidBond: "paper", apprenticeCommitment: null,
    acknowledgedAddenda: [1, 2],
  };
  const cell = (h: string) =>
    /<tr><th>Addenda acknowledged \(list numbers\)<\/th><td>([\s\S]*?)<\/td><\/tr>/.exec(h)?.[1];

  it("prints the acknowledged numbers joined by comma-space", () => {
    expect(cell(renderBidFormHtml(ctx, { draft: false, fill }))).toBe("1, 2");
  });
  it("prints the blank line when nothing is acknowledged", () => {
    expect(cell(renderBidFormHtml(ctx, { draft: false, fill: { ...fill, acknowledgedAddenda: [] } })))
      .toBe('<span class="write-in"></span>');
  });
  it("prints the blank line on a blank form", () => {
    expect(cell(renderBidFormHtml(ctx, { draft: false }))).toBe('<span class="write-in"></span>');
  });
});
