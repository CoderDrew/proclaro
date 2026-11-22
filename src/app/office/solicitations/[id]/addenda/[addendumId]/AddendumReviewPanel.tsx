"use client";

import { useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import type { DateChange } from "@/documents/addendumDoc";
import type { Issue } from "@/domain/solicitation/validate";
import { IssueList } from "@/components/IssueList";
import {
  Button, Card, ConfirmAction, EmptyState, Field, Notice, StatusBadge, Table, Td, Th,
} from "@/components/ui";
import {
  approveAddendumAlone, approveAddendumCheck, disagreeAddendum, publishAddendumAction, reassignAddendumReview,
  reopenAddendumReview, returnAddendum, sendAddendumToCheck, startAddendumReview, withdrawAddendumAsOffice,
} from "./actions";
import { publishWarning, type AddendumAuditRow } from "./logic";

/** From public.addendum_review_info: each flag mirrors the database function's guard for the caller. */
export interface ReviewFlags {
  canStart: boolean; canReturn: boolean; canSend: boolean; canApprove: boolean; canDisagree: boolean;
  canApproveAlone: boolean; canReopen: boolean; canPublish: boolean; canWithdraw: boolean; afterAnswersDue: boolean;
}

/** Field paths the agency's addendum editor shows comments on. */
const FIELD_OPTIONS: { path: string; label: string }[] = [
  { path: "narrative", label: "Changes in this addendum" },
  { path: "schedule.items", label: "Bid schedule items" },
  { path: "questionsDue", label: "Questions due" },
  { path: "answersDue", label: "Answers / addenda due" },
  { path: "bidDueDate", label: "Bid due date" },
  { path: "bidDueTime", label: "Bid due time" },
  { path: "preBid.date", label: "Pre-bid date" },
  { path: "attachments.plans", label: "Plans" },
  { path: "attachments.specifications", label: "Specifications" },
  { path: "answers", label: "Questions and answers" },
];

type Outcome = { ok: boolean; message: string; errors?: Issue[] };
type Raw = { ok: true; message?: string; number?: number } | { ok: false; message: string; errors?: Issue[] };

function toOutcome(r: Raw): Outcome {
  if (!r.ok) return r;
  return { ok: true, message: r.message ?? (r.number !== undefined ? `Addendum ${r.number} published.` : "Done.") };
}
type CommentRow = { field: string; body: string };

export function AddendumReviewPanel(props: {
  addendumId: string;
  number: number;
  /** The effective state: after close an unpublished addendum reads withdrawn. */
  state: string;
  /** Office staff may act; anyone else only views. */
  canWork: boolean;
  flags: ReviewFlags;
  reviewerId: string | null;
  reviewerName: string | null;
  checkerName: string | null;
  singleReviewer: boolean;
  withdrawnReason: string | null;
  publishedVersion: number | null;
  solicitationNumber: string | null;
  narrative: string;
  /** null when either version's data can't be read. */
  changes: string[] | null;
  dateChanges: DateChange[] | null;
  answers: { questionId: string; publishedQuestion: string; answer: string }[];
  staff: { userId: string; name: string }[];
  history: AddendumAuditRow[];
}) {
  const { addendumId: id, number, state, flags } = props;
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [busy, setBusy] = useState<string | null>(null);
  const [result, setResult] = useState<Outcome | null>(null);
  const [comments, setComments] = useState<CommentRow[]>([{ field: "", body: "" }]);
  const [checkComment, setCheckComment] = useState("");
  const [reopenReason, setReopenReason] = useState("");
  const [withdrawReason, setWithdrawReason] = useState("");
  const [assignee, setAssignee] = useState("");

  const submit = (name: string, action: () => Promise<Raw>, onOk?: () => void) =>
    (e: FormEvent<HTMLFormElement>) => {
      e.preventDefault();
      setBusy(name);
      setResult(null);
      startTransition(async () => {
        let r: Outcome;
        try {
          r = toOutcome(await action());
        } catch {
          r = { ok: false, message: "Something went wrong. Reload the page and try again." };
        }
        setResult(r);
        setBusy(null);
        if (r.ok) {
          onOk?.();
          router.refresh();
        }
      });
    };

  const reviewer = flags.canReturn || flags.canSend || flags.canApproveAlone;
  const checker = flags.canApprove || flags.canDisagree;
  const noteId = (s: string) => `${id}-${s}-note`;
  const anyAction = reviewer || checker || flags.canStart || flags.canPublish || flags.canReopen || flags.canWithdraw;

  const statusNote =
    !props.canWork ? "You can view this addendum but not act on it."
    : state === "published" ? `Published${props.publishedVersion ? ` as version ${props.publishedVersion}` : ""}.`
    : state === "withdrawn" ? (props.withdrawnReason ? `Withdrawn. Reason: ${props.withdrawnReason}` : "Withdrawn. Bidding has closed, so it can no longer be published.")
    : state === "in_review" && !reviewer ? `Being reviewed by ${props.reviewerName ?? "another staff member"}.`
    : state === "in_check" && !checker ? "Waiting for a staff member who did not review it in this round to check it."
    : state === "approved" && !flags.canPublish ? "Approved. Its reviewer or checker publishes it."
    : state === "draft" ? "With the agency."
    : !anyAction ? "No action is available to you now. Reload the page."
    : null;

  return (
    <div className="sol-layout">
      <div>
        <Card as="section" title="Changes in this addendum">
          {props.narrative.trim() === ""
            ? <EmptyState>No description yet.</EmptyState>
            : <p className="ui-prewrap" data-testid="addendum-narrative">{props.narrative}</p>}
        </Card>

        <Card as="section" title="Bid schedule changes">
          {props.changes === null ? (
            <p className="muted">The bid schedule could not be read, so changes can&apos;t be shown.</p>
          ) : props.changes.length === 0 ? (
            <EmptyState>No changes to the bid schedule.</EmptyState>
          ) : (
            <>
              <ul data-testid="schedule-changes">{props.changes.map((c) => <li key={c}>{c}</li>)}</ul>
              <Notice tone="warning">
                Publishing clears bidders&apos; entered prices, and every bid already submitted must be submitted again.
              </Notice>
            </>
          )}
        </Card>

        <Card as="section" title="Key date changes">
          {props.dateChanges === null ? (
            <p className="muted">The dates could not be read, so changes can&apos;t be shown.</p>
          ) : props.dateChanges.length === 0 ? (
            <EmptyState>No key dates change.</EmptyState>
          ) : (
            <Table data-testid="date-changes">
              <thead><tr><Th>Date</Th><Th>Was</Th><Th>Now</Th></tr></thead>
              <tbody>
                {props.dateChanges.map((d) => (
                  <tr key={d.field}><Td>{d.field}</Td><Td>{d.before}</Td><Td>{d.after}</Td></tr>
                ))}
              </tbody>
            </Table>
          )}
        </Card>

        <Card as="section" title="Questions and answers">
          {props.answers.length === 0 ? <EmptyState>This addendum answers no questions.</EmptyState> : (
            <ol data-testid="addendum-answers">
              {props.answers.map((a) => (
                <li key={a.questionId}>
                  <p className="ui-prewrap"><strong>Question:</strong> {a.publishedQuestion}</p>
                  <p className="ui-prewrap"><strong>Answer:</strong> {a.answer}</p>
                </li>
              ))}
            </ol>
          )}
          <p className="muted">These are published exactly as shown, with no names.</p>
        </Card>
      </div>

      <aside className="sol-side">
        <Card as="section" title="Status">
          <StatusBadge status={{ kind: "addendum", state }} />
          {props.reviewerName && <p className="sol-note">Reviewer: {props.reviewerName}</p>}
          {props.checkerName && <p className="sol-note">Checker: {props.checkerName}</p>}
          {state === "approved" && props.singleReviewer && (
            <p className="sol-note">Single-reviewer approval (no second reviewer available).</p>
          )}
          {statusNote && <p className="sol-note" id={noteId("status")}>{statusNote}</p>}
          {state === "published" && props.solicitationNumber && (
            <p className="sol-note"><a href={`/solicitations/${props.solicitationNumber}`}>Public page</a></p>
          )}
        </Card>

        <Card as="section" title="Actions" data-testid="addendum-actions">
          <div role="status" aria-live="polite">
            {result?.ok ? <Notice tone="success" className="ui-inline-status">{result.message}</Notice> : null}
          </div>
          {result && !result.ok ? (
            <Notice tone="error" role="alert" className="ui-inline-status">
              {result.message}
              {result.errors && result.errors.length > 0 ? <IssueList issues={result.errors} kind="error" /> : null}
            </Notice>
          ) : null}

          {flags.canStart && (
            <form onSubmit={submit("start", () => startAddendumReview(id))} className="ui-form">
              <Button type="submit" variant="primary" loading={busy === "start"} data-testid="start-review">
                {busy === "start" ? "Starting..." : "Start review"}
              </Button>
            </form>
          )}

          {reviewer && (
            <>
              <p className="sol-note" id={noteId("reviewer")}>
                You are the reviewer. Return it to the agency with comments, send it to a second staff member to check,
                or approve it alone when no second reviewer is available.
              </p>
              <form onSubmit={submit("send", () => sendAddendumToCheck(id))} className="ui-form">
                <Button type="submit" variant="primary" disabled={!flags.canSend} loading={busy === "send"}
                  aria-describedby={noteId("reviewer")} data-testid="send-to-check">
                  {busy === "send" ? "Sending..." : "Send to check"}
                </Button>
              </form>
              <form onSubmit={submit("alone", () => approveAddendumAlone(id))} className="ui-form">
                <ConfirmAction label="Approve alone" confirmLabel={`Confirm: approve Addendum ${number} alone`}
                  variant="secondary" disabled={!flags.canApproveAlone} busy={busy === "alone"} busyLabel="Approving..."
                  warning="No second reviewer is available. This approval is recorded as a single-reviewer approval."
                  describedBy={noteId("reviewer")} data-testid="approve-alone" />
              </form>
            </>
          )}

          {checker && (
            <>
              <p className="sol-note" id={noteId("checker")}>
                You did not review this addendum in this round, so you can check it.
              </p>
              <form onSubmit={submit("approve", () => approveAddendumCheck(id))} className="ui-form">
                <Button type="submit" variant="primary" disabled={!flags.canApprove} loading={busy === "approve"}
                  aria-describedby={noteId("checker")} data-testid="approve-check">
                  {busy === "approve" ? "Approving..." : "Approve"}
                </Button>
              </form>
              <form onSubmit={submit("disagree", () => disagreeAddendum(id, checkComment), () => setCheckComment(""))}
                className="ui-form">
                <Field label="Comment" id={`${id}-disagree-comment`}
                  hint="Sends the addendum back to the reviewer. The comment is kept on record.">
                  <textarea rows={2} value={checkComment} onChange={(e) => setCheckComment(e.target.value)} />
                </Field>
                <Button type="submit" variant="danger" disabled={!flags.canDisagree || checkComment.trim() === ""}
                  loading={busy === "disagree"} aria-describedby={noteId("checker")} data-testid="disagree">
                  {busy === "disagree" ? "Sending..." : "Disagree"}
                </Button>
              </form>
            </>
          )}

          {flags.canPublish && (
            <form onSubmit={submit("publish", () => publishAddendumAction(id))} className="ui-form">
              <p className="sol-note" id={noteId("publish")}>
                Publishing renders the RFB, the bid form and the addendum as version {number + 1}{" "}
                and makes them public.
              </p>
              {flags.afterAnswersDue && (
                <Notice tone="warning" data-testid="after-answers-due">The answers-due date has passed.</Notice>
              )}
              <ConfirmAction label="Publish" confirmLabel={`Confirm: publish Addendum ${number}`}
                warning={publishWarning(number, flags.afterAnswersDue)} busy={busy === "publish"}
                busyLabel="Publishing..." describedBy={noteId("publish")} data-testid="publish-addendum" />
            </form>
          )}

          {flags.canReopen && (
            <form onSubmit={submit("reopen", () => reopenAddendumReview(id, reopenReason), () => setReopenReason(""))}
              className="ui-form">
              <Field label="Reason for reopening" id={`${id}-reopen-reason`}>
                <input value={reopenReason} onChange={(e) => setReopenReason(e.target.value)} />
              </Field>
              {reopenReason.trim() === "" && <p className="sol-note" id={noteId("reopen")}>Enter a reason to reopen.</p>}
              <Button type="submit" disabled={reopenReason.trim() === ""} loading={busy === "reopen"}
                aria-describedby={reopenReason.trim() === "" ? noteId("reopen") : undefined} data-testid="reopen">
                {busy === "reopen" ? "Reopening..." : "Reopen review"}
              </Button>
            </form>
          )}

          {props.canWork && state === "in_review" && (
            <form onSubmit={submit("reassign", () => reassignAddendumReview(id, assignee), () => setAssignee(""))}
              className="ui-form">
              <Field label="Reassign review to" id={`${id}-reassign`}>
                <select value={assignee} onChange={(e) => setAssignee(e.target.value)}>
                  <option value="">Select...</option>
                  {props.staff.filter((s) => s.userId !== props.reviewerId).map((s) => (
                    <option key={s.userId} value={s.userId}>{s.name}</option>
                  ))}
                </select>
              </Field>
              {assignee === "" && <p className="sol-note" id={noteId("reassign")}>Choose a staff member.</p>}
              <Button type="submit" disabled={assignee === ""} loading={busy === "reassign"}
                aria-describedby={assignee === "" ? noteId("reassign") : undefined} data-testid="reassign">
                {busy === "reassign" ? "Reassigning..." : "Reassign"}
              </Button>
            </form>
          )}

          {flags.canWithdraw && (
            <form onSubmit={submit("withdraw", () => withdrawAddendumAsOffice(id, withdrawReason),
              () => setWithdrawReason(""))} className="ui-form">
              <Field label="Reason for withdrawing" id={`${id}-withdraw-reason`}>
                <textarea rows={2} value={withdrawReason} onChange={(e) => setWithdrawReason(e.target.value)} />
              </Field>
              {withdrawReason.trim() === "" && (
                <p className="sol-note" id={noteId("withdraw")}>Enter a reason to withdraw.</p>
              )}
              <ConfirmAction label="Withdraw addendum" confirmLabel={`Confirm: withdraw Addendum ${number}`}
                variant="danger" disabled={withdrawReason.trim() === ""} busy={busy === "withdraw"}
                busyLabel="Withdrawing..."
                warning="Withdrawing is final. Questions answered in it go back to open, and the next addendum reuses its number."
                describedBy={withdrawReason.trim() === "" ? noteId("withdraw") : undefined}
                data-testid="withdraw-addendum" />
            </form>
          )}
        </Card>

        {flags.canReturn && (
          <Card as="section" title="Return to the agency">
            <form onSubmit={submit("return", () => returnAddendum(id, comments.map((c) => ({
              field: c.field === "" ? null : c.field, body: c.body,
            }))), () => setComments([{ field: "", body: "" }]))} className="ui-form">
              <p className="sol-note" id={noteId("return")}>
                The agency sees these comments on its addendum. Choose a field, or leave it general.
              </p>
              {comments.map((c, i) => (
                <div key={i} className="ui-comment-row">
                  <select aria-label={`Comment ${i + 1} field`} value={c.field}
                    onChange={(e) => setComments(comments.map((x, j) => (j === i ? { ...x, field: e.target.value } : x)))}>
                    <option value="">General (no field)</option>
                    {FIELD_OPTIONS.map((f) => <option key={f.path} value={f.path}>{f.label}</option>)}
                  </select>
                  <textarea aria-label={`Comment ${i + 1}`} value={c.body}
                    onChange={(e) => setComments(comments.map((x, j) => (j === i ? { ...x, body: e.target.value } : x)))} />
                  {comments.length > 1 && (
                    <Button type="button" aria-label={`Remove comment ${i + 1}`}
                      onClick={() => setComments(comments.filter((_, j) => j !== i))}>Remove</Button>
                  )}
                </div>
              ))}
              <span className="ui-inline-actions">
                <Button type="button" onClick={() => setComments([...comments, { field: "", body: "" }])}>
                  Add another comment
                </Button>
                <Button type="submit" variant="danger" loading={busy === "return"}
                  disabled={comments.every((c) => c.body.trim() === "")} aria-describedby={noteId("return")}
                  data-testid="return-addendum">
                  {busy === "return" ? "Returning..." : "Return to agency"}
                </Button>
              </span>
            </form>
          </Card>
        )}

        <Card as="section" title="History">
          {props.history.length === 0 ? <EmptyState>No history yet.</EmptyState> : (
            <ul className="ui-timeline" data-testid="addendum-history">
              {props.history.map((a) => (
                <li key={a.id}>
                  <strong>{a.action}</strong> by {a.actor}, {a.when}
                  {a.reason && <div>{a.reason}</div>}
                </li>
              ))}
            </ul>
          )}
        </Card>
      </aside>
    </div>
  );
}
