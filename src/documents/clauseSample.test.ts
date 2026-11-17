import { describe, expect, it } from "vitest";
import { CLAUSE_VARIABLES } from "./clauseKeys";
import { sampleClauseVars } from "./clauseSample";
import { renderClause } from "./clauses";
import { loadSeedClauses } from "./testFixtures";

describe("sampleClauseVars", () => {
  it("has exactly the documented clause variables", () => {
    expect(Object.keys(sampleClauseVars()).sort()).toEqual([...CLAUSE_VARIABLES].sort());
  });

  it("renders every seeded clause", () => {
    for (const [key, body] of Object.entries(loadSeedClauses())) {
      expect(() => renderClause(body, sampleClauseVars()), key).not.toThrow();
    }
  });
});
