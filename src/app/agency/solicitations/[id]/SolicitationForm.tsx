"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { todayIn } from "@/domain/time";
import type { SolicitationData } from "@/domain/solicitation/types";
import { validate, type Issue } from "@/domain/solicitation/validate";
import { deriveRequirements } from "@/domain/solicitation/valueBands";
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
          <section>
            <h2>Status</h2>
            <span className="status-pill">{props.state}</span>
            {props.number && <> <strong>{props.number}</strong></>}
            {editable ? (
              <p style={{ margin: "6px 0 0" }}>
                {status === "saved" && "All changes saved."}
                {status === "dirty" && "Unsaved changes (autosaves after 5 seconds)."}
                {status === "saving" && "Saving..."}
                {status === "error" && "Save failed."}
                {" "}
                <button type="button" onClick={() => void save()} disabled={status === "saving"}>Save</button>
              </p>
            ) : (
              <p style={{ margin: "6px 0 0" }}>This solicitation is read-only while it is {props.state.replace("_", " ")}.</p>
            )}
            {message && <p role="alert" className="error">{message}</p>}
          </section>

          <section>
            <h2>Requirements</h2>
            <RequirementsList req={req} />
          </section>

          <section>
            <h2>Problems ({errors.length}) and warnings ({warnings.length})</h2>
            <IssueList issues={errors} kind="error" />
            <IssueList issues={warnings} kind="warning" acked={acked} onAck={ack} disabled={!editable} />
            {errors.length + warnings.length === 0 && <p style={{ margin: 0 }}>None.</p>}
          </section>

          {noFieldComments.length > 0 && (
            <section>
              <h2>Office comments</h2>
              {noFieldComments.map((c, i) => <div key={i} className="field-comment">{c.field ? `${c.field}: ` : ""}{c.body}</div>)}
            </section>
          )}

          <section>
            <h2>Preview</h2>
            <a href={`/api/solicitations/${id}/preview?doc=rfb`} target="_blank" rel="noreferrer">Preview RFB</a>
            {" · "}
            <a href={`/api/solicitations/${id}/preview?doc=bid-form`} target="_blank" rel="noreferrer">Preview bid form</a>
            <p style={{ margin: "4px 0 0" }}>Previews show the last saved draft.</p>
          </section>

          {editable && (
            <section>
              <h2>Submit for office review</h2>
              <button type="button" disabled={!canSubmit} onClick={() => void submit()}>
                {submitting ? "Submitting..." : "Submit for review"}
              </button>
              {!canSubmit && !submitting && <p style={{ margin: "4px 0 0" }}>Fix all problems and acknowledge all warnings first.</p>}
              {submitIssues && (
                <>
                  <p className="error" role="alert">The server did not accept the submission.</p>
                  <IssueList issues={submitIssues.errors} kind="error" />
                  <IssueList issues={submitIssues.unacknowledged} kind="warning" acked={acked} onAck={ack} />
                </>
              )}
            </section>
          )}
        </aside>
    </div>
  );
}