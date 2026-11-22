import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { emptySolicitation } from "../solicitation/schema";
import { LOCKED_FIELDS, lockedFieldChanges } from "./lockedFields";

/** The list app.locked_fields() returns, read from the migration between its marker comments. */
function migrationKeys(): string[] {
  const sql = readFileSync(join(process.cwd(), "supabase/migrations/0027_addenda.sql"), "utf8");
  const block = /locked-fields:start([\s\S]*?)-- locked-fields:end/.exec(sql);
  if (!block) throw new Error("marker comments not found in 0027_addenda.sql");
  return [...block[1].matchAll(/'([A-Za-z]+)'/g)].map((m) => m[1]);
}

describe("LOCKED_FIELDS", () => {
  it("is the fixed list", () => {
    expect([...LOCKED_FIELDS]).toEqual(["releaseDate", "adStart", "adEnd", "newspapers", "category"]);
  });
  it("matches app.locked_fields() in the migration", () => {
    expect(migrationKeys()).toEqual([...LOCKED_FIELDS]);
  });
});

describe("lockedFieldChanges", () => {
  const base = {
    ...emptySolicitation(),
    category: "construction" as const, releaseDate: "2026-08-03", adStart: "2026-08-03", adEnd: "2026-08-17",
    newspapers: "Calder Daily", shortTitle: "Roof", bidDueDate: "2026-08-31",
  };
  it("reports nothing when only unlocked fields change", () => {
    expect(lockedFieldChanges(base, { ...base, shortTitle: "Roof 2", bidDueDate: "2026-09-08" })).toEqual([]);
  });
  it("reports exactly the changed locked keys, in LOCKED_FIELDS order", () => {
    expect(lockedFieldChanges(base, { ...base, newspapers: "Calder Courier", releaseDate: "2026-08-04", shortTitle: "x" }))
      .toEqual(["releaseDate", "newspapers"]);
    expect(lockedFieldChanges(base, { ...base, category: null, adEnd: null }))
      .toEqual(["adEnd", "category"]);
  });
});
