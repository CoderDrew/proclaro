import { deriveRequirements } from "../../domain/solicitation/valueBands";
import type { DocContext } from "../clauses";
import { BidFormPages } from "./BidFormSections";
import { Shell } from "./Layout";
import {
  AttachmentsSection, Cover, EvaluationSection, KeyDatesSection, NoticeSection, OptionalSections,
  SECTION_LABELS, SpecialProvisionsSection, SpecsPlansSection, SubmissionSection, Toc,
} from "./RfbSections";

export function RfbDocument({ ctx, draft }: { ctx: DocContext; draft: boolean }) {
  const { data } = ctx;
  const req = deriveRequirements(data.estimateCents ?? 0, data.federalFunds === true, data.optionalSections);
  const toc = [
    { id: "notice", title: "Notice" },
    { id: "special-provisions", title: "Special Provisions" },
    { id: "key-dates", title: "Key Dates" },
    { id: "specs-plans", title: "Specifications and Plans" },
    { id: "submission", title: "Submission of Bids" },
    { id: "evaluation", title: "Evaluation and Award" },
    { id: "bid-form", title: "Bid Form" },
    ...data.optionalSections.map((s) => ({ id: `optional-${s}`, title: SECTION_LABELS[s] })),
    { id: "attachments", title: "List of Attached Documents" },
  ];
  return (
    <Shell title={`Request for Bids ${draft ? "(draft)" : ctx.number ?? ""}`.trim()} draft={draft}>
      <Cover ctx={ctx} draft={draft} />
      <Toc entries={toc} />
      <NoticeSection ctx={ctx} />
      <SpecialProvisionsSection ctx={ctx} req={req} />
      <KeyDatesSection ctx={ctx} />
      <SpecsPlansSection ctx={ctx} />
      <SubmissionSection ctx={ctx} req={req} />
      <EvaluationSection ctx={ctx} req={req} />
      <div id="bid-form">
        <BidFormPages ctx={ctx} req={req} footer={null} />
      </div>
      <OptionalSections data={data} />
      <AttachmentsSection data={data} />
    </Shell>
  );
}
