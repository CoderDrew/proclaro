"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { SolicitationData } from "@/domain/solicitation/types";
import { validate, type Issue } from "@/domain/solicitation/validate";
import { deriveRequirements } from "@/domain/solicitation/valueBands";
import { IssueList, ackKey } from "@/components/IssueList";
import { sidebarComments } from "@/components/fieldComments";
import { RequirementsList } from "@/components/RequirementsList";
import { SolicitationFields, type ReturnComment } from "@/components/SolicitationFields";
import {
  acknowledgeWarning, approveAlone, approveCheck, disagree, editAsReviewer, publish, reassign, reopenReview,
  returnToAgency, sendToCheck, startReview,
} from "./actions";
import type { ActionResult } from "./logic";
import { Button, Card, EmptyState, Field, Notice, StatusBadge } from "@/components/ui";

export interface AuditRow { id: number; actor: string; action: string; when: string; reason: string | null; changes: string[] }
export interface StaffMember { userId: string; name: string }

/** Field paths exactly as `Issue.field` reports them, so comments land on the agency form's fields. */
const FIELD_OPTIONS: { path: string; label: string }[] = [
  { path: "shortTitle", label: "Short title" }, { path: "longTitle", label: "Long title" },
  { path: "category", label: "Category" }, { path: "summary", label: "Summary" },
  { path: "projectDescription", label: "Project description" },
  { path: "location.address", label: "Project address" }, { path: "location.city", label: "City" },
  { path: "location.county", label: "County" },
  { path: "requester.name", label: "Requester name" }, { path: "requester.email", label: "Requester email" },
  { path: "requester.phone", label: "Requester phone" },
  { path: "projectManager.name", label: "Project manager name" },
  { path: "projectManager.email", label: "Project manager email" },
  { path: "projectManager.phone", label: "Project manager phone" },
  { path: "estimateCents", label: "Estimated cost" }, { path: "fundingSource", label: "Funding source" },
  { path: "fundingOther", label: "Funding source (describe)" }, { path: "federalFunds", label: "Federal funds" },
  { path: "releaseDate", label: "Requested release date" }, { path: "adStart", label: "Advertisement start" },
  { path: "adEnd", label: "Advertisement end" }, { path: "newspapers", label: "Newspapers" },
  { path: "questionsDue", label: "Questions due" }, { path: "answersDue", label: "Answers / addenda due" },
  { path: "bidDueDate", label: "Bid due date" }, { path: "bidDueTime", label: "Bid due time" },
  { path: "bidValidityDays", label: "Bid validity (days)" },
  { path: "tentativeAwardDate", label: "Tentative award date" },
  { path: "estimatedStartDate", label: "Estimated start date" },
  { path: "estimatedCompletionDate", label: "Estimated completion date" },
  { path: "preBid.kind", label: "Pre-bid meeting" }, { path: "preBid.format", label: "Pre-bid format" },
  { path: "preBid.date", label: "Pre-bid date" }, { path: "preBid.time", label: "Pre-bid time" },
  { path: "preBid.location", label: "Pre-bid location" },
  { path: "backgroundCheck.contact", label: "Background-check contact" },
  { path: "backgroundCheck.leadDays", label: "Background-check lead time" },
  { path: "schedule.items", label: "Bid schedule items" },
  { path: "attachments.plans", label: "Plans" }, { path: "attachments.specifications", label: "Specifications" },
  { path: "attachments.sample_contract", label: "Sample contract" },
  { path: "attachments.prevailing_wage", label: "Prevailing wage rates" },
  { path: "scopeNotes", label: "Scope notes" }, { path: "specialProvisions", label: "Special provisions" },
];

const STATE_LABELS: Record<string, string> = {
  draft: "Draft (with the agency)", submitted: "Submitted", in_review: "In review", in_check: "In check",
  approved: "Approved", published: "Published",
};

type CommentRow = { field: string; body: string };

