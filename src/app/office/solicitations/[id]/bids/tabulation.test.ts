import { describe, expect, it } from "vitest";
import { bondLabel, bondWithCure, toTabulation, type OpenedBid, type OpenedFile } from "./tabulation";

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

describe("toTabulation electronic bond", () => {
  it("says uploaded only when that bid has a bid_bond file", () => {
    const e = bid({ bid_bond_choice: "electronic", bond_original_received: null });
    const file: OpenedFile = { bid_id: "b1", slot: "bid_bond", path: "p", file_name: "b.pdf", file_status: "ok" };
    expect(toTabulation([e], [], [file]).rows[0].bond).toBe("Electronic bond (uploaded)");
    expect(toTabulation([e], [], []).rows[0].bond).toBe("Electronic bond (not uploaded)");
    expect(toTabulation([e], [], [{ ...file, bid_id: "other" }]).rows[0].bond).toBe("Electronic bond (not uploaded)");
  });
});

describe("bondLabel", () => {
  it("judges the bond by the bidder's choice", () => {
    expect(bondLabel("electronic", null, true)).toBe("Electronic bond (uploaded)");
    expect(bondLabel("electronic", null, false)).toBe("Electronic bond (not uploaded)");
    expect(bondLabel("paper", true, false)).toBe("Paper original mailed: received");
    expect(bondLabel("paper", false, false)).toBe("Paper original mailed: not received");
    expect(bondLabel(null, null, false)).toBe("Not required");
  });
});

describe("bond cure next to the label", () => {
  it("adds the cure status so a bond cured after close does not read as missing", () => {
    const e = bid({ bid_bond_choice: "electronic", bond_original_received: null });
    expect(toTabulation([e], [], [], { b1: "cured" }).rows[0].bond).toBe("Electronic bond (not uploaded); cured after close");
    expect(toTabulation([e], [], [], { b1: "pending" }).rows[0].bond).toBe("Electronic bond (not uploaded); cure pending");
    expect(toTabulation([e], [], [], { b1: "failed" }).rows[0].bond)
      .toBe("Electronic bond (not uploaded); not received by the cure deadline");
    expect(toTabulation([e], [], [], { other: "cured" }).rows[0].bond).toBe("Electronic bond (not uploaded)");
  });

  it("leaves the label alone when no cure was due", () => {
    expect(bondWithCure("Not required", "not_required")).toBe("Not required");
    expect(bondWithCure("Electronic bond (uploaded)", "ok")).toBe("Electronic bond (uploaded)");
    expect(bondWithCure("Electronic bond (uploaded)", undefined)).toBe("Electronic bond (uploaded)");
  });
});
