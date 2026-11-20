"use client";

import { startTransition, useActionState, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { sendFlags, setOutcome, verifyResident } from "./actions";
import {
  GROUND_LABELS, GROUNDS, OUTCOME_LABELS, OUTCOMES, apprenticeLabel, rowLabel,
  type BidOutcome, type NonResponsiveGround, type ReviewResult,
} from "./logic";
import {
  Button, Card, Choice, DateTime, EmptyState, Field, Money, Notice, StatusBadge, Table, Td, Th,
} from "@/components/ui";

export interface ReviewRowView {
  bidId: string;
  /** The current outcome row, or null before any outcome. */
  outcomeId: string | null;
  reference: string;
  version: number;
  bidderName: string;
  baseTotalCents: number;
  apprentice: boolean | null;
  status: string;
  statusReason: string | null;
  cure: { label: string; dueAt: string | null } | null;
  outcome: BidOutcome | null;
  ground: NonResponsiveGround | null;
  note: string | null;
  editable: boolean;
  /** Why the form is disabled, or what a save means now (pending cure). */
  formNote: string | null;
}

export interface ClaimView {
  bidId: string;
  reference: string;
  bidderName: string;
  certificate: string;
  verified: boolean | null;
  note: string | null;
  verifiedAt: string | null;
}

/**
 * Wraps a (prev, formData) server action so a successful save clears the typed note and re-reads the page. The
 * form stays mounted across the refresh (keyed by bid only), so its result message survives and is announced.
 * Returns [state, onSubmit, pending]: forms submit through onSubmit + startTransition, not the form `action` prop,
 * because React resets a form after an action, which would leave the controlled radios looking unchecked after a
 * successful save (the bug Task 7 found on the agency form).
 */
function useReviewAction(
  action: (prev: ReviewResult | null, fd: FormData) => Promise<ReviewResult>, onOk: () => void,
) {
  const router = useRouter();
  const [state, run, pending] = useActionState(async (prev: ReviewResult | null, fd: FormData) => {
    const r = await action(prev, fd);
    if (r.ok) {
      onOk();
      router.refresh();
    }
    return r;
  }, null);
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    startTransition(() => run(fd));
  };
  return [state, onSubmit, pending] as const;
}

/**
 * The polite live region is always rendered (empty until a save), so screen readers announce the success text when
 * it appears. A refusal is an alert, which is announced on insertion.
 */
