"use client";

import { createContext, useContext, useState, type ReactNode } from "react";
import { formatMoney, parseMoney } from "@/domain/money";
import type { BidSection, SolicitationData } from "@/domain/solicitation/types";
import type { Issue } from "@/domain/solicitation/validate";
import type { deriveRequirements } from "@/domain/solicitation/valueBands";
import { AttachmentUploader } from "@/components/AttachmentUploader";
import { IssueList } from "@/components/IssueList";
import { Choice, Field as UiField } from "@/components/ui";

export interface ReturnComment { field: string | null; body: string }

const SECTION_LABELS: Record<BidSection, string> = {
  bid_form_1: "Bid form section 1", bid_form_2: "Bid form section 2", signature_page: "Signature page",
  insurance: "Proof of insurance", qualifications: "Qualifications", references: "References",
  current_work: "Current work",
};
const OPTIONAL_SECTIONS = ["qualifications", "references", "current_work"] as const;

export function getPath(obj: unknown, path: string): unknown {
  return path.split(".").reduce<unknown>((o, k) => (o == null ? o : (o as Record<string, unknown>)[k]), obj);
}
export function setPath(data: SolicitationData, path: string, value: unknown): SolicitationData {
  const next = structuredClone(data) as unknown as Record<string, unknown>;
  const keys = path.split(".");
  let cur = next;
  for (const k of keys.slice(0, -1)) cur = cur[k] as Record<string, unknown>;
  cur[keys[keys.length - 1]] = value;
  return next as unknown as SolicitationData;
}

/** Everything a field needs to show its own errors, warnings and office comments. */
interface FieldCtxValue {
  errors: Issue[]; warnings: Issue[]; acked: ReadonlySet<string>;
  onAck: (i: Issue) => void; editable: boolean; comments: ReturnComment[];
}
const FieldCtx = createContext<FieldCtxValue | null>(null);

// A real top-level component (not defined inside the form) so inputs keep focus across renders.
function Field({ label, field, wide, labelId, hint, children }: { label: string; field?: string; wide?: boolean; labelId?: string; hint?: string; children: ReactNode }) {
  const c = useContext(FieldCtx)!;
  return (
    <div className={wide ? "sol-cell sol-cell--wide" : "sol-cell"}>
      <UiField label={label} labelId={labelId} hint={hint}>{children}</UiField>
      {field && (
        <>
          <IssueList issues={c.errors.filter((i) => i.field === field)} kind="error" />
          <IssueList
            issues={c.warnings.filter((i) => i.field === field)} kind="warning"
            acked={c.acked} onAck={c.onAck} disabled={!c.editable}
          />
          <FieldComments field={field} />
        </>
      )}
    </div>
  );
}

/** Office comments attached to one field path. */
function FieldComments({ field }: { field: string }) {
  const c = useContext(FieldCtx)!;
  return (
    <>
      {c.comments.filter((m) => m.field === field).map((m, i) => (
        <div key={i} className="field-comment">Office comment: {m.body}</div>
      ))}
    </>
  );
}

function MoneyInput({
  cents, onChange, ...aria
}: {
  cents: number | null; onChange: (c: number | null) => void;
  id?: string; "aria-describedby"?: string; "aria-invalid"?: boolean;
}) {
  const [text, setText] = useState(cents === null ? "" : formatMoney(cents));
  const bad = text.trim() !== "" && parseMoney(text) === null;
  return (
    <>
      <input
        {...aria} inputMode="decimal" value={text} placeholder="$0.00"
        onChange={(e) => { setText(e.target.value); onChange(parseMoney(e.target.value)); }}
      />
      {bad && <span className="ui-field-error">Enter an amount like $150,000.00.</span>}
    </>
  );
}

export interface FieldsProps {
  data: SolicitationData;
  /** The newest data, read when a handler must not use a stale render (e.g. several changes in one tick). */
  getLatest: () => SolicitationData;
  onChange: (next: SolicitationData) => void;
  editable: boolean;
  errors: Issue[];
  warnings: Issue[];
  acked: ReadonlySet<string>;
  onAck: (i: Issue) => void;
  comments: ReturnComment[];
  req: ReturnType<typeof deriveRequirements> | null;
  uploads: {
    createUploadUrl: (name: string) => Promise<{ path: string; token: string }>;
    onUploaded: (added: SolicitationData["attachments"][number]) => void;
  };
  /** Top-level data keys shown read-only (an addendum's locked fields). */
  locked?: ReadonlySet<string>;
}

const LOCKED_HINT = "Can't change in an addendum.";

