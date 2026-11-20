import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { emptySolicitation, parseStoredData, solicitationSchema } from "./schema";

/** The key list submit_solicitation checks, read from the migration between its marker comments. */
function migrationKeys(): string[] {
  const sql = readFileSync(join(process.cwd(), "supabase/migrations/0014_funding_amount.sql"), "utf8");
  const block = /required-data-keys:start([\s\S]*?)-- required-data-keys:end/.exec(sql);
  if (!block) throw new Error("marker comments not found in 0014_funding_amount.sql");
  return [...block[1].matchAll(/'([A-Za-z]+)'/g)].map((m) => m[1]);
}

describe("database required keys", () => {
  it("match every top-level key the Zod schema requires", () => {
    const required = Object.entries(solicitationSchema.shape)
      .filter(([, t]) => !t.safeParse(undefined).success)
      .map(([k]) => k);
    expect(migrationKeys().sort()).toEqual(required.sort());
    expect(required.sort()).toEqual(Object.keys(emptySolicitation()).sort());
  });
});

describe("parseStoredData", () => {
  it("returns the merged data when it matches the schema", () => {
    expect(parseStoredData({ shortTitle: "Roof" })?.shortTitle).toBe("Roof");
  });
  it("returns null instead of throwing for invalid data", () => {
    expect(parseStoredData({ releaseDate: "2026-02-30" })).toBeNull();
    expect(parseStoredData({ estimateCents: "lots" })).toBeNull();
    expect(parseStoredData([])).toBeNull();
    expect(parseStoredData(null)).toBeNull();
    expect(parseStoredData("x")).toBeNull();
  });
});
