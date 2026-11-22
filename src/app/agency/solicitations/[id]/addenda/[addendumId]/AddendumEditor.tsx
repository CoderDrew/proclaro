"use client";

import { startTransition, useCallback, useMemo, useRef, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { describeScheduleChange, diffSchedule, type ScheduleChange } from "@/domain/addendum/diff";
import type { SolicitationData } from "@/domain/solicitation/types";
import { Button, Card, ConfirmAction, DateTime, EmptyState, Field, Notice } from "@/components/ui";
import { SolicitationForm, type ReturnComment, type SolicitationFormActions } from "../../SolicitationForm";
import {
  createAddendumUploadUrl, removeAnswer, saveAddendum, saveAnswer, submitAddendum, withdrawAddendum,
} from "./actions";
import { ANSWER_MAX, answerDraftProblems, narrativeProblems, type AnswerDraft } from "./logic";

type Schedule = SolicitationData["schedule"];

export interface EditorQuestion { id: string; body: string; reference: string; askedAt: string }

/** The agency's addendum editor: narrative, the solicitation form in addendum mode, the schedule diff and answers. */
export function AddendumEditor(props: {
  solicitationId: string;
  addendumId: string;
  number: number;
  /** The effective state (withdrawn after close when unpublished). Editable only as a draft. */
  state: string;
  initial: SolicitationData;
  narrative: string;
  /** The schedule in the current published version, or null when it can't be read. */
  baseSchedule: Schedule | null;
  tz: string;
  holidays: string[];
  comments: ReturnComment[];
  /** Open questions, plus any already answered in this addendum. */
  questions: EditorQuestion[];
  answers: { questionId: string; publishedQuestion: string; answer: string }[];
}) {
  const { addendumId, number, tz } = props;
  const editable = props.state === "draft";
  const [narrative, setNarrative] = useState(props.narrative);
  const narrativeRef = useRef(props.narrative);
  const [schedule, setSchedule] = useState(props.initial.schedule);
  const labels = useMemo(
    () => new Map(props.questions.map((q, i) => [q.id, `Question ${i + 1}`])), [props.questions]);
  const [answers, setAnswers] = useState<ReadonlyMap<string, AnswerDraft>>(() => new Map(props.answers.map((a) => [
    a.questionId,
    { questionId: a.questionId, label: labels.get(a.questionId) ?? "Question", publishedQuestion: a.publishedQuestion,
      answer: a.answer, saved: true },
  ])));

  const actions = useMemo<SolicitationFormActions>(() => ({
    async save(data) {
      const r = await saveAddendum(addendumId, data, narrativeRef.current);
      if (!r.ok) throw new Error(r.message);
    },
    async upload(fileName) {
      const r = await createAddendumUploadUrl(addendumId, fileName);
      if (!r.ok) throw new Error(r.message);
      return { path: r.path, token: r.token };
    },
    async submit() {
      const r = await submitAddendum(addendumId);
      if ("message" in r) throw new Error(r.message);
      return r;
    },
  }), [addendumId]);

  const onDataChange = useCallback((d: SolicitationData) => setSchedule(d.schedule), []);

  const ordered = props.questions.map((q) => answers.get(q.id)).filter((a): a is AnswerDraft => !!a);
  const extraErrors = editable ? [...narrativeProblems(narrative), ...answerDraftProblems(ordered)] : [];
  const changes = props.baseSchedule ? diffSchedule(props.baseSchedule, schedule) : null;
  const showDiff = props.state !== "published" && props.state !== "withdrawn";

  const setAnswer = (qid: string, next: AnswerDraft | null) => setAnswers((m) => {
    const copy = new Map(m);
    if (next) copy.set(qid, next); else copy.delete(qid);
    return copy;
  });

  return (
    <SolicitationForm
      id={props.solicitationId}
      initial={props.initial}
      state={props.state}
      number={`Addendum ${number}`}
      tz={tz}
      holidays={props.holidays}
      acks={[]}
      comments={props.comments}
      actions={actions}
      mode="addendum"
      extraErrors={extraErrors}
      onDataChange={onDataChange}
      side={editable ? <WithdrawCard solicitationId={props.solicitationId} addendumId={addendumId} number={number} /> : null}
      lead={(markDirty) => (
        <>
          <Card as="section" title="Changes in this addendum">
            <Field label="Changes in this addendum (required)" id={`${addendumId}-narrative`}
              hint="Plain text, printed on the addendum. Describe every change bidders need to know about."
              error={editable && narrative.trim() === "" ? "Describe the changes in this addendum." : undefined}>
              <textarea rows={5} value={narrative} disabled={!editable}
                onChange={(e) => { setNarrative(e.target.value); narrativeRef.current = e.target.value; markDirty(); }} />
            </Field>
          </Card>

          {showDiff && (
            <Card as="section" title="Changes to the bid schedule">
              <ScheduleChanges changes={changes} />
            </Card>
          )}

          <Card as="section" title="Answers">
            <AnswersSection
              addendumId={addendumId} editable={editable} tz={tz} questions={props.questions}
              labels={labels} answers={answers} setAnswer={setAnswer}
            />
          </Card>
        </>
      )}
    />
  );
}


function ScheduleChanges({ changes }: { changes: ScheduleChange[] | null }) {
  if (changes === null) return <p className="muted">The current bid schedule could not be read, so changes can&apos;t be shown.</p>;
  if (changes.length === 0) return <EmptyState>No changes to the bid schedule.</EmptyState>;
  return (
    <>
      <ul data-testid="schedule-changes">
        {changes.map((c) => <li key={`${c.kind}-${c.position}-${c.change}`}>{describeScheduleChange(c)}</li>)}
      </ul>
      <Notice tone="warning">
        Publishing an addendum that changes the bid schedule clears bidders&apos; entered prices, and every bid already
        submitted must be submitted again.
      </Notice>
    </>
  );
}

function AnswersSection(props: {
  addendumId: string; editable: boolean; tz: string; questions: EditorQuestion[];
  labels: ReadonlyMap<string, string>; answers: ReadonlyMap<string, AnswerDraft>;
  setAnswer: (qid: string, next: AnswerDraft | null) => void;
}) {
  const shown = props.editable ? props.questions : props.questions.filter((q) => props.answers.has(q.id));
  if (shown.length === 0) {
    return <EmptyState>{props.editable ? "No open questions." : "No questions are answered in this addendum."}</EmptyState>;
  }
  return (
    <div className="ui-stack">
      {props.editable && (
        <p className="muted">
          Bidders&apos; names are never shown. Edit the published question to remove anything that identifies the asker.
        </p>
      )}
      {shown.map((q) => (
        <QuestionAnswer
          key={q.id} addendumId={props.addendumId} editable={props.editable} tz={props.tz} question={q}
          label={props.labels.get(q.id) ?? "Question"} draft={props.answers.get(q.id) ?? null}
          onChange={(next) => props.setAnswer(q.id, next)}
        />
      ))}
    </div>
  );
}

type Status = { ok: boolean; message: string } | null;

function QuestionAnswer(props: {
  addendumId: string; editable: boolean; tz: string; question: EditorQuestion; label: string;
  draft: AnswerDraft | null; onChange: (next: AnswerDraft | null) => void;
}) {
  const { question: q, label, draft, editable } = props;
  const [status, setStatus] = useState<Status>(null);
  const [pending, setPending] = useState(false);
  // Whether the answer is stored in the addendum (it may have unsaved edits on top).
  const [persisted, setPersisted] = useState(draft !== null && draft.saved);
  const base = `answer-${q.id}`;

  const open = () => {
    setStatus(null);
    props.onChange({ questionId: q.id, label, publishedQuestion: q.body, answer: "", saved: false });
  };
  const edit = (patch: Partial<AnswerDraft>) => draft && props.onChange({ ...draft, ...patch, saved: false });

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!draft) return;
    setStatus(null);
    setPending(true);
    startTransition(async () => {
      const r = await saveAnswer(props.addendumId, q.id, draft.publishedQuestion, draft.answer);
      setPending(false);
      if (r.ok) {
        props.onChange({ ...draft, publishedQuestion: draft.publishedQuestion.trim(), answer: draft.answer.trim(), saved: true });
        setPersisted(true);
        setStatus({ ok: true, message: `${label}: answer saved.` });
      } else {
        setStatus({ ok: false, message: r.message });
      }
    });
  };

  const onRemove = () => {
    setStatus(null);
    setPending(true);
    startTransition(async () => {
      const r = await removeAnswer(props.addendumId, q.id);
      setPending(false);
      if (r.ok) {
        props.onChange(null);
        setPersisted(false);
        setStatus({ ok: true, message: `${label}: answer removed.` });
      } else {
        setStatus({ ok: false, message: r.message });
      }
    });
  };

  return (
    <form onSubmit={onSubmit} className="ui-form" data-testid={`question-${q.id}`}>
      <h3>{label}</h3>
      <p className="muted">
        Asked <DateTime iso={q.askedAt} tz={props.tz} />{q.reference ? <>. Reference: {q.reference}</> : null}
      </p>
      <p className="ui-prewrap">{q.body}</p>

      {draft === null ? (
        editable ? (
          <Button type="button" onClick={open} aria-label={`Answer ${label.toLowerCase()} in this addendum`}>
            Answer in this addendum
          </Button>
        ) : null
      ) : editable ? (
        <>
          <Field label="Published question" id={`${base}-q`}
            hint="Shown publicly. Remove anything that identifies the asker.">
            <textarea rows={3} maxLength={ANSWER_MAX} value={draft.publishedQuestion}
              onChange={(e) => edit({ publishedQuestion: e.target.value })} />
          </Field>
          <Field label="Answer" id={`${base}-a`}>
            <textarea rows={3} maxLength={ANSWER_MAX} value={draft.answer} onChange={(e) => edit({ answer: e.target.value })} />
          </Field>
          <span className="ui-inline-actions">
            <Button type="submit" variant="primary" loading={pending} aria-label={`Save answer to ${label.toLowerCase()}`}>
              {pending ? "Saving..." : "Save answer"}
            </Button>
            <Button type="button" disabled={pending} aria-label={`Remove answer to ${label.toLowerCase()}`}
              onClick={() => (persisted ? onRemove() : props.onChange(null))}>
              Remove answer
            </Button>
          </span>
          {!draft.saved && <p className="muted">Not saved yet.</p>}
        </>
      ) : (
        <dl>
          <dt>Published question</dt><dd className="ui-prewrap">{draft.publishedQuestion}</dd>
          <dt>Answer</dt><dd className="ui-prewrap">{draft.answer}</dd>
        </dl>
      )}

      <div role="status" aria-live="polite">
        {status?.ok ? <Notice tone="success" className="ui-inline-status">{status.message}</Notice> : null}
      </div>
      {status && !status.ok ? <Notice tone="error" role="alert" className="ui-inline-status">{status.message}</Notice> : null}
    </form>
  );
}

