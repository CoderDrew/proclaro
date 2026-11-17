import { describe, expect, it } from "vitest";
import { emptySolicitation, solicitationSchema } from "./schema";

const parse = (patch: Record<string, unknown>) =>
  solicitationSchema.safeParse({ ...emptySolicitation(), ...patch });

describe("solicitationSchema", () => {
  it("accepts the empty solicitation", () => {
    expect(solicitationSchema.safeParse(emptySolicitation()).success).toBe(true);
  });
  it("has defaults", () => {
    expect(emptySolicitation().bidDueTime).toBe("13:00");
    expect(emptySolicitation().bidValidityDays).toBe(90);
  });
  it("accepts real dates and leap day", () => {
    expect(parse({ releaseDate: "2026-02-28" }).success).toBe(true);
    expect(parse({ releaseDate: "2028-02-29" }).success).toBe(true);
  });
  it("rejects impossible calendar dates", () => {
    expect(parse({ releaseDate: "2026-02-30" }).success).toBe(false);
    expect(parse({ releaseDate: "2026-13-01" }).success).toBe(false);
    expect(parse({ releaseDate: "2027-02-29" }).success).toBe(false);
    expect(parse({ releaseDate: "2026-1-1" }).success).toBe(false);
  });
  it("rejects invalid dates nested in objects", () => {
    expect(parse({ questionsDue: { date: "2026-02-30", time: "10:00" } }).success).toBe(false);
    expect(parse({ attachments: [{ kind: "plans", label: "a", storagePath: "p", issueDate: "2026-04-31" }] }).success).toBe(false);
  });
  it("accepts and rejects times", () => {
    expect(parse({ bidDueTime: "00:00" }).success).toBe(true);
    expect(parse({ bidDueTime: "23:59" }).success).toBe(true);
    expect(parse({ bidDueTime: "25:99" }).success).toBe(false);
    expect(parse({ bidDueTime: "24:00" }).success).toBe(false);
    expect(parse({ bidDueTime: "12:60" }).success).toBe(false);
    expect(parse({ bidDueTime: "9:00" }).success).toBe(false);
    expect(parse({ questionsDue: { date: "2026-03-01", time: "25:99" } }).success).toBe(false);
  });
  it("rejects bad enums and non-integer cents", () => {
    expect(parse({ category: "bogus" }).success).toBe(false);
    expect(parse({ estimateCents: 10.5 }).success).toBe(false);
    expect(parse({ estimateCents: 5_000_000 }).success).toBe(true);
  });
});
