import { describe, expect, it } from "vitest";
import { bondLabel, toTabulation, type OpenedBid, type OpenedFile } from "./tabulation";

const REASON = "signed original not received by the bid due time";

function bid(over: Partial<OpenedBid>): OpenedBid {
  return {
    bid_id: "b1", reference: "K7QM-2XVD", version: 2, submitted_at: "2026-11-17T20:00:00Z",
    bidder_org_id: "o1", bidder_name: "Ridgeback Builders LLC",
    item_cents: [12500000, 234500], alternate_cents: [1500000], base_total_cents: 12734500,
    bid_bond_choice: "paper", original_received: true, non_responsive_reason: null, bond_original_received: true,
    ...over,
  };
}

describe("toTabulation", () => {
  it("formats stored cents, labels alternates and passes the reason through verbatim", () => {
    const t = toTabulation(
      [bid({ base_total_cents: 12734567, item_cents: [12500000, 234567], original_received: false, non_responsive_reason: REASON })],
      [{ kind: "deductive", description: "Omit canopy" }],
    );
    expect(t.headers).toEqual(["Alternate 1 (deduct)"]);
    expect(t.rows[0].baseTotal).toBe("$127,345.67");
    expect(t.rows[0].alternates).toEqual(["$15,000.00"]);
    expect(t.rows[0].reason).toBe(REASON);
    expect(t.rows[0].originalReceived).toBe(false);
    expect(t.rows[0]).toMatchObject({ reference: "K7QM-2XVD", bidderName: "Ridgeback Builders LLC", version: 2 });
  });

  it("labels additive alternates and keeps database order", () => {
    const t = toTabulation(
      [bid({ bid_id: "x", reference: "AAAA-AAAA", base_total_cents: 100, alternate_cents: [5, 0] }),
       bid({ bid_id: "y", reference: "BBBB-BBBB", base_total_cents: 50, alternate_cents: [7, 8] })],
      [{ kind: "additive", description: "Gate" }, { kind: "deductive", description: "Canopy" }],
    );
    expect(t.headers).toEqual(["Alternate 1 (add)", "Alternate 2 (deduct)"]);
    expect(t.rows.map((r) => r.reference)).toEqual(["AAAA-AAAA", "BBBB-BBBB"]);
    expect(t.rows[1].alternates).toEqual(["$0.07", "$0.08"]);
    expect(t.rows[0].reason).toBeNull();
  });

  it("uses the stored base total, never a recomputed one", () => {
    const t = toTabulation([bid({ item_cents: [1, 2], base_total_cents: 3 })], []);
    expect(t.rows[0].baseTotal).toBe("$0.03");
    expect(t.headers).toEqual([]);
  });

  it("collects tamper flags per bid", () => {
    const files: OpenedFile[] = [
      { bid_id: "b1", slot: "insurance", path: "p1", file_name: "ins.pdf", file_status: "changed" },
      { bid_id: "b1", slot: "references", path: "p2", file_name: "ref.pdf", file_status: "missing" },
      { bid_id: "b1", slot: "bid_bond", path: "p3", file_name: "bond.pdf", file_status: "ok" },
      { bid_id: "other", slot: "insurance", path: "p4", file_name: "x.pdf", file_status: "missing" },
    ];
    const t = toTabulation([bid({})], [], files);
    expect(t.rows[0].fileFlags).toEqual(["Proof of Insurance: changed", "References: missing"]);
    expect(toTabulation([bid({})], []).rows[0].fileFlags).toEqual([]);
  });
});

describe("bondLabel", () => {
  it("judges the bond by the bidder's choice", () => {
    expect(bondLabel("electronic", null)).toBe("Electronic bond (uploaded)");
    expect(bondLabel("paper", true)).toBe("Paper original mailed: received");
    expect(bondLabel("paper", false)).toBe("Paper original mailed: not received");
    expect(bondLabel(null, null)).toBe("Not required");
  });
});
