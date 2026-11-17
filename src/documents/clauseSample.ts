import { emptySolicitation } from "../domain/solicitation/schema";
import { clauseVars, type DocContext } from "./clauses";

/**
 * A variable set containing every name a clause may use, derived from clauseVars so it cannot drift from the
 * renderer. Used to dry-run an Admin's clause text: any {{name}} not in this set would fail at publish time.
 */
export function sampleClauseVars(): Record<string, string> {
  const ctx: DocContext = {
    data: emptySolicitation(),
    number: null,
    version: null,
    settings: { stateName: "State", officeName: "Office", timezone: "America/Denver" },
    agencyName: "Agency",
    clauses: {},
  };
  return clauseVars(ctx);
}
