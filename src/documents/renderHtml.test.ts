import { describe, expect, it } from "vitest";
import type { SolicitationData } from "../domain/solicitation/types";
import { renderBidFormHtml, renderRfbHtml } from "./renderHtml";
import { ctxWith } from "./testFixtures";

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
  it("bond line and apprentice question follow the bands", () => {
    expect(form()).toContain("data-bond-line");
    expect(form({}, 14_999_999)).not.toContain("data-bond-line");
    expect(form({}, 100_000_000)).toContain("data-apprentice-question");
    expect(form({}, 99_999_999)).not.toContain("data-apprentice-question");
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
