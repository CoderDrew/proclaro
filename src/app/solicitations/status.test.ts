import { describe, expect, it } from "vitest";
import { bidStatus, formatInstant, onlyPublic, postedOutcomeLabel } from "./status";

describe("bidStatus", () => {
  const due = "2026-08-31T19:00:00Z";
  it("is Open before the bid due instant", () => {
    expect(bidStatus(due, new Date("2026-08-31T18:59:59Z"))).toBe("Open");
  });
  it("is Closed at and after the bid due instant", () => {
    expect(bidStatus(due, new Date("2026-08-31T19:00:00Z"))).toBe("Closed");
    expect(bidStatus(due, new Date("2026-09-01T00:00:00Z"))).toBe("Closed");
  });
  it("is Closed when there is no due instant", () => {
    expect(bidStatus(null, new Date())).toBe("Closed");
  });
});

describe("formatInstant", () => {
  it("shows the configured zone, not the server zone", () => {
    expect(formatInstant("2026-08-31T19:00:00Z", "America/Denver")).toBe("Aug 31, 2026, 1:00 PM MDT");
    expect(formatInstant("2026-12-15T20:00:00Z", "America/Denver")).toBe("Dec 15, 2026, 1:00 PM MST");
  });
});

describe("onlyPublic", () => {
  it("filters on published state and release date on or before today", () => {
    const calls: [string, string, string][] = [];
    const q = {
      eq(c: "state", v: "published") { calls.push(["eq", c, v]); return q; },
      lte(c: "release_date", v: string) { calls.push(["lte", c, v]); return q; },
    };
    expect(onlyPublic(q, "2026-11-17")).toBe(q);
    expect(calls).toEqual([["eq", "state", "published"], ["lte", "release_date", "2026-11-17"]]);
  });
});

describe("postedOutcomeLabel", () => {
  it("maps the posted statuses", () => {
    expect(postedOutcomeLabel("accepted")).toBe("Accepted");
    expect(postedOutcomeLabel("flag_accepted")).toBe("Accepted");
    expect(postedOutcomeLabel("non_responsive")).toBe("Non-responsive");
    expect(postedOutcomeLabel("flag_rejected")).toBe("Rejected by the agency");
  });
  it("returns an unknown value as it is", () => {
    expect(postedOutcomeLabel("something_else")).toBe("something_else");
  });
  it("never says Accepted under the all-rejected memo", () => {
    expect(postedOutcomeLabel("accepted", true)).toBe("All bids rejected");
    expect(postedOutcomeLabel("flag_accepted", true)).toBe("All bids rejected");
    expect(postedOutcomeLabel("non_responsive", true)).toBe("Non-responsive");
    expect(postedOutcomeLabel("flag_rejected", true)).toBe("Rejected by the agency");
  });
});
