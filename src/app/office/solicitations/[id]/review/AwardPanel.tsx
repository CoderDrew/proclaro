"use client";

import { useState, useTransition, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { disagreeAward, postAward, postAwardAlone, recallAward, sendAwardToCheck } from "./actions";
import { AWARD_WORDS, awardControls, type ReviewResult } from "./logic";
import type { AwardSnapshot } from "@/domain/recap/snapshot";
import { AwardSummary } from "@/components/AwardSummary";
import { Button, Card, ConfirmAction, DateTime, Field, Notice } from "@/components/ui";

export interface AwardPanelProps {
  solicitationId: string;
  stage: string;
  tz: string;
  /** The agency's current choice (public.current_award_pick). */
  pick: { reference: string; reason: string | null; pickedAt: string; differsFromExpected: boolean } | null;
  /** award_check: who sent it and whether the caller may check it (public.award_check_info). */
  check: { preparedBy: string | null; canCheck: boolean; needsNewPick: boolean } | null;
  /** recap_posted: the checker's comment when the last award was sent back. */
  returned: { comment: string; at: string } | null;
  /** Posted: the public awards row. */
  award: { award: AwardSnapshot; postedAt: string; singleReviewer: boolean } | null;
}

type Action = (prev: ReviewResult | null, fd: FormData) => Promise<ReviewResult>;

/**
 * Send the agency's award choice to check, post it (two-person check) or post it alone. Posting is irreversible and
 * public, so both post buttons go through ConfirmAction. The result region is always rendered, so a success message
 * survives the router.refresh that moves the panel to the next stage.
 */
export function AwardPanel(props: AwardPanelProps) {
  const router = useRouter();
  const [result, setResult] = useState<ReviewResult | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [comment, setComment] = useState("");
  const [, startTransition] = useTransition();

  // onSubmit + startTransition (not the form `action` prop), so React's form reset never clears the controlled
  // comment while a refused request keeps what was typed.
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

  const { solicitationId, stage, tz, pick } = props;
  const controls = awardControls(stage, pick !== null, props.check?.canCheck ?? false, props.check?.needsNewPick ?? false);
  const hidden = <input type="hidden" name="solicitationId" value={solicitationId} />;

  const pickView = pick ? (
    <div className="ui-stack-tight" data-testid="award-pick">
      <p>
        The agency chose bid <strong>{pick.reference}</strong> (<DateTime iso={pick.pickedAt} tz={tz} />).
      </p>
      {pick.differsFromExpected ? <p data-testid="award-differs"><strong>{AWARD_WORDS.differs}</strong>.</p> : null}
      {pick.reason ? <p>Agency&apos;s reason: {pick.reason}</p> : null}
    </div>
  ) : null;

  let body: React.ReactNode;
  if (props.award) {
    body = (
      <AwardSummary award={props.award.award} postedAt={props.award.postedAt}
        singleReviewer={props.award.singleReviewer} tz={tz} />
    );
  } else if (stage === "award_check") {
    body = (
      <>
        <p className="muted">Sent to check by {props.check?.preparedBy ?? "another office user"}.</p>
        {pickView}
        <p className="muted" id="award-check-note">{controls.note}</p>
        <form onSubmit={submit("post", postAward)} className="ui-form">
          {hidden}
          <ConfirmAction label={AWARD_WORDS.post} confirmLabel={AWARD_WORDS.postConfirm} warning={AWARD_WORDS.warning}
            busy={busy === "post"} busyLabel="Posting..." disabled={!controls.check} describedBy="award-check-note"
            data-testid="award-post" />
        </form>
        <form onSubmit={submit("disagree", disagreeAward, () => setComment(""))} className="ui-form">
          {hidden}
          <Field label="Comment" id="award-disagree-comment"
            hint="Sends the award back so the agency can change its choice. The comment is kept on record.">
            <textarea name="comment" rows={2} value={comment} onChange={(e) => setComment(e.target.value)}
              disabled={!controls.check} />
          </Field>
          <Button type="submit" disabled={!controls.check} loading={busy === "disagree"} data-testid="award-disagree"
            aria-describedby="award-check-note">
            {busy === "disagree" ? "Sending..." : AWARD_WORDS.disagree}
          </Button>
        </form>
        {controls.recall ? (
          <form onSubmit={submit("recall", recallAward)} className="ui-form">
            {hidden}
            <Button type="submit" loading={busy === "recall"} data-testid="award-recall" aria-describedby="award-check-note">
              {busy === "recall" ? "Recalling..." : AWARD_WORDS.recall}
            </Button>
          </form>
        ) : null}
      </>
    );
  } else if (stage === "recap_posted") {
    body = (
      <>
        {props.returned ? (
          <Notice tone="info" title="Sent back by the checker" data-testid="award-returned">
            {" "}<DateTime iso={props.returned.at} tz={tz} />: {props.returned.comment}
          </Notice>
        ) : null}
        {pickView}
        <p className="muted" id="award-send-note">{controls.note}</p>
        <form onSubmit={submit("send", sendAwardToCheck)} className="ui-form">
          {hidden}
          <Button type="submit" variant="primary" disabled={!controls.send} loading={busy === "send"}
            aria-describedby="award-send-note" data-testid="award-send">
            {busy === "send" ? "Sending..." : AWARD_WORDS.send}
          </Button>
        </form>
        <form onSubmit={submit("alone", postAwardAlone)} className="ui-form">
          {hidden}
          <ConfirmAction label={AWARD_WORDS.alone} confirmLabel={AWARD_WORDS.aloneConfirm} warning={AWARD_WORDS.warning}
            variant="secondary" busy={busy === "alone"} busyLabel="Posting..." disabled={!controls.alone}
            describedBy="award-send-note" data-testid="award-alone" />
        </form>
      </>
    );
  } else {
    body = <p className="muted">{controls.note} Reload the page.</p>;
  }

  return (
    <Card as="section" title="Award" data-testid="award-panel">
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
