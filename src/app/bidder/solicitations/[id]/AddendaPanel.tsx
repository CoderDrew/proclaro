"use client";

import { useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { Card, ConfirmAction, DateTime, Notice, Table, Td, Th } from "@/components/ui";
import { acknowledgeAddendum } from "./actions";

export interface AddendumAckView {
  number: number;
  publishedAt: string | null;
  acknowledgedAt: string | null;
  /** A short-lived signed link to the addendum PDF, or null when it is unavailable. */
  pdfUrl: string | null;
}

/**
 * Every published addendum of the solicitation, with its PDF and this bid's acknowledgment. Acknowledging is final
 * and works for a draft or a submitted bid; it is offered only while bidding is open (the database refuses after).
 */
export function AddendaPanel({ bidId, rows, tz, open }: { bidId: string; rows: AddendumAckView[]; tz: string; open: boolean }) {
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null);
  if (rows.length === 0) return null;
  return (
    <Card as="section" title="Addenda" data-testid="addenda-card">
      <div role="status" aria-live="polite">
        {result?.ok ? <Notice tone="success" className="ui-inline-status">{result.message}</Notice> : null}
      </div>
      {result && !result.ok ? <Notice tone="error" role="alert" className="ui-inline-status">{result.message}</Notice> : null}
      <Table>
        <thead>
          <tr><Th>Addendum</Th><Th>Published</Th><Th>Acknowledgment</Th></tr>
        </thead>
        <tbody>
          {rows.map((a) => (
            <tr key={a.number} data-testid={`addendum-${a.number}`}>
              <Td id={`addendum-${a.number}-name`}>
                {a.pdfUrl ? <a href={a.pdfUrl}>Addendum {a.number} (PDF)</a> : `Addendum ${a.number} (PDF unavailable)`}
              </Td>
              <Td>{a.publishedAt ? <DateTime iso={a.publishedAt} tz={tz} /> : "Unknown"}</Td>
              <Td>
                {a.acknowledgedAt ? (
                  <span data-testid={`acknowledged-${a.number}`}>Acknowledged <DateTime iso={a.acknowledgedAt} tz={tz} /></span>
                ) : open ? (
                  <AcknowledgeForm bidId={bidId} number={a.number} onResult={setResult} />
                ) : (
                  "Not acknowledged"
                )}
              </Td>
            </tr>
          ))}
        </tbody>
      </Table>
    </Card>
  );
}

function AcknowledgeForm(props: { bidId: string; number: number; onResult: (r: { ok: boolean; message: string }) => void }) {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [busy, setBusy] = useState(false);

  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setBusy(true);
    startTransition(async () => {
      const r = await acknowledgeAddendum(props.bidId, props.number);
      props.onResult({ ok: r.ok, message: r.ok ? `Addendum ${props.number} acknowledged.` : r.message });
      setBusy(false);
      if (r.ok) router.refresh();
    });
  };

  return (
    <form onSubmit={onSubmit} className="ui-form">
      <ConfirmAction label={`Acknowledge Addendum ${props.number}`} confirmLabel={`Confirm: acknowledge Addendum ${props.number}`}
        busy={busy} busyLabel="Acknowledging..."
        warning={`Acknowledging is final. It records that your organization received Addendum ${props.number} and took it into account in this bid.`}
        describedBy={`addendum-${props.number}-name`} data-testid={`acknowledge-${props.number}`} />
    </form>
  );
}
