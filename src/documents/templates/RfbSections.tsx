import type { BidSection, Requirements, SolicitationData } from "../../domain/solicitation/types";
import type { DocContext } from "../clauses";
import { formatDate, formatDateTime, formatTimeWithZone, TBD } from "../format";
import { Clause, FreeText } from "./Layout";

export const SECTION_LABELS: Record<BidSection, string> = {
  bid_form_1: "Bid Form Section 1",
  bid_form_2: "Bid Form Section 2",
  signature_page: "Signature Page",
  insurance: "Proof of Insurance",
  qualifications: "Statement of Qualifications",
  references: "References",
  current_work: "Current Work",
};

const FORMAT_LABELS = { in_person: "In person", phone: "By phone", video: "By video" } as const;

function dueText(ctx: DocContext): string {
  const { data, settings } = ctx;
  if (!data.bidDueDate) return TBD;
  return `${formatDate(data.bidDueDate)}, ${formatTimeWithZone(data.bidDueDate, data.bidDueTime, settings.timezone)}`;
}

export function Cover({ ctx, draft }: { ctx: DocContext; draft: boolean }) {
  const { data } = ctx;
  const place = [data.location.address, data.location.city, data.location.county].filter(Boolean).join(", ");
  return (
    <section className="cover" id="cover">
      <p className="muted">{ctx.settings.stateName}</p>
      <p>{ctx.settings.officeName}</p>
      <h1>Request for Bids</h1>
      <h2 style={{ border: 0 }}>{data.longTitle || data.shortTitle}</h2>
      <div className="meta">
        <p>{ctx.agencyName}</p>
        {place ? <p>{place}</p> : null}
        {draft ? <p>Draft: number and version not yet assigned</p> : <p>Solicitation {ctx.number} · Version {ctx.version}</p>}
        <p>Bids due {dueText(ctx)}</p>
      </div>
    </section>
  );
}

export function Toc({ entries }: { entries: { id: string; title: string }[] }) {
  return (
    <section className="major" id="toc">
      <h2>Table of Contents</h2>
      <ol className="toc">
        {entries.map((e) => <li key={e.id}><a href={`#${e.id}`}>{e.title}</a></li>)}
      </ol>
    </section>
  );
}

export function NoticeSection({ ctx }: { ctx: DocContext }) {
  const { data } = ctx;
  return (
    <section className="major" id="notice">
      <h2>Notice</h2>
      <Clause ctx={ctx} k="notice" />
      {data.summary ? <><h3>Summary</h3><FreeText text={data.summary} /></> : null}
      {data.preBid.kind !== "none" ? (
        <>
          <Clause ctx={ctx} k="prebid_meeting" />
          <table data-prebid-details>
            <tbody>
              <tr><th>Attendance</th><td>{data.preBid.kind === "mandatory" ? "Required" : "Optional"}</td></tr>
              <tr><th>Format</th><td>{data.preBid.format ? FORMAT_LABELS[data.preBid.format] : TBD}</td></tr>
              <tr>
                <th>Date and time</th>
                <td>{data.preBid.date && data.preBid.time ? formatDateTime({ date: data.preBid.date, time: data.preBid.time }, ctx.settings.timezone) : TBD}</td>
              </tr>
              <tr><th>Location or connection details</th><td>{data.preBid.location || TBD}</td></tr>
            </tbody>
          </table>
        </>
      ) : null}
      {data.backgroundCheck.required ? (
        <>
          <Clause ctx={ctx} k="background_check" />
          <table data-background-details>
            <tbody>
              <tr><th>Contact</th><td>{data.backgroundCheck.contact || TBD}</td></tr>
              <tr><th>Lead time</th><td>{data.backgroundCheck.leadDays === null ? TBD : `${data.backgroundCheck.leadDays} days`}</td></tr>
            </tbody>
          </table>
        </>
      ) : null}
    </section>
  );
}

export function SpecialProvisionsSection({ ctx, req }: { ctx: DocContext; req: Requirements }) {
  const { data } = ctx;
  return (
    <section className="major" id="special-provisions">
      <h2>Special Provisions</h2>
      {data.specialProvisions ? <FreeText text={data.specialProvisions} /> : null}
      <Clause ctx={ctx} k="insurance" />
      <Clause ctx={ctx} k="warranty" />
      {req.prevailingWage ? <Clause ctx={ctx} k="prevailing_wage" /> : null}
      {req.federalClauses ? <Clause ctx={ctx} k="federal_domestic_content" /> : null}
      {req.bonds ? <Clause ctx={ctx} k="performance_bond" /> : null}
      {req.apprenticeCredit ? <Clause ctx={ctx} k="apprentice_credit" /> : null}
    </section>
  );
}

