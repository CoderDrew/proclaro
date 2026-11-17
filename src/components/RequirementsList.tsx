import type { deriveRequirements } from "@/domain/solicitation/valueBands";

/** What the estimate triggers (value bands). Shared by the agency form and the office review page. */
export function RequirementsList({ req }: { req: ReturnType<typeof deriveRequirements> | null }) {
  if (req === null) return <p style={{ margin: 0 }}>Enter an estimate to see requirements.</p>;
  return (
    <ul style={{ margin: 0, paddingLeft: 16 }}>
      <li>{req.blocked ? "Blocked: estimate is under $50,000.00" : "Competitive sealed bidding"}</li>
      <li>Prevailing wage: {req.prevailingWage ? "yes" : "no"}</li>
      <li>Bid and performance bonds: {req.bonds ? "yes" : "no"}</li>
      <li>Apprentice credit: {req.apprenticeCredit ? "yes" : "no"}</li>
      <li>Federal domestic-content clauses: {req.federalClauses ? "yes" : "no"}</li>
    </ul>
  );
}
