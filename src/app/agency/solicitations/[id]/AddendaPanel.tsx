"use client";

import { startTransition, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { Button, ButtonLink, Card, DateTime, EmptyState, Notice, StatusBadge, Table, Td, Th } from "@/components/ui";
import { startAddendum } from "./addenda/[addendumId]/actions";

export interface AddendumRow {
  id: string;
  number: number;
  /** From solicitation_addenda: after close an unpublished addendum reads withdrawn. */
  effectiveState: string;
  publishedAt: string | null;
}

/** Every addendum of a published solicitation, with "Start addendum" while bidding is open and none is in progress. */
export function AddendaPanel(props: {
  solicitationId: string; rows: AddendumRow[]; tz: string; canStart: boolean; note: string | null;
}) {
  const { solicitationId, rows, tz } = props;
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setError(null);
    setPending(true);
    startTransition(async () => {
      const r = await startAddendum(solicitationId);
      if (r.ok) {
        router.push(`/agency/solicitations/${solicitationId}/addenda/${r.id}`);
      } else {
        setError(r.message);
        setPending(false);
      }
    });
  };

  return (
    <Card as="section" title="Addenda" data-testid="addenda-card">
      {rows.length === 0 ? (
        <EmptyState>No addenda yet.</EmptyState>
      ) : (
        <Table>
          <thead>
            <tr><Th>Addendum</Th><Th>State</Th><Th>Published</Th><Th><span className="visually-hidden">Open</span></Th></tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <Td>Addendum {r.number}</Td>
                <Td><StatusBadge status={{ kind: "addendum", state: r.effectiveState }} /></Td>
                <Td>{r.publishedAt ? <DateTime iso={r.publishedAt} tz={tz} /> : "Not published"}</Td>
                <Td>
                  <ButtonLink href={`/agency/solicitations/${solicitationId}/addenda/${r.id}`}
                    aria-label={`Open Addendum ${r.number} (${r.effectiveState.replace("_", " ")})`}>
                    Open
                  </ButtonLink>
                </Td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
      {props.canStart ? (
        <form onSubmit={onSubmit} className="ui-form">
          <Button type="submit" variant="primary" loading={pending} data-testid="start-addendum">
            {pending ? "Starting..." : "Start addendum"}
          </Button>
          {error ? <Notice tone="error" role="alert" className="ui-inline-status">{error}</Notice> : null}
        </form>
      ) : props.note ? (
        <p className="muted">{props.note}</p>
      ) : null}
    </Card>
  );
}