function WithdrawCard({ solicitationId, addendumId, number }: { solicitationId: string; addendumId: string; number: number }) {
  const router = useRouter();
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const hintId = `${addendumId}-withdraw-hint`;

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setError(null);
    setPending(true);
    startTransition(async () => {
      const r = await withdrawAddendum(addendumId, reason);
      if (r.ok) {
        router.push(`/agency/solicitations/${solicitationId}`);
        router.refresh();
      } else {
        setError(r.message);
        setPending(false);
      }
    });
  };

  return (
    <Card as="section" title="Withdraw addendum">
      <form onSubmit={onSubmit} className="ui-form">
        <Field label="Reason" id={`${addendumId}-withdraw-reason`}>
          <textarea rows={2} value={reason} onChange={(e) => setReason(e.target.value)} disabled={pending} />
        </Field>
        {reason.trim() === "" && <p className="sol-note" id={hintId}>Enter a reason to withdraw.</p>}
        <ConfirmAction
          label="Withdraw addendum" confirmLabel={`Confirm: withdraw Addendum ${number}`} variant="danger"
          warning="Withdrawing is final. Questions answered in it go back to open, and the next addendum reuses its number."
          busy={pending} busyLabel="Withdrawing..." disabled={reason.trim() === ""}
          describedBy={reason.trim() === "" ? hintId : undefined} data-testid="withdraw-addendum"
        />
        {error ? <Notice tone="error" role="alert" className="ui-inline-status">{error}</Notice> : null}
      </form>
    </Card>
  );
}
