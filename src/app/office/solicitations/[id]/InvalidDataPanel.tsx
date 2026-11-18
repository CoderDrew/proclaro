"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { returnToAgency, startReview } from "./actions";
import { INVALID_STORED_DATA, type ActionResult } from "./logic";
import type { AuditRow } from "./ReviewPanel";
import { Button, Card, EmptyState, Field, Notice } from "@/components/ui";

/**
 * Shown instead of the review form when the stored data does not match the schema. Nothing can be edited,
 * checked or published; the only way forward is returning it to the agency (starting the review first if needed).
 */
export function InvalidDataPanel(props: {
  id: string;
  state: string;
  canWork: boolean;
  isReviewer: boolean;
  agencyName: string;
  audit: AuditRow[];
}) {
  const { id, state } = props;
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [comment, setComment] = useState("");

  async function act(fn: () => Promise<ActionResult>) {
    setBusy(true);
    setMessage(null);
    try {
      const r = await fn();
      if (r.ok) router.refresh();
      else setMessage(r.message);
    } catch {
      setMessage("Something went wrong. Reload the page and try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card as="section">
      <Notice tone="error" role="alert">{INVALID_STORED_DATA}</Notice>
      <p className="ui-office-note">{props.agencyName}</p>
      {message && <Notice tone="error" role="alert">{message}</Notice>}

      {props.canWork && state === "submitted" && (
        <p><Button type="button" variant="primary" disabled={busy} onClick={() => void act(() => startReview(id))}>Start review</Button></p>
      )}
      {props.canWork && state === "in_review" && props.isReviewer && (
        <>
          <Field label="Comment to the agency">
            <textarea value={comment} onChange={(e) => setComment(e.target.value)} />
          </Field>
          <p>
            <Button type="button" variant="danger" disabled={busy}
              onClick={() => void act(() => returnToAgency(id, [{ field: null, body: comment }]))}>Return</Button>
          </p>
        </>
      )}
      {props.canWork && state === "in_review" && !props.isReviewer && (
        <p>Only the assigned reviewer can return this solicitation.</p>
      )}

      <h2 className="ui-card-title">History</h2>
      {props.audit.length === 0 ? <EmptyState>No history yet.</EmptyState> : (
        <ul className="ui-timeline">
          {props.audit.map((a) => (
            <li key={a.id}><strong>{a.action}</strong> by {a.actor}, {a.when}{a.reason && <div>{a.reason}</div>}</li>
          ))}
        </ul>
      )}
    </Card>
  );
}
