"use client";

import { useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { Card, ConfirmAction, DateTime, EmptyState, Notice, Table, Td, Th } from "@/components/ui";
import { closeQuestion } from "./addenda/[addendumId]/actions";
import { officeQuestionStatus, type CloseReason } from "./addenda/[addendumId]/logic";

/** One row of public.office_questions: office staff see the asker and the organization. */
export interface OfficeQuestion {
  id: string;
  body: string;
  reference: string;
  askedAt: string;
  status: string;
  answeredInNumber: number | null;
  closeReason: string | null;
  orgName: string;
  askerName: string;
}

/** Every question on the solicitation, with who asked it, and a Close action for open questions. */
export function QuestionsPanel({ questions, tz }: { questions: OfficeQuestion[]; tz: string }) {
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null);
  return (
    <Card as="section" title="Questions" data-testid="questions-card">
      <div role="status" aria-live="polite">
        {result?.ok ? <Notice tone="success" className="ui-inline-status">{result.message}</Notice> : null}
      </div>
      {result && !result.ok ? <Notice tone="error" role="alert" className="ui-inline-status">{result.message}</Notice> : null}
      {questions.length === 0 ? (
        <EmptyState>No questions yet.</EmptyState>
      ) : (
        <>
          <p className="muted">
            Only office staff see who asked. The agency sees the questions without names, and answers them in an
            addendum.
          </p>
          <Table>
            <thead>
              <tr><Th>#</Th><Th>Asked</Th><Th>Organization</Th><Th>Asked by</Th><Th>Reference</Th><Th>Question</Th>
                <Th>Status</Th><Th><span className="visually-hidden">Close</span></Th></tr>
            </thead>
            <tbody>
              {questions.map((q, i) => (
                <tr key={q.id} data-testid="office-question">
                  <Td>{i + 1}</Td>
                  <Td><DateTime iso={q.askedAt} tz={tz} /></Td>
                  <Td>{q.orgName}</Td>
                  <Td>{q.askerName}</Td>
                  <Td>{q.reference || "None"}</Td>
                  <Td className="ui-prewrap" id={`question-${q.id}-body`}>{q.body}</Td>
                  <Td>{officeQuestionStatus(q)}</Td>
                  <Td>
                    {q.status === "open"
                      ? <CloseQuestionForm id={q.id} position={i + 1} onResult={setResult} />
                      : null}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        </>
      )}
    </Card>
  );
}

function CloseQuestionForm(props: {
  id: string; position: number; onResult: (r: { ok: boolean; message: string }) => void;
}) {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [reason, setReason] = useState<CloseReason | "">("");
  const [busy, setBusy] = useState(false);

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (reason === "") return;
    setBusy(true);
    startTransition(async () => {
      const r = await closeQuestion(props.id, reason);
      props.onResult({ ok: r.ok, message: r.ok ? `Question ${props.position} closed.` : r.message });
      setBusy(false);
      if (r.ok) router.refresh();
    });
  };

  return (
    <form onSubmit={onSubmit} className="ui-form">
      <select aria-label={`Reason to close question ${props.position}`} value={reason} disabled={busy}
        onChange={(e) => setReason(e.target.value as CloseReason | "")}>
        <option value="">Choose a reason...</option>
        <option value="duplicate">Duplicate</option>
        <option value="out_of_scope">Out of scope</option>
      </select>
      <ConfirmAction label={`Close question ${props.position}`} confirmLabel={`Confirm: close question ${props.position}`}
        variant="danger" disabled={reason === ""} busy={busy} busyLabel="Closing..."
        warning={`Closing is final. The asker sees it as closed (${reason === "out_of_scope" ? "out of scope" : "duplicate"}), and it can no longer be answered in an addendum.`}
        describedBy={`question-${props.id}-body`} data-testid={`close-question-${props.position}`} />
    </form>
  );
}