/** The solicitation field groups. Controlled and shared by the agency form and the office review page. */
export function SolicitationFields({
  data, getLatest, onChange, editable, errors, warnings, acked, onAck, comments, req, uploads, locked,
}: FieldsProps) {
  const isLocked = (path: string) => locked?.has(path) ?? false;
  const lockHint = (path: string) => (isLocked(path) ? LOCKED_HINT : undefined);
  const fieldCtx: FieldCtxValue = { errors, warnings, acked, onAck, editable, comments };
  const set = (path: string, value: unknown) => onChange(setPath(getLatest(), path, value));
  const val = (path: string) => getPath(data, path);

  const text = (label: string, path: string, type = "text") => (
    <Field label={label} field={path} hint={lockHint(path)}>
      <input type={type} value={String(val(path) ?? "")} disabled={isLocked(path)} onChange={(e) => set(path, e.target.value)} />
    </Field>
  );
  const area = (label: string, path: string) => (
    <Field label={label} field={path} wide>
      <textarea value={String(val(path) ?? "")} onChange={(e) => set(path, e.target.value)} />
    </Field>
  );
  const dateField = (label: string, path: string) => (
    <Field label={label} field={path} hint={lockHint(path)}>
      <input type="date" value={String(val(path) ?? "")} disabled={isLocked(path)} onChange={(e) => set(path, e.target.value || null)} />
    </Field>
  );
  const dateTimeField = (label: string, path: "questionsDue" | "answersDue") => {
    const v = data[path];
    const labelId = `${path}-label`;
    return (
      <Field label={label} field={path} labelId={labelId}>
        <span className="row" role="group" aria-labelledby={labelId}>
          <input
            type="date" aria-label={`${label} date`} value={v?.date ?? ""}
            onChange={(e) => set(path, e.target.value ? { date: e.target.value, time: v?.time ?? "13:00" } : null)}
          />
          <input
            type="time" aria-label={`${label} time`} value={v?.time ?? ""} disabled={!v}
            onChange={(e) => v && e.target.value && set(path, { date: v.date, time: e.target.value })}
          />
        </span>
      </Field>
    );
  };
  const contact = (title: string, who: "requester" | "projectManager") => (
    <>
      <h4 className="sol-cell--wide sol-subhead">{title}</h4>
      {text(`${title} name`, `${who}.name`)}
      {text(`${title} email`, `${who}.email`, "email")}
      {text(`${title} phone`, `${who}.phone`, "tel")}
    </>
  );

  const requiredSections = req?.requiredSections
    ?? (["bid_form_1", "bid_form_2", "signature_page", "insurance", ...data.optionalSections] as BidSection[]);

  const attachmentKinds = [
    { kind: "plans", title: "Plans", issue: true },
    { kind: "specifications", title: "Project manual / specifications", issue: true },
    { kind: "sample_contract", title: "Sample contract", issue: false },
    { kind: "prevailing_wage", title: `Prevailing wage rates${req?.prevailingWage ? " (required)" : ""}`, issue: false },
    { kind: "other", title: "Additional documents", issue: false },
  ] as const;


  return (
    <FieldCtx.Provider value={fieldCtx}>
        <form className="sol-form" onSubmit={(e) => e.preventDefault()}>
          <fieldset disabled={!editable} className="ui-fieldset-reset">
            <fieldset>
              <legend>Identity</legend>
              <div className="ui-field-grid ui-field-grid--auto">
                {text("Short title (30 characters max)", "shortTitle")}
                {text("Long title", "longTitle")}
                <Field label="Category" field="category" hint={lockHint("category")}>
                  <select value={data.category ?? ""} disabled={isLocked("category")} onChange={(e) => set("category", e.target.value || null)}>
                    <option value="">Select...</option>
                    <option value="construction">Construction</option>
                    <option value="major_maintenance">Major Maintenance</option>
                    <option value="capital_construction">Capital Construction</option>
                  </select>
                </Field>
                {area("Summary (one or two sentences)", "summary")}
                {area("Project description", "projectDescription")}
                {text("Project address", "location.address")}
                {text("City", "location.city")}
                {text("County", "location.county")}
                {contact("Requester", "requester")}
                {contact("Project manager", "projectManager")}
              </div>
            </fieldset>

            <fieldset>
              <legend>Money</legend>
              <div className="ui-field-grid ui-field-grid--auto">
                <Field label="Estimated cost" field="estimateCents">
                  <MoneyInput cents={data.estimateCents} onChange={(c) => set("estimateCents", c)} />
                </Field>
                <Field
                  label="Funding amount" field="fundingAmountCents"
                  hint="The most the agency can spend. Frozen when the solicitation is published."
                >
                  <MoneyInput cents={data.fundingAmountCents} onChange={(c) => set("fundingAmountCents", c)} />
                </Field>
                <Field label="Funding source" field="fundingSource">
                  <select value={data.fundingSource ?? ""} onChange={(e) => set("fundingSource", e.target.value || null)}>
                    <option value="">Select...</option>
                    <option value="capital_construction">Capital Construction</option>
                    <option value="major_maintenance">Major Maintenance</option>
                    <option value="other">Other</option>
                  </select>
                </Field>
                {data.fundingSource === "other" && text("Funding source (describe)", "fundingOther")}
                <Field label="Federal funds" field="federalFunds">
                  <select
                    value={data.federalFunds === null ? "" : data.federalFunds ? "yes" : "no"}
                    onChange={(e) => set("federalFunds", e.target.value === "" ? null : e.target.value === "yes")}
                  >
                    <option value="">Select...</option>
                    <option value="yes">Yes</option>
                    <option value="no">No</option>
                  </select>
                </Field>
              </div>
            </fieldset>

            <fieldset>
              <legend>Dates</legend>
              <div className="ui-field-grid ui-field-grid--auto">
                {dateField("Requested release date", "releaseDate")}
                {dateField("Advertisement start", "adStart")}
                {dateField("Advertisement end", "adEnd")}
                {text("Newspapers", "newspapers")}
                {dateTimeField("Questions due", "questionsDue")}
                {dateTimeField("Answers / addenda due", "answersDue")}
                {dateField("Bid due date", "bidDueDate")}
                {text("Bid due time", "bidDueTime", "time")}
                <Field label="Bid validity (days)" field="bidValidityDays">
                  <input
                    type="number" min={1} value={Number.isFinite(data.bidValidityDays) ? data.bidValidityDays : ""}
                    onChange={(e) => set("bidValidityDays", e.target.value === "" ? Number.NaN : Number(e.target.value))}
                  />
                </Field>
                {dateField("Tentative award date (optional)", "tentativeAwardDate")}
                {dateField("Estimated start date (optional)", "estimatedStartDate")}
                {dateField("Estimated completion date (optional)", "estimatedCompletionDate")}
              </div>
            </fieldset>

            <fieldset>
              <legend>Pre-bid meeting</legend>
              <div className="ui-field-grid ui-field-grid--auto">
                <Field label="Pre-bid meeting" field="preBid.kind">
                  <select value={data.preBid.kind} onChange={(e) => set("preBid.kind", e.target.value)}>
                    <option value="none">None</option>
                    <option value="optional">Optional</option>
                    <option value="mandatory">Mandatory</option>
                  </select>
                </Field>
                {data.preBid.kind !== "none" && (
                  <>
                    <Field label="Format" field="preBid.format">
                      <select value={data.preBid.format ?? ""} onChange={(e) => set("preBid.format", e.target.value || null)}>
                        <option value="">Select...</option>
                        <option value="in_person">In person</option>
                        <option value="phone">Phone</option>
                        <option value="video">Video</option>
                      </select>
                    </Field>
                    {dateField("Meeting date", "preBid.date")}
                    <Field label="Meeting time" field="preBid.time">
                      <input type="time" value={data.preBid.time ?? ""} onChange={(e) => set("preBid.time", e.target.value || null)} />
                    </Field>
                    {text("Location or connection details", "preBid.location")}
                  </>
                )}
                <Choice className="sol-cell--wide" label="Facility requires a background check (optional)">
                  <input
                    type="checkbox" checked={data.backgroundCheck.required}
                    onChange={(e) => set("backgroundCheck.required", e.target.checked)}
                  />
                </Choice>
                {data.backgroundCheck.required && (
                  <>
                    {text("Background-check contact", "backgroundCheck.contact")}
                    <Field label="Lead time (days)" field="backgroundCheck.leadDays">
                      <input
                        type="number" min={0} value={data.backgroundCheck.leadDays ?? ""}
                        onChange={(e) => set("backgroundCheck.leadDays", e.target.value === "" ? null : Number(e.target.value))}
                      />
                    </Field>
                  </>
                )}
              </div>
            </fieldset>

            <fieldset>
              <legend>Bid schedule</legend>
              <p className="sol-note sol-note--below">Lump-sum line items. The bid form adds a total line.</p>
              {data.schedule.items.map((it, i) => (
                <div key={i} className="row">
                  <Field label="Item name" field={`schedule.items.${i}.name`}>
                    <input value={it.name} onChange={(e) => set(`schedule.items.${i}.name`, e.target.value)} />
                  </Field>
                  <Field label="Description (optional)">
                    <input value={it.description} onChange={(e) => set(`schedule.items.${i}.description`, e.target.value)} />
                  </Field>
                  <button
                    type="button" aria-label={`Remove item ${i + 1}`}
                    onClick={() => set("schedule.items", data.schedule.items.filter((_, j) => j !== i))}
                  >Remove</button>
                </div>
              ))}
              <IssueList issues={errors.filter((i) => i.field === "schedule.items")} kind="error" />
              <FieldComments field="schedule.items" />
              <button type="button" onClick={() => set("schedule.items", [...data.schedule.items, { name: "", description: "" }])}>
                Add line item
              </button>
              <h4 className="sol-subhead sol-subhead--spaced">Alternates (optional)</h4>
              {data.schedule.alternates.map((alt, i) => (
                <div key={i} className="row">
                  <select aria-label="Alternate kind" value={alt.kind} onChange={(e) => set(`schedule.alternates.${i}.kind`, e.target.value)}>
                    <option value="additive">Additive</option>
                    <option value="deductive">Deductive</option>
                  </select>
                  <input
                    aria-label="Alternate description" value={alt.description}
                    onChange={(e) => set(`schedule.alternates.${i}.description`, e.target.value)}
                  />
                  <button
                    type="button" aria-label={`Remove alternate ${i + 1}`}
                    onClick={() => set("schedule.alternates", data.schedule.alternates.filter((_, j) => j !== i))}
                  >Remove</button>
                </div>
              ))}
              <button type="button" onClick={() => set("schedule.alternates", [...data.schedule.alternates, { kind: "additive", description: "" }])}>
                Add alternate
              </button>
            </fieldset>

            <fieldset>
              <legend>Bid content</legend>
              <p className="sol-note sol-note--below">Sections required by the estimate are locked on. Page limits are printed, not checked.</p>
              {requiredSections.map((s) => {
                const optional = (OPTIONAL_SECTIONS as readonly string[]).includes(s);
                return (
                  <div key={s} className="row sol-row-aligned">
                    <Choice label={`${SECTION_LABELS[s]}${optional ? "" : " (required)"}`}>
                      <input
                        type="checkbox" checked disabled={!optional}
                        onChange={() => {
                          const nextLimits = { ...getLatest().pageLimits };
                          delete nextLimits[s];
                          onChange({
                            ...getLatest(),
                            optionalSections: getLatest().optionalSections.filter((o) => o !== s),
                            pageLimits: nextLimits,
                          });
                        }}
                      />
                    </Choice>
                    <label className="sol-inline">Page limit
                      <input
                        type="number" min={1} className="sol-narrow" value={data.pageLimits[s] ?? ""}
                        onChange={(e) => {
                          const next = { ...getLatest().pageLimits };
                          if (e.target.value === "") delete next[s]; else next[s] = Number(e.target.value);
                          set("pageLimits", next);
                        }}
                      />
                    </label>
                  </div>
                );
              })}
              {OPTIONAL_SECTIONS.filter((s) => !data.optionalSections.includes(s)).map((s) => (
                <div key={s} className="row">
                  <Choice label={`${SECTION_LABELS[s]} (optional)`}>
                    <input type="checkbox" checked={false} onChange={() => set("optionalSections", [...data.optionalSections, s])} />
                  </Choice>
                </div>
              ))}
            </fieldset>

            <fieldset>
              <legend>Author-editable text</legend>
              <div className="ui-field-grid ui-field-grid--auto">
                {area("Project-specific scope notes (optional)", "scopeNotes")}
                {area("Project-specific special provisions (optional)", "specialProvisions")}
              </div>
            </fieldset>

            <fieldset>
              <legend>Attachments</legend>
              {attachmentKinds.map((k) => (
                <AttachmentUploader
                  key={k.kind} kind={k.kind} title={k.title} needsIssueDate={k.issue}
                  attachments={data.attachments} disabled={!editable}
                  createUploadUrl={uploads.createUploadUrl}
                  onChange={(next) => set("attachments", next)}
                  onUploaded={uploads.onUploaded}
                />
              ))}
              {["plans", "specifications", "sample_contract", "prevailing_wage"].map((k) => (
                <div key={k}>
                  <IssueList issues={errors.filter((i) => i.field === `attachments.${k}`)} kind="error" />
                  <FieldComments field={`attachments.${k}`} />
                </div>
              ))}
            </fieldset>
          </fieldset>
        </form>
    </FieldCtx.Provider>
  );
}
