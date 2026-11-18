import { deriveRequirements } from "../../domain/solicitation/valueBands";
import type { BidFill } from "../bidFill";
import type { DocContext } from "../clauses";
import { BidFormPages } from "./BidFormSections";
import { Shell } from "./Layout";

export function BidForm({ ctx, draft, fill }: { ctx: DocContext; draft: boolean; fill?: BidFill }) {
  const { data } = ctx;
  const req = deriveRequirements(data.estimateCents ?? 0, data.federalFunds === true, data.optionalSections);
  return (
    <Shell title={`Bid Form ${draft ? "(draft)" : ctx.number ?? ""}`.trim()} draft={draft}>
      <BidFormPages fill={fill} ctx={ctx} req={req} footer={{ draft, number: ctx.number, version: ctx.version }} />
    </Shell>
  );
}
