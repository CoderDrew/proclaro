"use client";

import { useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { pickAward } from "./actions";
import { pickReasonRule, type PickResult } from "./logic";
import type { AwardSnapshot, RecapSnapshot } from "@/domain/recap/snapshot";
import { RecapTable } from "@/components/RecapTable";
import { AwardSummary } from "@/components/AwardSummary";
import { Button, Card, Choice, DateTime, Field, Money, Notice } from "@/components/ui";

export interface CurrentPickView {
  bidId: string;
  reference: string;
  reason: string | null;
  pickedAt: string;
  differsFromExpected: boolean;
}

export interface AwardPickPanelProps {
  solicitationId: string;
  tz: string;
  /** The posted recap (public.recaps, kind recap). */
  recap: RecapSnapshot;
  /** True only in recap_posted: the office has not sent the award to check. */
  canPick: boolean;
  /** Why the choice cannot be changed now, shown with the disabled controls. */
  closedNote: string | null;
  pick: CurrentPickView | null;
  award: { award: AwardSnapshot; postedAt: string; singleReviewer: boolean } | null;
}

const REASON_HINT = {
  tied: "Required: two or more bids are tied at rank 1, so explain the choice between them.",
  differs: "Required: this bid is not the expected award in the recap, so explain why it was chosen.",
  none: "Optional: the expected award needs no explanation.",
} as const;

/**
 * The agency's award choice from the posted recap: one Choice per recap row with the expected winner (or the current
 * choice) preselected, and a reason that is required when the choice is not the expected winner or rank 1 is tied.
 * The result region is always rendered so the success text survives router.refresh.
 */
export function AwardPickPanel(props: AwardPickPanelProps) {
  const { recap, tz } = props;
  const router = useRouter();
  const [bidId, setBidId] = useState<string>(props.pick?.bidId ?? recap.expectedWinnerBidId ?? "");
  const [reason, setReason] = useState("");
  const [result, setResult] = useState<PickResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [, startTransition] = useTransition();

  // onSubmit + startTransition (not the form `action` prop): React's form reset would clear the controlled radios
  // and reason in the DOM after an action.
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    setBusy(true);
    startTransition(async () => {
      const r = await pickAward(null, fd);
      setResult(r);
      setBusy(false);
      if (r.ok) {
        setReason("");
        router.refresh();
      }
    });
  };

  const off = !props.canPick;
  const rule = bidId ? pickReasonRule(recap, bidId) : recap.expectedWinnerBidId === null ? "tied" : null;
  const required = rule !== null;

  return (
    <Card as="section" title="Award" data-testid="award-pick-panel">
      <div role="status" aria-live="polite">
        {result?.ok ? <Notice tone="success" className="ui-inline-status">{result.message}</Notice> : null}
      </div>
      {result && !result.ok ? (
        <Notice tone="error" role="alert" className="ui-inline-status">{result.message}</Notice>
      ) : null}

      {props.award ? (
        <AwardSummary award={props.award.award} postedAt={props.award.postedAt}
          singleReviewer={props.award.singleReviewer} tz={tz} />
      ) : null}

      <h3>Posted bid recap</h3>
      <RecapTable recap={recap} />

      {props.pick ? (
        <p data-testid="award-current-pick">
          Your current choice: bid {props.pick.reference} (<DateTime iso={props.pick.pickedAt} tz={tz} />).
          {props.pick.differsFromExpected ? " Differs from the expected award." : ""}
          {props.pick.reason ? ` Reason: ${props.pick.reason}` : ""}
        </p>
      ) : null}

      {props.award ? null : (
        <form onSubmit={onSubmit} className="ui-form" data-testid="award-pick-form">
          <input type="hidden" name="solicitationId" value={props.solicitationId} />
          {props.closedNote ? <p className="muted" id="award-pick-closed">{props.closedNote}</p> : null}
          <fieldset className="ui-fieldset" disabled={off}>
            <legend>Bid to award</legend>
            {recap.rows.map((r) => (
              <Choice key={r.bidId} data-testid={`award-choice-${r.reference}`} label={
                <>
                  Bid {r.reference}: {r.bidderName}, rank {r.rank}{r.tied ? " (tied)" : ""},{" "}
                  <Money cents={r.totalCents} />
                  {recap.expectedWinnerBidId === r.bidId ? " (expected award)" : ""}
                </>
              }>
                <input type="radio" name="bidId" value={r.bidId} checked={bidId === r.bidId} disabled={off}
                  onChange={() => setBidId(r.bidId)} />
              </Choice>
            ))}
          </fieldset>
          <Field label={required ? "Reason (required)" : "Reason (optional)"} id="award-pick-reason"
            hint={rule === "tied" ? REASON_HINT.tied : rule === "differs" ? REASON_HINT.differs : REASON_HINT.none}>
            <textarea name="reason" rows={2} value={reason} onChange={(e) => setReason(e.target.value)}
              disabled={off} aria-required={required} />
          </Field>
          <Button type="submit" variant="primary" disabled={off} loading={busy} data-testid="award-pick-submit"
            aria-describedby={off && props.closedNote ? "award-pick-closed" : undefined}>
            {busy ? "Saving..." : "Record award choice"}
          </Button>
        </form>
      )}
    </Card>
  );
}
