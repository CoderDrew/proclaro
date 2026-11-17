import { deriveRequirements } from "../../domain/solicitation/valueBands";
import type { DocContext } from "../clauses";
import { BidFormPages } from "./BidFormSections";
import { Shell } from "./Layout";

export function BidForm({ ctx, draft }: { ctx: DocContext; draft: boolean }) {
  const { data } = ctx;
  const req = deriveRequirements(data.estimateCents ?? 0, data.federalFunds === true, data.optionalSections);
  return (
    <Shell title={`Bid Form ${draft ? "(draft)" : ctx.number ?? ""}`.trim()} draft={draft}>
      <BidFormPages ctx={ctx} req={req} footer={{ draft, number: ctx.number, version: ctx.version }} />
    </Shell>
  );
}