export function KeyDatesSection({ ctx }: { ctx: DocContext }) {
  const { data, settings } = ctx;
  const rows: [string, string][] = [
    ["Release date", formatDate(data.releaseDate)],
    ["Questions due", formatDateTime(data.questionsDue, settings.timezone)],
    ["Answers issued by", formatDateTime(data.answersDue, settings.timezone)],
    ["Bids due", dueText(ctx)],
  ];
  if (data.tentativeAwardDate) rows.push(["Tentative award", formatDate(data.tentativeAwardDate)]);
  if (data.estimatedStartDate) rows.push(["Estimated start", formatDate(data.estimatedStartDate)]);
  if (data.estimatedCompletionDate) rows.push(["Estimated completion", formatDate(data.estimatedCompletionDate)]);
  return (
    <section className="major" id="key-dates">
      <h2>Key Dates</h2>
      <table data-key-dates>
        <tbody>{rows.map(([k, v]) => <tr key={k}><th>{k}</th><td>{v}</td></tr>)}</tbody>
      </table>
      <p className="muted">All times are in the {settings.timezone} time zone.</p>
    </section>
  );
}

export function SpecsPlansSection({ ctx }: { ctx: DocContext }) {
  const { data } = ctx;
  return (
    <section className="major" id="specs-plans">
      <h2>Specifications and Plans</h2>
      {data.projectDescription ? <><h3>Project description</h3><FreeText text={data.projectDescription} /></> : null}
      {data.scopeNotes ? <><h3>Scope notes</h3><FreeText text={data.scopeNotes} /></> : null}
      <Clause ctx={ctx} k="addenda" />
      <Clause ctx={ctx} k="substitutions" />
    </section>
  );
}

export function SubmissionSection({ ctx, req }: { ctx: DocContext; req: Requirements }) {
  return (
    <section className="major" id="submission">
      <h2>Submission of Bids</h2>
      <Clause ctx={ctx} k="submission" />
      {req.bonds ? <Clause ctx={ctx} k="bid_deposit" /> : null}
      <Clause ctx={ctx} k="modification_withdrawal" />
      <Clause ctx={ctx} k="questions" />
      <Clause ctx={ctx} k="communication_restrictions" />
    </section>
  );
}

export function EvaluationSection({ ctx, req }: { ctx: DocContext; req: Requirements }) {
  const limits = ctx.data.pageLimits;
  return (
    <section className="major" id="evaluation">
      <h2>Evaluation and Award</h2>
      <Clause ctx={ctx} k="evaluation_award" />
      <table data-checklist>
        <thead><tr><th>Required item</th><th>Page limit</th><th>Result</th></tr></thead>
        <tbody>
          {req.requiredSections.map((s) => {
            const limit = limits[s];
            return (
              <tr key={s} data-checklist-row={s}>
                <td>{SECTION_LABELS[s]}</td>
                <td>{limit ? `${limit} ${limit === 1 ? "page" : "pages"}` : "None"}</td>
                <td>MET / NOT MET</td>
              </tr>
            );
          })}
        </tbody>
      </table>
      <Clause ctx={ctx} k="award_contract" />
      <Clause ctx={ctx} k="resident_preference" />
      <Clause ctx={ctx} k="registrations" />
      <Clause ctx={ctx} k="reservation_of_rights" />
    </section>
  );
}

const OPTIONAL_BLURBS = {
  qualifications: "Describe your firm's experience and the people who would manage and carry out this work.",
  references: "List recent clients we may contact about comparable work.",
  current_work: "List the projects your firm is working on now, with their size and expected completion dates.",
} as const;

export function OptionalSections({ data }: { data: SolicitationData }) {
  const limits = data.pageLimits;
  return (
    <>
      {data.optionalSections.map((s) => (
        <section className="major" id={`optional-${s}`} key={s} data-optional-section={s}>
          <h2>{SECTION_LABELS[s]}</h2>
          <p>{OPTIONAL_BLURBS[s]}</p>
          {limits[s] ? <p>Limit: {limits[s]} {limits[s] === 1 ? "page" : "pages"}.</p> : null}
        </section>
      ))}
    </>
  );
}

const KIND_LABELS = {
  plans: "Plans", specifications: "Specifications", sample_contract: "Sample contract",
  prevailing_wage: "Prevailing wage rates", other: "Other document",
} as const;

export function AttachmentsSection({ data }: { data: SolicitationData }) {
  return (
    <section className="major" id="attachments">
      <h2>List of Attached Documents</h2>
      {data.attachments.length === 0 ? <p>No documents are attached.</p> : (
        <table data-attachments>
          <thead><tr><th>Type</th><th>Document</th><th>Issue date</th></tr></thead>
          <tbody>
            {data.attachments.map((a, i) => (
              <tr key={i}><td>{KIND_LABELS[a.kind]}</td><td>{a.label}</td><td>{a.issueDate ? formatDate(a.issueDate) : "—"}</td></tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}