function Result({ state }: { state: ReviewResult | null }) {
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

export interface SendFlagsView {
  solicitationId: string;
  enabled: boolean;
  /** Why the button is disabled, or when the flags were sent. */
  note: string;
}

export function ReviewTable(props: {
  rows: ReviewRowView[]; claims: ClaimView[]; tz: string; canVerify: boolean; sendFlags: SendFlagsView;
}) {
  const { rows, claims, tz } = props;
  return (
    <>
      <SendFlagsForm view={props.sendFlags} />
      <Card as="section" title="Bids">
        {rows.length === 0 ? (
          <EmptyState>No bids were opened.</EmptyState>
        ) : (
          <Table data-testid="review-table">
            <thead>
              <tr>
                <Th>Reference</Th><Th>Bidder</Th><Th numeric>Base total</Th><Th>Apprentice commitment</Th>
                <Th>Status</Th><Th>Bid bond cure</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.bidId} data-testid={`review-${r.reference}`}>
                  <Td>{r.reference}</Td>
                  <Td>{r.bidderName}</Td>
                  <Td numeric><Money cents={r.baseTotalCents} /></Td>
                  <Td>{apprenticeLabel(r.apprentice)}</Td>
                  <Td>
                    <StatusBadge status={{ kind: "review", status: r.status }} wrap />
                    {r.statusReason ? <>: {r.statusReason}</> : null}
                  </Td>
                  <Td>
                    {r.cure ? (
                      <>
                        {r.cure.label}
                        {r.cure.dueAt ? <>; due <DateTime iso={r.cure.dueAt} tz={tz} /></> : null}
                      </>
                    ) : "Not needed"}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>

      {rows.map((r) => <OutcomeForm key={r.bidId} row={r} />)}

      <Card as="section" title="Resident certificates">
        {claims.length === 0 ? (
          <EmptyState>No bidder claimed resident status.</EmptyState>
        ) : (
          <div className="ui-stack">
            {claims.map((c) => (
              <VerifyForm key={c.bidId} claim={c} tz={tz} enabled={props.canVerify} />
            ))}
          </div>
        )}
      </Card>
    </>
  );
}

function OutcomeForm({ row }: { row: ReviewRowView }) {
  // Controlled, so a refused save keeps what was typed. After a save the choice already matches the new current
  // outcome; only the note is cleared.
  const [outcome, setOutcomeChoice] = useState<string>(row.outcome ?? "");
  const [ground, setGround] = useState<string>(row.ground ?? "");
  const [note, setNote] = useState("");
  const [state, onSubmit, pending] = useReviewAction(setOutcome, () => setNote(""));
  const off = !row.editable;
  const id = `outcome-${row.bidId}`;

  return (
    <Card as="section" title={`Bid ${row.reference}: ${row.bidderName}`} data-testid={`outcome-${row.reference}`}>
      <p>
        <StatusBadge status={{ kind: "review", status: row.status }} wrap />
        {row.statusReason ? <>: {row.statusReason}</> : null}
      </p>
      {row.note && row.status !== "flagged" ? <p className="muted">Last note: {row.note}</p> : null}
      {row.formNote ? <p className="muted" id={`${id}-note-text`}>{row.formNote}</p> : null}
      <form onSubmit={onSubmit} className="ui-form">
        <input type="hidden" name="bidId" value={row.bidId} />
        <fieldset className="ui-fieldset" disabled={off}>
          <legend>Outcome<span className="visually-hidden"> for bid {row.reference}</span></legend>
          {OUTCOMES.map((o) => (
            <Choice key={o} label={OUTCOME_LABELS[o]}>
              <input type="radio" name="outcome" value={o} checked={outcome === o} disabled={off}
                onChange={() => setOutcomeChoice(o)} />
            </Choice>
          ))}
        </fieldset>
        <Field label="Non-responsive reason" id={`${id}-ground`}
          hint={outcome === "non_responsive" ? undefined : "Only for a non-responsive outcome."}>
          <select name="ground" value={ground} onChange={(e) => setGround(e.target.value)}
            disabled={off || outcome !== "non_responsive"}>
            <option value="">Choose a reason</option>
            {GROUNDS.map((g) => <option key={g} value={g}>{GROUND_LABELS[g]}</option>)}
          </select>
        </Field>
        <Field label="Reason or note" id={`${id}-note`}
          hint={outcome === "accepted_flagged" ? "The agency sees this note with the flagged bid." : undefined}>
          <textarea name="note" rows={2} value={note} onChange={(e) => setNote(e.target.value)} disabled={off} />
        </Field>
        <Button type="submit" variant="primary" disabled={off} loading={pending}
          aria-label={rowLabel("saveOutcome", row.reference)}
          aria-describedby={row.formNote ? `${id}-note-text` : undefined}>
          {pending ? "Saving..." : "Save outcome"}
        </Button>
        <Result state={state} />
      </form>
    </Card>
  );
}

function VerifyForm({ claim, tz, enabled }: { claim: ClaimView; tz: string; enabled: boolean }) {
  const [verified, setVerified] = useState<string>(claim.verified === null ? "" : String(claim.verified));
  const [note, setNote] = useState("");
  const [state, onSubmit, pending] = useReviewAction(verifyResident, () => setNote(""));
  const off = !enabled;
  const id = `resident-${claim.bidId}`;
  const finding = claim.verified === null ? "Not checked yet" : claim.verified ? "Verified" : "Not verified";

  return (
    <form onSubmit={onSubmit} className="ui-form" data-testid={`resident-${claim.reference}`}>
      <input type="hidden" name="bidId" value={claim.bidId} />
      <p>
        <strong>Bid {claim.reference}{claim.bidderName ? `, ${claim.bidderName}` : ""}</strong>: certificate {claim.certificate || "(none given)"}. Finding: {finding}
        {claim.verifiedAt ? <> (<DateTime iso={claim.verifiedAt} tz={tz} />)</> : null}
        {claim.note ? <>. Note: {claim.note}</> : null}
      </p>
      <fieldset className="ui-fieldset" disabled={off}>
        <legend>Certificate finding<span className="visually-hidden"> for bid {claim.reference}</span></legend>
        <Choice label="Verified">
          <input type="radio" name="verified" value="true" checked={verified === "true"} disabled={off}
            onChange={() => setVerified("true")} />
        </Choice>
        <Choice label="Not verified">
          <input type="radio" name="verified" value="false" checked={verified === "false"} disabled={off}
            onChange={() => setVerified("false")} />
        </Choice>
      </fieldset>
      <Field label="Reason or note" id={`${id}-note`}>
        <textarea name="note" rows={2} value={note} onChange={(e) => setNote(e.target.value)} disabled={off} />
      </Field>
      <Button type="submit" disabled={off} loading={pending} aria-label={rowLabel("saveFinding", claim.reference)}>
        {pending ? "Saving..." : "Save finding"}
      </Button>
      <Result state={state} />
    </form>
  );
}

function SendFlagsForm({ view }: { view: SendFlagsView }) {
  const [state, onSubmit, pending] = useReviewAction(sendFlags, () => {});
  const off = !view.enabled;
  return (
    <Card as="section" title="Agency decisions" data-testid="send-flags">
      <p className="muted" id="send-flags-note">{view.note}</p>
      <form onSubmit={onSubmit} className="ui-form">
        <input type="hidden" name="solicitationId" value={view.solicitationId} />
        <Button type="submit" variant="primary" disabled={off} loading={pending} aria-describedby="send-flags-note">
          {pending ? "Sending..." : "Send flagged bids to the agency"}
        </Button>
        <Result state={state} />
      </form>
    </Card>
  );
}