export function ReviewPanel(props: {
  id: string;
  initial: SolicitationData;
  state: string;
  number: string | null;
  agencyName: string;
  reviewerId: string | null;
  checkerId: string | null;
  reviewerName: string | null;
  fallbackApproved: boolean;
  viewerId: string;
  /** Office staff may act; an admin from another organization may only view. */
  canWork: boolean;
  tz: string;
  holidays: string[];
  /** The latest submission date in the configured zone (anchors the release-date rule). */
  submissionDate: string;
  acks: string[]; // `${code}|${field}`
  checkerComments: ReturnComment[];
  staff: StaffMember[];
  audit: AuditRow[];
}) {
  const { id, tz, holidays, state } = props;
  const router = useRouter();
  const canPublish = props.canWork && state === "approved"
    && (props.reviewerId === props.viewerId || props.checkerId === props.viewerId);
  const isReviewer = props.canWork && state === "in_review" && props.reviewerId === props.viewerId;

  const [data, setData] = useState(props.initial);
  const latest = useRef(data);
  const [editing, setEditing] = useState(false);
  const [reason, setReason] = useState("");
  const [acked, setAcked] = useState<ReadonlySet<string>>(new Set(props.acks));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [gate, setGate] = useState<{ errors: Issue[]; unacknowledged: Issue[] } | null>(null);
  const [comments, setComments] = useState<CommentRow[]>([{ field: "", body: "" }]);
  const [confirmAlone, setConfirmAlone] = useState(false);
  const [checkField, setCheckField] = useState("");
  const [checkComment, setCheckComment] = useState("");
  const [assignee, setAssignee] = useState("");
  const [showPreviews, setShowPreviews] = useState(false);
  const [reopenReason, setReopenReason] = useState("");

  const { errors, warnings } = useMemo(
    () => validate(data, { tz, holidays, submissionDate: props.submissionDate }),
    [data, tz, holidays, props.submissionDate],
  );
  const req = useMemo(
    () => (data.estimateCents === null ? null
      : deriveRequirements(data.estimateCents, data.federalFunds === true, data.optionalSections)),
    [data.estimateCents, data.federalFunds, data.optionalSections],
  );
  const dirty = editing && JSON.stringify(data) !== JSON.stringify(props.initial);

  function change(next: SolicitationData) {
    latest.current = next;
    setData(next);
  }

  /** Runs one action; shows its message, or refreshes the page on success. */
  async function act(fn: () => Promise<ActionResult>, onOk?: () => void) {
    setBusy(true);
    setMessage(null);
    setGate(null);
    try {
      const r = await fn();
      if (r.ok) {
        onOk?.();
        router.refresh();
      } else {
        setMessage(r.message);
        if (r.errors || r.unacknowledged) setGate({ errors: r.errors ?? [], unacknowledged: r.unacknowledged ?? [] });
      }
    } catch {
      setMessage("Something went wrong. Reload the page and try again.");
    } finally {
      setBusy(false);
    }
  }

  async function ack(issue: Issue) {
    const r = await acknowledgeWarning(id, issue.code, issue.field === "" ? null : issue.field);
    if (r.ok) setAcked((s) => new Set(s).add(ackKey(issue)));
    else setMessage(r.message);
  }

  function cancelEdit() {
    change(props.initial);
    setEditing(false);
    setReason("");
    setMessage(null);
  }

  const sideComments = sidebarComments(props.checkerComments, data);
  const unackedNow = warnings.filter((w) => !acked.has(ackKey(w)));
  const canAdvance = isReviewer && !dirty && !busy;
  // Publish refused because the release date has passed: reopening is the way to correct it (spec 7.1).
  const releasePassed = gate?.errors.some((e) => e.code === "release_too_soon") ?? false;

  return (
    <div className="sol-layout">
      <div>
        {isReviewer && (
          <p className="ui-office-note">
            {editing ? (
              <>
                You are editing. Every change needs a reason, which is recorded in the history.
              </>
            ) : (
              <Button type="button" variant="secondary" onClick={() => setEditing(true)} disabled={busy}>Edit</Button>
            )}
          </p>
        )}
        {editing && (
          <Card as="section" className="ui-office-note">
            <Field label="Reason for the change">
              <input value={reason} onChange={(e) => setReason(e.target.value)} />
            </Field>
            <p className="ui-inline-actions">
              <Button
                type="button" variant="primary" disabled={busy || !dirty}
                onClick={() => void act(() => editAsReviewer(id, latest.current, reason), () => {
                  setEditing(false);
                  setReason("");
                })}
              >
                Save changes
              </Button>
              <Button type="button" variant="secondary" onClick={cancelEdit} disabled={busy}>Cancel</Button>
            </p>
          </Card>
        )}
        <SolicitationFields
          data={data} getLatest={() => latest.current} onChange={change} editable={editing}
          errors={errors} warnings={warnings} acked={acked} onAck={() => {}}
          comments={props.checkerComments} req={req}
          uploads={{
            createUploadUrl: async () => { throw new Error("not_authorized"); },
            onUploaded: () => {},
          }}
        />
      </div>

      <aside className="sol-side">
        <Card as="section" title="Status">
          <StatusBadge status={{ kind: "solicitation", state }} label={STATE_LABELS[state] ?? state} />
          {props.number && <> <strong>{props.number}</strong></>}
          <p className="ui-office-note">{props.agencyName}</p>
          {props.reviewerName && <p className="ui-office-note">Reviewer: {props.reviewerName}</p>}
          {state === "approved" && props.fallbackApproved && (
            <p className="ui-office-note">Single-reviewer approval (no second reviewer available).</p>
          )}
          {message && <Notice tone="error" role="alert">{message}</Notice>}
          {gate && (
            <>
              <IssueList issues={gate.errors} kind="error" />
              <IssueList issues={gate.unacknowledged} kind="warning" acked={acked} onAck={isReviewer ? ack : undefined} />
            </>
          )}
        </Card>

        <Card as="section" title="Actions">
          {!props.canWork && <p className="ui-office-note">You can view this solicitation but not act on it.</p>}

          {props.canWork && state === "submitted" && (
            <Button type="button" variant="primary" disabled={busy} onClick={() => void act(() => startReview(id))}>Start review</Button>
          )}

          {props.canWork && state === "in_review" && !isReviewer && (
            <p className="ui-office-note">This solicitation is being reviewed by {props.reviewerName ?? "another staff member"}.</p>
          )}

          {isReviewer && (
            <>
              <p className="ui-inline-actions">
                <Button type="button" variant="danger" disabled={!canAdvance} onClick={() => {
                  const rows = comments.map((c) => ({ field: c.field === "" ? null : c.field, body: c.body }));
                  void act(() => returnToAgency(id, rows));
                }}>Return</Button>
                <Button type="button" variant="primary" disabled={!canAdvance || errors.length > 0 || unackedNow.length > 0}
                  onClick={() => void act(() => sendToCheck(id))}>Send to check</Button>
                <Button type="button" variant="secondary" disabled={!canAdvance || errors.length > 0 || unackedNow.length > 0}
                  onClick={() => setConfirmAlone(true)}>Approve alone</Button>
              </p>
              {dirty && <p className="ui-office-note">Save or cancel your edits first.</p>}
              {!dirty && (errors.length > 0 || unackedNow.length > 0) && (
                <p className="ui-office-note">Fix all problems and acknowledge all warnings before sending to check or approving.</p>
              )}
              {confirmAlone && (
                <Notice tone="warning" role="alertdialog">
                  <p className="ui-office-note">
                    No second reviewer available. This approval will be recorded as a single-reviewer approval.
                  </p>
                  <p className="ui-inline-actions">
                    <Button type="button" variant="secondary" disabled={busy}
                      onClick={() => void act(() => approveAlone(id), () => setConfirmAlone(false))}>Confirm approve alone</Button>
                    <Button type="button" variant="secondary" onClick={() => setConfirmAlone(false)}>Cancel</Button>
                  </p>
                </Notice>
              )}
            </>
          )}

          {props.canWork && state === "in_check" && props.reviewerId === props.viewerId && (
            <p className="ui-office-note">Waiting for a different staff member to check this solicitation.</p>
          )}

          {props.canWork && state === "in_check" && props.reviewerId !== props.viewerId && (
            <>
              <p className="ui-office-note">
                <Button type="button" variant="primary" disabled={busy} onClick={() => void act(() => approveCheck(id))}>Approve</Button>
              </p>
              <Field label="Disagree with this field (optional)">
                <select value={checkField} onChange={(e) => setCheckField(e.target.value)}>
                  <option value="">General (no field)</option>
                  {FIELD_OPTIONS.map((f) => <option key={f.path} value={f.path}>{f.label}</option>)}
                </select>
              </Field>
              <Field label="Comment">
                <textarea value={checkComment} onChange={(e) => setCheckComment(e.target.value)} />
              </Field>
              <p>
                <Button type="button" variant="danger" disabled={busy}
                  onClick={() => void act(() => disagree(id, checkComment, checkField === "" ? null : checkField))}>
                  Disagree
                </Button>
              </p>
            </>
          )}

          {state === "approved" && !canPublish && (
            <p className="ui-office-note">Approved. The reviewer or checker publishes it.</p>
          )}
          {canPublish && (
            <>
              <p className="ui-office-note">
                <Button type="button" variant="primary" disabled={busy} onClick={() => void act(() => publish(id))}>
                  {busy ? "Publishing..." : "Publish"}
                </Button>
              </p>
              <p className="ui-office-note">
                Publishing renders the final documents and freezes this solicitation. It cannot be edited afterwards.
              </p>
              {releasePassed && (
                <Notice tone="warning">
                  The release date has passed. Reopen the review so the reviewer can correct the dates; it then
                  needs a new check (or approval) before publishing.
                </Notice>
              )}
              <Field label="Reason for reopening">
                <input value={reopenReason} onChange={(e) => setReopenReason(e.target.value)} />
              </Field>
              <p>
                <Button type="button" variant="secondary" disabled={busy || reopenReason.trim() === ""}
                  onClick={() => void act(() => reopenReview(id, reopenReason), () => setReopenReason(""))}>
                  Reopen to correct dates
                </Button>
              </p>
            </>
          )}
          {state === "published" && props.number && (
            <p className="ui-office-note">
              Published as <strong>{props.number}</strong>.{" "}
              <a href={`/solicitations/${props.number}`}>Public page</a>
              {props.initial.releaseDate && ` (visible to the public from ${props.initial.releaseDate})`}
            </p>
          )}

          {props.canWork && state === "in_review" && (
            <div className="ui-stack-tight">
              <Field label="Reassign review to">
                <select value={assignee} onChange={(e) => setAssignee(e.target.value)}>
                  <option value="">Select...</option>
                  {props.staff.filter((s) => s.userId !== props.reviewerId).map((s) => (
                    <option key={s.userId} value={s.userId}>{s.name}</option>
                  ))}
                </select>
              </Field>
              <Button type="button" variant="secondary" disabled={busy || assignee === ""} onClick={() => void act(() => reassign(id, assignee))}>
                Reassign
              </Button>
            </div>
          )}
        </Card>

        {isReviewer && (
          <Card as="section" title="Comments to the agency">
            <p className="ui-office-note">Used when you return the solicitation. Choose a field, or leave it general.</p>
            {comments.map((c, i) => (
              <div key={i} className="ui-comment-row">
                <select
                  aria-label={`Comment ${i + 1} field`} value={c.field}
                  onChange={(e) => setComments(comments.map((x, j) => (j === i ? { ...x, field: e.target.value } : x)))}
                >
                  <option value="">General (no field)</option>
                  {FIELD_OPTIONS.map((f) => <option key={f.path} value={f.path}>{f.label}</option>)}
                </select>
                <textarea
                  aria-label={`Comment ${i + 1}`} value={c.body}
                  onChange={(e) => setComments(comments.map((x, j) => (j === i ? { ...x, body: e.target.value } : x)))}
                />
                {comments.length > 1 && (
                  <Button type="button" variant="secondary" aria-label={`Remove comment ${i + 1}`}
                    onClick={() => setComments(comments.filter((_, j) => j !== i))}>Remove</Button>
                )}
              </div>
            ))}
            <Button type="button" variant="secondary" onClick={() => setComments([...comments, { field: "", body: "" }])}>Add another comment</Button>
          </Card>
        )}

        <Card as="section" title="Requirements">
          <RequirementsList req={req} />
        </Card>

        <Card as="section" title={`Problems (${errors.length}) and warnings (${warnings.length})`}>
          <IssueList issues={errors} kind="error" />
          <IssueList issues={warnings} kind="warning" acked={acked} onAck={isReviewer ? ack : undefined} disabled={busy} />
          {errors.length + warnings.length === 0 && <p className="ui-office-note">None.</p>}
        </Card>

        {sideComments.length > 0 && (
          <Card as="section" title="Checker comments">
            {sideComments.map((c, i) => <Notice key={i} tone="warning">{c.field ? `${c.field}: ` : ""}{c.body}</Notice>)}
          </Card>
        )}

        <Card as="section" title="Preview">
          <a href={`/api/solicitations/${id}/preview?doc=rfb`} target="_blank" rel="noreferrer">Open RFB</a>
          {" · "}
          <a href={`/api/solicitations/${id}/preview?doc=bid-form`} target="_blank" rel="noreferrer">Open bid form</a>
          <p className="ui-office-note">
            <Button type="button" variant="secondary" onClick={() => setShowPreviews((v) => !v)}>
              {showPreviews ? "Hide embedded previews" : "Show embedded previews"}
            </Button>
          </p>
          <p className="ui-office-note">Previews show the last saved data.</p>
        </Card>

        <Card as="section" title="History">
          {props.audit.length === 0 ? <EmptyState>No history yet.</EmptyState> : (
            <ul className="ui-timeline">
              {props.audit.map((a) => (
                <li key={a.id}>
                  <strong>{a.action}</strong> by {a.actor}, {a.when}
                  {a.reason && <div>{a.reason}</div>}
                  {a.changes.length > 0 && (
                    <ul>
                      {a.changes.map((ch, i) => <li key={i}>{ch}</li>)}
                    </ul>
                  )}
                </li>
              ))}
            </ul>
          )}
        </Card>
      </aside>

      {showPreviews && (
        <div className="ui-preview-grid">
          <iframe title="RFB preview" src={`/api/solicitations/${id}/preview?doc=rfb`} style={{ width: "100%", height: 700 }} />
          <iframe title="Bid form preview" src={`/api/solicitations/${id}/preview?doc=bid-form`} style={{ width: "100%", height: 700 }} />
        </div>
      )}
    </div>
  );
}
