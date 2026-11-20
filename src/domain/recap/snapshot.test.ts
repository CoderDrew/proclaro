import { describe, expect, it } from "vitest";
import { memoText, parseAward, parseRecap, recapColumns, type MemoSnapshot, type RecapSnapshot } from "./snapshot";

const row = {
  bidId: "11111111-1111-4111-8111-111111111111",
  reference: "B-0001",
  bidderName: "Calder Builders",
  baseCents: 100000000,
  alternateCents: [10000000, 1],
  totalCents: 110000000,
  evaluatedCents: 110000000,
  resident: false,
  apprenticeCredit: false,
  residentPreferred: false,
  rank: 1,
  tied: false,
};

const recap: RecapSnapshot = {
  kind: "recap",
  reason: null,
  solicitationNumber: "CAL-2026-0001",
  fundingCents: 110000000,
  fundingFromEstimate: false,
  alternates: [
    { kind: "additive", description: "Add canopy" },
    { kind: "additive", description: "Add bike racks" },
  ],
  selectedAlternates: [1],
  rows: [row],
  expectedWinnerBidId: row.bidId,
  winnerOverFunding: false,
};

const memo: MemoSnapshot = {
  kind: "all_rejected",
  reason: "over_funding",
  solicitationNumber: "CAL-2026-0001",
  fundingCents: 100000000,
  fundingFromEstimate: false,
  alternates: [],
  selectedAlternates: [],
  rows: [],
  expectedWinnerBidId: null,
  winnerOverFunding: false,
};

describe("parseRecap", () => {
  it("accepts a recap", () => {
    expect(parseRecap(recap)).toEqual(recap);
  });

  it("accepts a memo", () => {
    expect(parseRecap(memo)).toEqual(memo);
  });

  it("returns null for a recap missing rows", () => {
    expect(parseRecap({ kind: "recap" })).toBeNull();
  });

  it("returns null for fractional cents or a memo that discloses a bid", () => {
    expect(parseRecap({ ...recap, fundingCents: 1.5 })).toBeNull();
    expect(parseRecap({ ...memo, rows: [row] })).toBeNull();
    expect(parseRecap(null)).toBeNull();
  });
});

describe("parseAward", () => {
  it("accepts an award and rejects a partial one", () => {
    const award = {
      bidId: row.bidId,
      reference: "B-0001",
      bidderName: "Calder Builders",
      amountCents: 110000000,
      selectedAlternates: [1],
      alternates: recap.alternates,
      expectedWinnerBidId: row.bidId,
      differsFromExpected: false,
    };
    expect(parseAward(award)).toEqual(award);
    expect(parseAward({ bidId: row.bidId })).toBeNull();
  });
});

describe("recapColumns", () => {
  it("marks the selected alternates", () => {
    expect(recapColumns(recap)).toEqual(["Alternate 1 (add) (selected)", "Alternate 2 (add)"]);
  });
});

describe("memoText", () => {
  it("states the funding amount for over_funding", () => {
    expect(memoText({ ...memo, fundingCents: 100000000 })).toBe(
      "All bids rejected: every accepted bid exceeds the funding amount of $1,000,000.00.",
    );
  });

  it("states that no bid was accepted", () => {
    expect(memoText({ ...memo, reason: "no_accepted_bids" })).toBe("All bids rejected: no bid was accepted.");
  });
});
