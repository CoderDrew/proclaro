"use client";

import { useId, useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { Button, Card, DateTime, EmptyState, Field, Notice, StatusBadge, Table, Td, Th } from "@/components/ui";
import { askQuestion } from "./actions";
import { bidderQuestionStatus, QUESTION_MAX, REFERENCE_MAX, type MyQuestion } from "./logic";

/**
 * "Ask a question" until questions are due, then the closed line; and "Your questions": the caller's own
 * organization's questions only (public.my_questions), with their status. Shown before a bid is started too.
 */
export function QuestionsPanel(props: {
  solicitationId: string; questions: MyQuestion[]; tz: string; canAsk: boolean; closedText: string;
}) {
  const { questions, tz } = props;
  return (
    <Card as="section" title="Questions" data-testid="bidder-questions">
      {props.canAsk ? <AskForm solicitationId={props.solicitationId} /> : <p data-testid="questions-closed">{props.closedText}</p>}
      <h3>Your questions</h3>
      {questions.length === 0 ? (
        <EmptyState>Your organization has not asked any questions.</EmptyState>
      ) : (
        <>
          <p className="muted">Only your organization and the purchasing office see these. Answers are published in addenda.</p>
          <Table>
            <thead>
              <tr><Th>Asked</Th><Th>Reference</Th><Th>Question</Th><Th>Status</Th></tr>
            </thead>
            <tbody>
              {questions.map((q) => (
                <tr key={q.id} data-testid="my-question">
                  <Td><DateTime iso={q.askedAt} tz={tz} /></Td>
                  <Td>{q.reference || "None"}</Td>
                  <Td className="ui-prewrap">{q.body}</Td>
                  <Td><StatusBadge status={{ kind: "question", status: q.status }} label={bidderQuestionStatus(q)} wrap /></Td>
                </tr>
              ))}
            </tbody>
          </Table>
        </>
      )}
    </Card>
  );
}

function AskForm({ solicitationId }: { solicitationId: string }) {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [body, setBody] = useState("");
  const [reference, setReference] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null);
  const hintId = useId();

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setBusy(true);
    setResult(null);
    startTransition(async () => {
      const r = await askQuestion(solicitationId, { body, reference });
      setBusy(false);
      if (r.ok) {
        setBody("");
        setReference("");
        setResult({ ok: true, message: "Question sent. Its answer will be published in an addendum." });
        router.refresh();
      } else {
        setResult({ ok: false, message: r.message });
        router.refresh();
      }
    });
  };

  return (
    <form onSubmit={onSubmit} className="ui-form" data-testid="ask-question">
      <h3>Ask a question</h3>
      <p id={hintId} className="muted">
        Your question is not published. The agency answers it, without your name, in an addendum. A question cannot be
        changed after it is sent; send a new one to correct it.
      </p>
      <Field label="Question" hint={`Up to ${QUESTION_MAX.toLocaleString("en-US")} characters.`}>
        <textarea rows={4} maxLength={QUESTION_MAX} value={body} disabled={busy} required
          onChange={(e) => setBody(e.target.value)} />
      </Field>
      <Field label="Reference (optional)" hint='For example "Item 3" or "Section 02 41 00".'>
        <input type="text" maxLength={REFERENCE_MAX} value={reference} disabled={busy}
          onChange={(e) => setReference(e.target.value)} />
      </Field>
      <div className="ui-actions">
        <Button type="submit" variant="primary" loading={busy} disabled={body.trim() === ""} aria-describedby={hintId}>
          Send question
        </Button>
      </div>
      <div role="status" aria-live="polite">
        {result?.ok ? <Notice tone="success" className="ui-inline-status">{result.message}</Notice> : null}
      </div>
      {result && !result.ok ? <Notice tone="error" role="alert" className="ui-inline-status">{result.message}</Notice> : null}
    </form>
  );
}
