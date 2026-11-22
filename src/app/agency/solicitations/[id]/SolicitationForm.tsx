"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { todayIn } from "@/domain/time";
import { LOCKED_FIELDS } from "@/domain/addendum/lockedFields";
import type { SolicitationData } from "@/domain/solicitation/types";
import { validate, type Issue } from "@/domain/solicitation/validate";
import { deriveRequirements } from "@/domain/solicitation/valueBands";
import { Button, ButtonLink, Card, Notice, StatusBadge } from "@/components/ui";
import { IssueList, ackKey } from "@/components/IssueList";
import { sidebarComments } from "@/components/fieldComments";
import { RequirementsList } from "@/components/RequirementsList";
import { SolicitationFields, type ReturnComment } from "@/components/SolicitationFields";
import { appendAttachment, type SubmitResult } from "./logic";

export type { ReturnComment };
type SaveStatus = "saved" | "dirty" | "saving" | "error";
const AUTOSAVE_MS = 5000;
const LOCKED: ReadonlySet<string> = new Set(LOCKED_FIELDS);

/** What the form calls. Each throws an Error whose message is shown to the user. */
export interface SolicitationFormActions {
  save(data: SolicitationData): Promise<void>;
  upload(fileName: string): Promise<{ path: string; token: string }>;
  /** Without it, warnings are shown but never block submit (addenda have no warning acknowledgments). */
  acknowledgeWarning?(code: string, field: string | null): Promise<void>;
  submit(): Promise<SubmitResult>;
}

