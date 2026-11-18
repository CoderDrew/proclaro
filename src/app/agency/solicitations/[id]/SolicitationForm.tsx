"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { todayIn } from "@/domain/time";
import type { SolicitationData } from "@/domain/solicitation/types";
import { validate, type Issue } from "@/domain/solicitation/validate";
import { deriveRequirements } from "@/domain/solicitation/valueBands";
import { Button, Card, Notice, StatusBadge } from "@/components/ui";
import { IssueList, ackKey } from "@/components/IssueList";
import { sidebarComments } from "@/components/fieldComments";
import { RequirementsList } from "@/components/RequirementsList";
import { SolicitationFields, type ReturnComment } from "@/components/SolicitationFields";
import { appendAttachment } from "./logic";
import { acknowledgeWarning, createUploadUrl, saveDraft, submitSolicitation } from "./actions";

export type { ReturnComment };
type SaveStatus = "saved" | "dirty" | "saving" | "error";
const AUTOSAVE_MS = 5000;

export function SolicitationForm(props: {
  id: string;
  initial: SolicitationData;
  state: string;
  number: string | null;
  tz: string;
  holidays: string[];
  acks: string[]; // `${code}|${field}`
  comments: ReturnComment[];
}) {
  const { id, tz, holidays } = props;
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

  const { errors, warnings } = useMemo(
    () => validate(data, { tz, holidays, submissionDate: todayIn(tz, new Date()) }),
    [data, tz, holidays],
  );
  const req = useMemo(
    () => (data.estimateCents === null ? null
      : deriveRequirements(data.estimateCents, data.federalFunds === true, data.optionalSections)),
    [data.estimateCents, data.federalFunds, data.optionalSections],
  );

  const save = useCallback(async (): Promise<boolean> => {
    const target = rev.current;
    setStatus("saving");
    try {
      await saveDraft(id, latest.current);
      setStatus(rev.current === target ? "saved" : "dirty");
      setMessage(null);
      return true;
    } catch (e) {
      setStatus("error");
      setMessage(e instanceof Error ? e.message : "Save failed");
      return false;
    }
  }, [id]);

  const change = useCallback((next: SolicitationData) => {
    latest.current = next;
    rev.current += 1;
    setData(next);
    setStatus("dirty");
  }, []);

  // Debounced autosave: 5 seconds after the last change.
  useEffect(() => {
    if (!editable || status !== "dirty") return;
    const t = setTimeout(() => { void save(); }, AUTOSAVE_MS);
    return () => clearTimeout(t);
  }, [data, status, editable, save]);

  const ack = useCallback(async (issue: Issue) => {
    try {
      await acknowledgeWarning(id, issue.code, issue.field === "" ? null : issue.field);
      setAcked((s) => new Set(s).add(ackKey(issue)));
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Acknowledge failed");
    }
  }, [id]);



  async function submit() {
    setSubmitting(true);
    setMessage(null);
    setSubmitIssues(null);
    try {
      if (!(await save())) return;
      const r = await submitSolicitation(id);
      if (r.ok) router.refresh();
      else setSubmitIssues({ errors: r.errors, unacknowledged: r.unacknowledged });
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Submit failed");
    } finally {
      setSubmitting(false);
    }
  }


  const noFieldComments = sidebarComments(props.comments, data);
  const unackedNow = warnings.filter((w) => !acked.has(ackKey(w)));
  const canSubmit = editable && errors.length === 0 && unackedNow.length === 0 && !submitting && status !== "saving";

  return (
    <div className="sol-layout">
      <SolicitationFields
        data={data} getLatest={() => latest.current} onChange={change} editable={editable}
        errors={errors} warnings={warnings} acked={acked} onAck={ack} comments={props.comments} req={req}
        uploads={{
          createUploadUrl: (name) => createUploadUrl(id, name),
          onUploaded: (added) => { change(appendAttachment(latest.current, added)); void save(); },
        }}
      />

      <aside className="sol-side">
        <Card as="section" title="Status">
          <StatusBadge status={{ kind: "solicitation", state: props.state }} />
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
            <p className="sol-note">This solicitation is read-only while it is {props.state.replace("_", " ")}.</p>
          )}
          {message && <Notice tone="error" role="alert">{message}</Notice>}
        </Card>

        <Card as="section" title="Requirements">
          <RequirementsList req={req} />
        </Card>

        <Card as="section" title={`Problems (${errors.length}) and warnings (${warnings.length})`}>
          <IssueList issues={errors} kind="error" />
          <IssueList issues={warnings} kind="warning" acked={acked} onAck={ack} disabled={!editable} />
          {errors.length + warnings.length === 0 && <p className="sol-note sol-note--flush">None.</p>}
        </Card>

        {noFieldComments.length > 0 && (
          <Card as="section" title="Office comments">
            {noFieldComments.map((c, i) => (
              <Notice key={i} tone="warning">{c.field ? `${c.field}: ` : ""}{c.body}</Notice>
            ))}
          </Card>
        )}

        <Card as="section" title="Preview">
          <a href={`/api/solicitations/${id}/preview?doc=rfb`} target="_blank" rel="noreferrer">Preview RFB</a>
          {" · "}
          <a href={`/api/solicitations/${id}/preview?doc=bid-form`} target="_blank" rel="noreferrer">Preview bid form</a>
          <p className="sol-note">Previews show the last saved draft.</p>
        </Card>

        {editable && (
          <Card as="section" title="Submit for office review">
            <Button type="button" variant="primary" disabled={!canSubmit} onClick={() => void submit()}>
              {submitting ? "Submitting..." : "Submit for review"}
            </Button>
            {!canSubmit && !submitting && <p className="sol-note">Fix all problems and acknowledge all warnings first.</p>}
            {submitIssues && (
              <>
                <Notice tone="error" role="alert">The server did not accept the submission.</Notice>
                <IssueList issues={submitIssues.errors} kind="error" />
                <IssueList issues={submitIssues.unacknowledged} kind="warning" acked={acked} onAck={ack} />
              </>
            )}
          </Card>
        )}
      </aside>
    </div>
  );
}