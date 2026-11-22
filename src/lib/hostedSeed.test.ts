import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { hostedSeed } from "../../scripts/hosted-reset.mjs";

describe("hostedSeed", () => {
  const seed = readFileSync("supabase/seed.sql", "utf8");

  it("replaces every seeded password and leaves no trace of the local one", () => {
    const out: string = hostedSeed(seed, "it's-demo");
    expect(out).not.toContain("'proclaro-dev'");
    expect(out.match(/crypt\('it''s-demo'/g)?.length).toBe(seed.match(/crypt\('proclaro-dev'/g)?.length);
  });

  it("refuses the local password as the demo password", () => {
    expect(() => hostedSeed(seed, "proclaro-dev")).toThrow(/local password/);
  });
});
