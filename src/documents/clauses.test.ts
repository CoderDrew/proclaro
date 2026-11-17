import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { CLAUSE_KEYS } from "./clauseKeys";
import { clauseBlocks, clauseVars, renderClause } from "./clauses";
import { ctxWith, loadSeedClauses } from "./testFixtures";

describe("renderClause", () => {
  it("replaces variables", () => {
    expect(renderClause("Due {{bidDue}}", { bidDue: "Aug 31" })).toBe("Due Aug 31");
  });
  it("throws for an unknown variable", () => {
    expect(() => renderClause("{{nope}}", {})).toThrow("UnknownClauseVariable");
  });
  it("escapes values", () => {
    expect(renderClause("{{x}}", { x: "<b>&" })).toBe("&lt;b&gt;&amp;");
  });
});

describe("clauseBlocks", () => {
  it("splits paragraphs, finds headings, keeps values as plain text", () => {
    const blocks = clauseBlocks("# Title\n\nOne {{x}}\n\nTwo", { x: "<b>" });
    expect(blocks).toEqual([
      { kind: "heading", text: "Title" },
      { kind: "paragraph", text: "One <b>" },
      { kind: "paragraph", text: "Two" },
    ]);
  });
});

describe("seeded clause text", () => {
  const seeded = loadSeedClauses();
  it("seeds version 1 of exactly the CLAUSE_KEYS", () => {
    expect(Object.keys(seeded).sort()).toEqual([...CLAUSE_KEYS].sort());
    const sql = readFileSync(join(__dirname, "../../supabase/migrations/0003_clauses_seed.sql"), "utf8");
    expect((sql.match(/, 1, \$clause\$/g) ?? []).length).toBe(CLAUSE_KEYS.length);
  });
  it("uses only variables the templates provide", () => {
    const vars = clauseVars(ctxWith(16_000_000));
    for (const key of CLAUSE_KEYS) expect(() => clauseBlocks(seeded[key], vars), key).not.toThrow();
  });
  it("contains no statute citations", () => {
    for (const [key, body] of Object.entries(seeded)) expect(body, key).not.toMatch(/§|\b\d+-\d+-\d+\b/);
  });
});
