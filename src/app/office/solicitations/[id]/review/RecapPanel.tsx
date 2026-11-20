"use client";

import { useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { disagreeRecap, postRecap, postRecapAlone, recallRecap, sendRecapToCheck } from "./actions";
import { blockerMessages, recapCheckControls, recapWords, type RecapKind, type ReviewResult } from "./logic";
import { memoText, type MemoSnapshot, type RecapSnapshot } from "@/domain/recap/snapshot";
import { RecapTable } from "@/components/RecapTable";
import { Button, Card, ConfirmAction, DateTime, Field, Notice } from "@/components/ui";

export type RecapOrMemo = RecapSnapshot | MemoSnapshot;

export interface RecapPanelProps {
  solicitationId: string;
  stage: string;
  tz: string;
  /** bid_review: the live preview (public.preview_recap) and its blocker codes. */
  preview: { recap: RecapOrMemo; blockers: string[] } | null;
  /** bid_review: the checker's comment when the last draft was sent back. */
  returned: { comment: string; at: string } | null;
  /**
   * recap_check: the frozen draft (public.recap_draft), who prepared it, whether this user may check it (not the
   * sender and never reviewed these bids) and whether this user may recall it (the sender, Ruling 13).
   */
  draft: { recap: RecapOrMemo; preparedBy: string | null; canCheck: boolean; canRecall: boolean } | null;
  /** Posted: the public recaps row. */
  posted: { recap: RecapOrMemo; postedAt: string; singleReviewer: boolean } | null;
}

type Action = (prev: ReviewResult | null, fd: FormData) => Promise<ReviewResult>;

function RecapView({ recap }: { recap: RecapOrMemo }) {
  return recap.kind === "recap"
    ? <RecapTable recap={recap} />
    : <p data-testid="recap-memo"><strong>{memoText(recap)}</strong></p>;
}

/**
 * Prepare, check and post the recap (or the "all bids rejected" memo). Both posts are irreversible and public, so they
 * go through ConfirmAction (Ruling 10). Buttons that would always fail for this user are disabled with the reason.
 * The result region lives at panel level and is always rendered, so a success message survives the router.refresh
 * that moves the panel to the next stage.
 */
export function RecapPanel(props: RecapPanelProps) {
  const router = useRouter();
  const [result, setResult] = useState<ReviewResult | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [comment, setComment] = useState("");
  const [, startTransition] = useTransition();

  // Submitted through onSubmit + startTransition (not the form `action` prop), so React's form reset never clears
  // the controlled comment while a refused request keeps what was typed.
  const submit = (name: string, action: Action, onOk?: () => void) => (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    setBusy(name);
    startTransition(async () => {
      const r = await action(null, fd);
      setResult(r);
      setBusy(null);
      if (r.ok) {
        onOk?.();
        router.refresh();
      }
    });
  };

  const { solicitationId, stage, tz } = props;
  const current = props.posted?.recap ?? props.draft?.recap ?? props.preview?.recap ?? null;
  const kind: RecapKind = current?.kind ?? "recap";
  const w = recapWords(kind);
  const title = kind === "all_rejected" ? "All bids rejected memo" : "Recap";

  const hidden = (
    <>
      <input type="hidden" name="solicitationId" value={solicitationId} />
      <input type="hidden" name="kind" value={kind} />
    </>
  );

  let body: React.ReactNode = null;
  if (props.posted) {
    body = (
      <>
        <p data-testid="recap-posted">
          Posted <DateTime iso={props.posted.postedAt} tz={tz} />. The posted {w.noun} is public and cannot change.
          {props.posted.singleReviewer ? " It was posted without a second reviewer (no second reviewer available)." : ""}
        </p>
        <RecapView recap={props.posted.recap} />
      </>
    );
  } else if (stage === "recap_check" && props.draft) {
    const c = recapCheckControls(props.draft.canCheck, props.draft.canRecall, kind, props.draft.preparedBy);
    body = (
      <>
        <p className="muted" id="recap-check-note">{c.note}</p>
        <RecapView recap={props.draft.recap} />
        <form onSubmit={submit("post", postRecap)} className="ui-form">
          {hidden}
          <ConfirmAction label={w.post} confirmLabel={w.postConfirm} warning={w.warning} busy={busy === "post"}
            busyLabel="Posting..." disabled={!c.check} describedBy="recap-check-note" data-testid="recap-post" />
        </form>
        <form onSubmit={submit("disagree", disagreeRecap, () => setComment(""))} className="ui-form">
          {hidden}
          <Field label="Comment" id="recap-disagree-comment"
            hint={`Sends the ${w.noun} back to bid review. The comment is kept on record.`}>
            <textarea name="comment" rows={2} value={comment} onChange={(e) => setComment(e.target.value)}
              disabled={!c.check} />
          </Field>
          <Button type="submit" disabled={!c.check} loading={busy === "disagree"} data-testid="recap-disagree"
            aria-describedby="recap-check-note">
            {busy === "disagree" ? "Sending..." : w.disagree}
          </Button>
        </form>
        {c.recall ? (
          <form onSubmit={submit("recall", recallRecap)} className="ui-form">
            {hidden}
            <Button type="submit" loading={busy === "recall"} data-testid="recap-recall"
              aria-describedby="recap-check-note">
              {busy === "recall" ? "Recalling..." : w.recall}
            </Button>
          </form>
        ) : null}
      </>
    );
  } else if (stage === "bid_review" && props.preview) {
    const blockers = blockerMessages(props.preview.blockers);
    const off = blockers.length > 0;
    body = (
      <>
        {props.returned ? (
          <Notice tone="info" title="Sent back by the checker" data-testid="recap-returned">
            {" "}<DateTime iso={props.returned.at} tz={tz} />: {props.returned.comment}
          </Notice>
        ) : null}
        <p className="muted">
          Preview: this is what the {w.noun} would show now. It is computed from the sealed bid prices and is not
          public until it is posted.
        </p>
        <RecapView recap={props.preview.recap} />
        {off ? (
          <Notice tone="warning" title="Before you can send it" data-testid="recap-blockers">
            <ul>{blockers.map((b) => <li key={b}>{b}</li>)}</ul>
          </Notice>
        ) : null}
        <p className="muted" id="recap-send-note">
          {off
            ? "Resolve the items above first."
            : `Send the ${w.noun} to a second office user to check. Post alone only when no second reviewer is available; that is recorded.`}
        </p>
        <form onSubmit={submit("send", sendRecapToCheck)} className="ui-form">
          {hidden}
          <Button type="submit" variant="primary" disabled={off} loading={busy === "send"} data-testid="recap-send"
            aria-describedby="recap-send-note">
            {busy === "send" ? "Sending..." : w.send}
          </Button>
        </form>
        <form onSubmit={submit("alone", postRecapAlone)} className="ui-form">
          {hidden}
          <ConfirmAction label={w.alone} confirmLabel={w.aloneConfirm} warning={w.warning} variant="secondary"
            busy={busy === "alone"} busyLabel="Posting..." disabled={off} describedBy="recap-send-note"
            data-testid="recap-alone" />
        </form>
      </>
    );
  } else {
    body = <p className="muted">The {w.noun} is not available at this stage. Reload the page.</p>;
  }

  return (
    <Card as="section" title={title} data-testid="recap-panel">
      <div role="status" aria-live="polite">
        {result?.ok ? <Notice tone="success" className="ui-inline-status">{result.message}</Notice> : null}
      </div>
      {result && !result.ok ? (
        <Notice tone="error" role="alert" className="ui-inline-status">{result.message}</Notice>
      ) : null}
      {body}
    </Card>
  );
}
