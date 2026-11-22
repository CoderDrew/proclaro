import { Card, DateTime, EmptyState, Table, Td, Th } from "@/components/ui";

/** One row of public.agency_questions: never the asker or the organization. */
export interface AgencyQuestion {
  id: string;
  body: string;
  reference: string;
  askedAt: string;
  status: string;
  answeredInNumber: number | null;
  inDraft: boolean;
}

export function questionStatusText(q: Pick<AgencyQuestion, "status" | "answeredInNumber" | "inDraft">): string {
  if (q.status === "answered") return q.answeredInNumber ? `Answered in Addendum ${q.answeredInNumber}` : "Answered";
  if (q.status === "closed") return "Closed by the office";
  return q.inDraft ? "Open (answered in the addendum in progress)" : "Open";
}

/** The bidders' questions on this solicitation, without identities. Answers go out through an addendum. */
export function QuestionsPanel({ questions, tz }: { questions: AgencyQuestion[]; tz: string }) {
  return (
    <Card as="section" title="Questions" data-testid="questions-card">
      {questions.length === 0 ? (
        <EmptyState>No questions yet.</EmptyState>
      ) : (
        <>
          <p className="muted">Bidders&apos; names are not shown. Answer open questions in an addendum.</p>
          <Table>
            <thead>
              <tr><Th>Asked</Th><Th>Reference</Th><Th>Question</Th><Th>Status</Th></tr>
            </thead>
            <tbody>
              {questions.map((q) => (
                <tr key={q.id}>
                  <Td><DateTime iso={q.askedAt} tz={tz} /></Td>
                  <Td>{q.reference || "None"}</Td>
                  <Td className="ui-prewrap">{q.body}</Td>
                  <Td>{questionStatusText(q)}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        </>
      )}
    </Card>
  );
}
