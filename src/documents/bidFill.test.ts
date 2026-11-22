import { describe, expect, it } from "vitest";
import type { BidDraft } from "@/domain/bid/types";
import { toBidFill, type BidderCompany } from "./bidFill";

const company: BidderCompany = {
  org_id: "o1", address: "1 Elm St", contact_name: "Ana Ridge", contact_phone: "555-0142",
  contact_email: "ana@example.test", resident_claimed: false, resident_certificate: null, created_at: "2027-01-01",
};
const draft = (over: Partial<BidDraft> = {}): BidDraft => ({
  bidId: "b1", reference: "K7QM-2XVD", version: 3, itemCents: [100, 200], alternateCents: [50],
  bidBondChoice: "paper", apprenticeCommitment: null, files: [], ...over,
});

describe("toBidFill", () => {
  it("builds the fill from a complete draft", () => {
    expect(toBidFill(company, "Ridge Builders", draft(), [])).toEqual({
      legalName: "Ridge Builders", address: "1 Elm St", contact: "Ana Ridge, 555-0142, ana@example.test",
      residentClaimed: false, residentCertificate: null, reference: "K7QM-2XVD", bidVersion: 3,
      itemCents: [100, 200], alternateCents: [50], bidBond: "paper", apprenticeCommitment: null,
      acknowledgedAddenda: [],
    });
  });
  it("carries the apprentice commitment", () => {
    const fill = toBidFill(company, "R", draft({ apprenticeCommitment: true }), []);
    expect(fill).toMatchObject({ apprenticeCommitment: true });
  });
  it("is incomplete when any item price is null", () => {
    expect(toBidFill(company, "R", draft({ itemCents: [100, null] }), [])).toEqual({ incomplete: true });
  });
  it("is incomplete when any alternate price is null", () => {
    expect(toBidFill(company, "R", draft({ alternateCents: [null] }), [])).toEqual({ incomplete: true });
  });
  it("is incomplete with no item prices at all", () => {
    expect(toBidFill(company, "R", draft({ itemCents: [] }), [])).toEqual({ incomplete: true });
  });
  it("carries the acknowledged addenda ascending, without duplicates", () => {
    expect(toBidFill(company, "R", draft(), [2, 1, 2])).toMatchObject({ acknowledgedAddenda: [1, 2] });
  });
});