export function SolicitationForm(props: {
  id: string;
  initial: SolicitationData;
  state: string;
  number: string | null;
  tz: string;
  holidays: string[];
  acks: string[]; // `${code}|${field}`
  comments: ReturnComment[];
  actions: SolicitationFormActions;
  /** `addendum`: locked fields read-only, addendum-mode validation, addendum wording. Default `setup`. */
  mode?: "setup" | "addendum";
  /** Rendered above the fields. `markDirty` schedules an autosave for changes the form doesn't hold (the narrative). */
  lead?: (markDirty: () => void) => ReactNode;
  /** Rendered at the end of the side column. */
  side?: ReactNode;
  /** Problems the form doesn't compute (narrative, answers): listed and blocking submit. */
  extraErrors?: Issue[];
  /** Called with every change, for views that depend on the live data (the schedule diff). */
  onDataChange?: (data: SolicitationData) => void;
}) {
  const { id, tz, holidays, actions, onDataChange } = props;
  const mode = props.mode ?? "setup";
  const addendum = mode === "addendum";
  const router = useRouter();
  const editable = props.state === "draft";
  const [data, setData] = useState(props.initial);
  const [acked, setAcked] = useState<ReadonlySet<string>>(new Set(props.acks));
  const [status, setStatus] = useState<SaveStatus>("saved");
  const [message, setMessage] = useState<string | null>(null);
  const [submitIssues, setSubmitIssues] = useState<{ errors: Issue[]; unacknowledged: Issue[] } | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const latest = useRef(data);
  const rev = useRef(0);

  const { errors, warnings } = useMemo(() => {
    const submissionDate = todayIn(tz, new Date());
    return addendum
      ? validate(data, { tz, holidays, submissionDate, mode: "addendum", now: new Date() })
      : validate(data, { tz, holidays, submissionDate });
  }, [data, tz, holidays, addendum]);
  const req = useMemo(
    () => (data.estimateCents === null ? null
      : deriveRequirements(data.estimateCents, data.federalFunds === true, data.optionalSections)),
    [data.estimateCents, data.federalFunds, data.optionalSections],
  );

  const save = useCallback(async (): Promise<boolean> => {
    const target = rev.current;
    setStatus("saving");
    try {
      await actions.save(latest.current);
      setStatus(rev.current === target ? "saved" : "dirty");
      setMessage(null);
      return true;
    } catch (e) {
      setStatus("error");
      setMessage(e instanceof Error ? e.message : "Save failed");
      return false;
    }
  }, [actions]);

  const markDirty = useCallback(() => {
    rev.current += 1;
    setStatus("dirty");
  }, []);

  const change = useCallback((next: SolicitationData) => {
    latest.current = next;
    rev.current += 1;
    setData(next);
    setStatus("dirty");
    onDataChange?.(next);
  }, [onDataChange]);

  // Debounced autosave: 5 seconds after the last change.
  useEffect(() => {
    if (!editable || status !== "dirty") return;
    const t = setTimeout(() => { void save(); }, AUTOSAVE_MS);
    return () => clearTimeout(t);
  }, [data, status, editable, save]);

  const ackAction = actions.acknowledgeWarning;
  const ack = useCallback(async (issue: Issue) => {
    if (!ackAction) return;
    try {
      await ackAction(issue.code, issue.field === "" ? null : issue.field);
      setAcked((s) => new Set(s).add(ackKey(issue)));
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Acknowledge failed");
    }
  }, [ackAction]);



  async function submit() {
    setSubmitting(true);
    setMessage(null);
    setSubmitIssues(null);
    try {
      if (!(await save())) return;
      const r = await actions.submit();
      if (r.ok) router.refresh();
      else setSubmitIssues({ errors: r.errors, unacknowledged: r.unacknowledged });
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Submit failed");
    } finally {
      setSubmitting(false);
    }
  }


  const noFieldComments = sidebarComments(props.comments, data);
  const allErrors = props.extraErrors && props.extraErrors.length > 0 ? [...props.extraErrors, ...errors] : errors;
  const unackedNow = ackAction ? warnings.filter((w) => !acked.has(ackKey(w))) : [];
  const canSubmit = editable && allErrors.length === 0 && unackedNow.length === 0 && !submitting && status !== "saving";
  const noun = addendum ? "addendum" : "solicitation";
  const fields = (
    <SolicitationFields
      data={data} getLatest={() => latest.current} onChange={change} editable={editable}
      errors={errors} warnings={warnings} acked={acked} onAck={ack} comments={props.comments} req={req}
      uploads={{
        createUploadUrl: (name) => actions.upload(name),
        onUploaded: (added) => { change(appendAttachment(latest.current, added)); void save(); },
      }}
      locked={addendum ? LOCKED : undefined}
    />
  );

  return (
    <div className="sol-layout">
      {props.lead ? <div className="ui-stack">{props.lead(markDirty)}{fields}</div> : fields}

      <aside className="sol-side">
        <Card as="section" title="Status">
          <StatusBadge status={{ kind: addendum ? "addendum" : "solicitation", state: props.state }} />
          {props.number && <> <strong>{props.number}</strong></>}
          {editable ? (
            <p className="sol-note">
              {status === "saved" && "All changes saved."}
              {status === "dirty" && "Unsaved changes (autosaves after 5 seconds)."}
              {status === "saving" && "Saving..."}
              {status === "error" && "Save failed."}
              {" "}
              <Button type="button" variant="secondary" onClick={() => void save()} disabled={status === "saving"}>Save</Button>
            </p>
          ) : (
            <p className="sol-note">This {noun} is read-only while it is {props.state.replace("_", " ")}.</p>
          )}
          {message && <Notice tone="error" role="alert">{message}</Notice>}
        </Card>

        <Card as="section" title="Requirements">
          <RequirementsList req={req} />
        </Card>

        <Card as="section" title={`Problems (${allErrors.length}) and warnings (${warnings.length})`}>
          <IssueList issues={allErrors} kind="error" />
          <IssueList issues={warnings} kind="warning" acked={acked} onAck={ackAction ? ack : undefined} disabled={!editable} />
          {allErrors.length + warnings.length === 0 && <p className="sol-note sol-note--flush">None.</p>}
        </Card>

        {noFieldComments.length > 0 && (
          <Card as="section" title="Office comments">
            {noFieldComments.map((c, i) => (
              <Notice key={i} tone="warning">{c.field ? `${c.field}: ` : ""}{c.body}</Notice>
            ))}
          </Card>
        )}

        {!addendum && (
          <Card as="section" title="Preview">
            <div className="ui-inline-actions">
              <ButtonLink href={`/api/solicitations/${id}/preview?doc=rfb`} target="_blank" rel="noreferrer">Preview RFB</ButtonLink>
              <ButtonLink href={`/api/solicitations/${id}/preview?doc=bid-form`} target="_blank" rel="noreferrer">Preview bid form</ButtonLink>
            </div>
            <p className="sol-note">Previews show the last saved draft.</p>
          </Card>
        )}

        {editable && (
          <Card as="section" title="Submit for office review">
            <Button type="button" variant="primary" disabled={!canSubmit} onClick={() => void submit()}
              aria-describedby={!canSubmit && !submitting ? `${id}-submit-hint` : undefined}>
              {submitting ? "Submitting..." : "Submit for review"}
            </Button>
            {!canSubmit && !submitting && (
              <p className="sol-note" id={`${id}-submit-hint`}>
                {ackAction ? "Fix all problems and acknowledge all warnings first." : "Fix all problems first."}
              </p>
            )}
            {submitIssues && (
              <>
                <Notice tone="error" role="alert">The server did not accept the submission.</Notice>
                <IssueList issues={submitIssues.errors} kind="error" />
                <IssueList issues={submitIssues.unacknowledged} kind="warning" acked={acked} onAck={ackAction ? ack : undefined} />
              </>
            )}
          </Card>
        )}

        {props.side}
      </aside>
    </div>
  );
}
