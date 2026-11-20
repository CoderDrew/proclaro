import type { SolicitationData } from "@/domain/solicitation/types";

export interface FieldComment { field: string | null; body: string }

/**
 * Field paths that have a visible place for their comments in the form right now.
 * Conditional inputs count only while shown; unknown paths are not listed, so they fall back to the sidebar.
 */
export function renderedFieldPaths(d: SolicitationData): Set<string> {
  const s = new Set<string>([
    "shortTitle", "longTitle", "category", "summary", "projectDescription",
    "location.address", "location.city", "location.county",
    "requester.name", "requester.email", "requester.phone",
    "projectManager.name", "projectManager.email", "projectManager.phone",
    "estimateCents", "fundingAmountCents", "fundingSource", "federalFunds",
    "releaseDate", "adStart", "adEnd", "newspapers", "questionsDue", "answersDue",
    "bidDueDate", "bidDueTime", "bidValidityDays",
    "tentativeAwardDate", "estimatedStartDate", "estimatedCompletionDate",
    "preBid.kind", "scopeNotes", "specialProvisions",
    "schedule.items",
    "attachments.plans", "attachments.specifications", "attachments.sample_contract", "attachments.prevailing_wage",
  ]);
  if (d.fundingSource === "other") s.add("fundingOther");
  if (d.preBid.kind !== "none") for (const k of ["format", "date", "time", "location"]) s.add(`preBid.${k}`);
  if (d.backgroundCheck.required) for (const k of ["contact", "leadDays"]) s.add(`backgroundCheck.${k}`);
  d.schedule.items.forEach((_, i) => s.add(`schedule.items.${i}.name`));
  return s;
}

/** Comments for the sidebar: general ones, plus any whose field is not currently rendered in the form. */
export function sidebarComments<T extends FieldComment>(comments: T[], d: SolicitationData): T[] {
  const shown = renderedFieldPaths(d);
  return comments.filter((c) => !c.field || !shown.has(c.field));
}
