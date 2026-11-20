"use client";

import { startTransition, useActionState, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { decideFlagged } from "./actions";
import { DECISION_LABELS, DECISIONS, decisionStatus, rowLabel, type FlagDecision, type FlaggedResult } from "./logic";
import { Button, Card, Choice, DateTime, EmptyState, Field, Money, Notice, StatusBadge } from "@/components/ui";

export interface FlaggedBidView {
  outcomeId: string;
  reference: string;
  note: string;
  baseTotalCents: number;
  decision: FlagDecision | null;
  decisionReason: string | null;
  decidedAt: string | null;
}

/**
 * The polite live region is always rendered (empty until a save), so screen readers announce the success text when
 * it appears. A refusal is an alert, which is announced on insertion.
 */
function Result({ state }: { state: FlaggedResult | null }) {
  return (
    <>
      <div role="status" aria-live="polite">
        {state?.ok ? <Notice tone="success" className="ui-inline-status">{state.message}</Notice> : null}
      </div>
      {state && !state.ok ? (
        <Notice tone="error" role="alert" className="ui-inline-status">{state.message}</Notice>
      ) : null}
    </>
  );
}

/** The agency's list of flagged bids: reference, the reviewer's note, the base total and its decision. */
export function FlaggedPanel(props: { bids: FlaggedBidView[]; tz: string; canDecide: boolean; closedNote: string | null }) {
  const { bids, tz } = props;
  return (
    <Card as="section" title="Flagged bids">
      {bids.length === 0 ? (
        <EmptyState data-testid="flagged-empty">No flagged bids need a decision.</EmptyState>
      ) : (
        <div className="ui-stack">
          {props.closedNote ? <p className="muted">{props.closedNote}</p> : null}
          {bids.map((b) => <DecisionForm key={b.outcomeId} bid={b} tz={tz} enabled={props.canDecide} />)}
        </div>
      )}
    </Card>
  );
}

function DecisionForm({ bid, tz, enabled }: { bid: FlaggedBidView; tz: string; enabled: boolean }) {
  const router = useRouter();
  // Controlled, so a refused save keeps what was typed (React resets uncontrolled fields after a form action).
  const [decision, setDecision] = useState<string>(bid.decision ?? "");
  const [reason, setReason] = useState("");
  const [state, run, pending] = useActionState(async (prev: FlaggedResult | null, fd: FormData) => {
    const r = await decideFlagged(prev, fd);
    if (r.ok) {
      setReason("");
      router.refresh();
    }
    return r;
  }, null);
  const off = !enabled;
  const id = `flag-${bid.outcomeId}`;
  // Submitted through onSubmit, not the form `action` prop: React resets a form after an action, which would uncheck
  // the controlled radios in the DOM while the state still says they are checked.
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    startTransition(() => run(fd));
  };

  return (
    <form onSubmit={onSubmit} className="ui-form" data-testid={`flagged-${bid.reference}`}>
      <input type="hidden" name="outcomeId" value={bid.outcomeId} />
      <h3>Bid {bid.reference}</h3>
      <p>
        <StatusBadge status={{ kind: "review", status: decisionStatus(bid.decision) }} wrap />
        {bid.decision && bid.decisionReason ? <>: {bid.decisionReason}</> : null}
        {bid.decidedAt ? <> (<DateTime iso={bid.decidedAt} tz={tz} />)</> : null}
      </p>
      <p>Base total: <Money cents={bid.baseTotalCents} /></p>
      <p>Reviewer&apos;s note: {bid.note}</p>
      <fieldset className="ui-fieldset" disabled={off}>
        <legend>Decision<span className="visually-hidden"> for bid {bid.reference}</span></legend>
        {DECISIONS.map((d) => (
          <Choice key={d} label={DECISION_LABELS[d]}>
            <input type="radio" name="decision" value={d} checked={decision === d} disabled={off}
              onChange={() => setDecision(d)} />
          </Choice>
        ))}
      </fieldset>
      <Field label="Reason" id={`${id}-reason`}
        hint={bid.decision ? "A new decision replaces the current one; both are kept on record." : undefined}>
        <textarea name="reason" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} disabled={off} />
      </Field>
      <Button type="submit" variant="primary" disabled={off} loading={pending} aria-label={rowLabel(bid.reference)}>
        {pending ? "Saving..." : "Save decision"}
      </Button>
      <Result state={state} />
    </form>
  );
}
