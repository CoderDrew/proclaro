import { describe, it, expect } from "vitest";
import { toUtc, todayIn, addDays, diffDays, isWeekend, isNonWorkingDay, fiscalYearOf } from "./time";

describe("time", () => {
  it("toUtc handles DST", () => {
    expect(toUtc("2026-11-01", "13:00", "America/Denver").toISOString()).toBe("2026-11-01T20:00:00.000Z");
    expect(toUtc("2026-07-15", "13:00", "America/Denver").toISOString()).toBe("2026-07-15T19:00:00.000Z");
  });
  it("todayIn uses the zone", () => {
    expect(todayIn("America/Denver", new Date("2026-11-17T01:30:00Z"))).toBe("2026-11-16");
  });
  it("calendar arithmetic", () => {
    expect(diffDays("2026-09-14", "2026-09-04")).toBe(10);
    expect(diffDays("2026-09-04", "2026-09-14")).toBe(-10);
    expect(diffDays("2026-11-02", "2026-10-31")).toBe(2);
    expect(addDays("2026-02-27", 2)).toBe("2026-03-01");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
  });
  it("weekend and non-working", () => {
    expect(isWeekend("2026-11-21")).toBe(true);
    expect(isWeekend("2026-11-20")).toBe(false);
    expect(isNonWorkingDay("2026-11-26", ["2026-11-26"])).toBe(true);
    expect(isNonWorkingDay("2026-11-22", [])).toBe(true);
    expect(isNonWorkingDay("2026-11-25", [])).toBe(false);
  });
  it("fiscal year", () => {
    expect(fiscalYearOf("2026-06-30", 7)).toBe(2026);
    expect(fiscalYearOf("2026-07-01", 7)).toBe(2027);
    expect(fiscalYearOf("2026-12-31", 1)).toBe(2026);
  });
});
