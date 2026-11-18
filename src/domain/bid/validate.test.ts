import { describe, expect, it } from "vitest";
import { emptySolicitation } from "../solicitation/schema";
import type { SolicitationData } from "../solicitation/types";
import { baseTotalCents, requiredUploadSlots, validateBidDraft } from "./validate";
import type { BidDraft } from "./types";

// Matches the pgTAP fixture: 2 items, 1 deductive alternate, $150,000.00, optional section "references".
function fixture(over: Partial<SolicitationData> = {}): SolicitationData {
  return {
    ...emptySolicitation(),
    estimateCents: 15_000_000,
    schedule: {
      items: [{ name: "Base bid", description: "" }, { name: "Item 2", description: "" }],
      alternates: [{ kind: "deductive", description: "Omit canopy" }],
    },
    optionalSections: ["references"],
    ...over,
  };
}

function draft(over: Partial<BidDraft> = {}): BidDraft {
  return {
    bidId: "b1", reference: "K7QM-2XV0", version: 1,
    itemCents: [12_500_000, 234_567], alternateCents: [1_500_000], bidBondChoice: "paper",
    files: [
      { slot: "insurance", path: "bids/b1/u1/ins.pdf", fileName: "ins.pdf" },
      { slot: "references", path: "bids/b1/u2/ref.pdf", fileName: "ref.pdf" },
    ],
    ...over,
  };
}

describe("requiredUploadSlots", () => {
  it("is insurance and the optional sections for a paper bond", () => {
    expect(requiredUploadSlots(fixture(), "paper")).toEqual(["insurance", "references"]);
  });
  it("adds bid_bond for an electronic bond", () => {
    expect(requiredUploadSlots(fixture(), "electronic")).toEqual(["insurance", "references", "bid_bond"]);
  });
  it("adds nothing for a missing choice", () => {
    expect(requiredUploadSlots(fixture(), null)).toEqual(["insurance", "references"]);
  });
  it("never needs a bond file below the bond threshold", () => {
    const d = fixture({ estimateCents: 14_999_999 });
    expect(requiredUploadSlots(d, null)).toEqual(["insurance", "references"]);
    expect(requiredUploadSlots(d, "electronic")).toEqual(["insurance", "references"]);
  });
  it("keeps the solicitation's section order", () => {
    expect(requiredUploadSlots(fixture({ optionalSections: ["qualifications", "current_work"] }), null))
      .toEqual(["insurance", "qualifications", "current_work"]);
  });
  it("treats an unknown estimate as below the threshold", () => {
    expect(requiredUploadSlots(fixture({ estimateCents: null }), "electronic")).toEqual(["insurance", "references"]);
  });
});

describe("validateBidDraft", () => {
  it("accepts a complete draft", () => {
    expect(validateBidDraft(draft(), fixture())).toEqual([]);
  });
  it("flags a null item price", () => {
    const issues = validateBidDraft(draft({ itemCents: [12_500_000, null] }), fixture());
    expect(issues).toEqual([expect.objectContaining({ code: "price_missing", field: "items.1" })]);
  });
  it("flags a null alternate price", () => {
    const issues = validateBidDraft(draft({ alternateCents: [null] }), fixture());
    expect(issues).toEqual([expect.objectContaining({ code: "price_missing", field: "alternates.0" })]);
  });
  it("flags a wrong number of item prices as price_count", () => {
    const issues = validateBidDraft(draft({ itemCents: [1, 2, 3] }), fixture());
    expect(issues).toEqual([expect.objectContaining({ code: "price_count", field: "items" })]);
  });
  it("flags a wrong number of alternate prices as price_count", () => {
    const issues = validateBidDraft(draft({ alternateCents: [1, 2] }), fixture());
    expect(issues).toEqual([expect.objectContaining({ code: "price_count", field: "alternates" })]);
  });
  it("reads an empty price array as price_missing, not price_count (matches bid_draft_problems)", () => {
    const issues = validateBidDraft(draft({ itemCents: [], alternateCents: [] }), fixture());
    expect(issues.map((i) => i.code)).toEqual(["price_missing", "price_missing", "price_missing"]);
    expect(issues.map((i) => i.field)).toEqual(["items.0", "items.1", "alternates.0"]);
  });
  it("accepts an empty array when the schedule has no entries of that kind", () => {
    const d = fixture({ schedule: { items: [{ name: "Base bid", description: "" }], alternates: [] } });
    expect(validateBidDraft(draft({ itemCents: [100], alternateCents: [] }), d)).toEqual([]);
  });
  it("flags a missing upload with the slot in the field", () => {
    const issues = validateBidDraft(draft({ files: [draft().files[0]] }), fixture());
    expect(issues).toEqual([expect.objectContaining({ code: "upload_missing", field: "uploads.references" })]);
  });
  it("needs a bid bond file for an electronic choice", () => {
    const issues = validateBidDraft(draft({ bidBondChoice: "electronic" }), fixture());
    expect(issues).toEqual([expect.objectContaining({ code: "upload_missing", field: "uploads.bid_bond" })]);
  });
  it("flags no bond choice at $150,000.00", () => {
    const issues = validateBidDraft(draft({ bidBondChoice: null }), fixture());
    expect(issues).toEqual([expect.objectContaining({ code: "bond_choice_missing", field: "bond" })]);
  });
  it("flags a choice below the threshold as bond_not_required", () => {
    const d = fixture({ estimateCents: 14_999_999 });
    const issues = validateBidDraft(draft({ bidBondChoice: "paper" }), d);
    expect(issues).toEqual([expect.objectContaining({ code: "bond_not_required", field: "bond" })]);
    expect(validateBidDraft(draft({ bidBondChoice: null }), d)).toEqual([]);
  });
  it("never reports file_missing (database only)", () => {
    expect(validateBidDraft(draft({ files: [] }), fixture()).some((i) => i.code === "file_missing")).toBe(false);
  });
  it("lists price_count before price_missing before uploads before the bond, as the database does", () => {
    const issues = validateBidDraft(
      draft({ itemCents: [1, 2, 3], alternateCents: [null], files: [], bidBondChoice: null }), fixture());
    expect(issues.map((i) => i.code)).toEqual(["price_count", "price_missing", "upload_missing", "upload_missing", "bond_choice_missing"]);
  });
});

describe("baseTotalCents", () => {
  it("sums integer cents exactly", () => {
    expect(baseTotalCents([12_500_000, 234_567])).toBe(12_734_567);
  });
  it("is zero for no items", () => {
    expect(baseTotalCents([])).toBe(0);
  });
});
