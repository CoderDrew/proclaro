import { readFileSync } from "node:fs";
import { join } from "node:path";
import { emptySolicitation } from "../domain/solicitation/schema";
import type { SolicitationData } from "../domain/solicitation/types";
import type { DocContext } from "./clauses";

/** Reads the clause bodies straight out of the seed migration, so tests render the real text. */
export function loadSeedClauses(): Record<string, string> {
  const sql = readFileSync(join(__dirname, "../../supabase/migrations/0003_clauses_seed.sql"), "utf8");
  const out: Record<string, string> = {};
  for (const m of sql.matchAll(/\('([a-z_]+)', 1, \$clause\$([\s\S]*?)\$clause\$/g)) out[m[1]] = m[2];
  return out;
}

export function ctxWith(
  estimateCents: number,
  extra: Partial<SolicitationData> = {},
  over: Partial<DocContext> = {},
): DocContext {
  const data: SolicitationData = {
    ...emptySolicitation(),
    shortTitle: "Roof Repair",
    longTitle: "Dormitory Roof Repair",
    category: "construction",
    summary: "Replace roofs.",
    projectDescription: "Replace the roofs on two dormitories.",
    location: { address: "1 Main St", city: "Calder City", county: "Calder County" },
    requester: { name: "Pat Example", email: "pat@example.test", phone: "555-0100" },
    projectManager: { name: "Sam Example", email: "sam@example.test", phone: "555-0101" },
    estimateCents,
    fundingAmountCents: estimateCents,
    fundingSource: "major_maintenance",
    federalFunds: false,
    releaseDate: "2027-06-01",
    questionsDue: { date: "2027-06-15", time: "13:00" },
    answersDue: { date: "2027-06-22", time: "13:00" },
    bidDueDate: "2027-07-01",
    bidDueTime: "13:00",
    schedule: { items: [{ name: "Base work", description: "" }], alternates: [] },
    attachments: [
      { kind: "plans", label: "Roof plans", storagePath: "p.pdf", issueDate: "2027-05-20" },
      { kind: "specifications", label: "Project manual", storagePath: "s.pdf", issueDate: "2027-05-20" },
    ],
    ...extra,
  };
  return {
    data,
    number: "27-0001",
    version: 1,
    settings: { stateName: "State of Calder", officeName: "Calder State Construction Office", timezone: "America/Denver" },
    agencyName: "Calder Department of Example",
    clauses: loadSeedClauses(),
    ...over,
  };
}
