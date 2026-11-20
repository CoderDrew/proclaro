import Link from "next/link";
import { Card, Notice } from "@/components/ui";
import { postedOutcomeLabel } from "@/app/solicitations/status";

const TONE = { accepted: "success", flag_accepted: "success", non_responsive: "error", flag_rejected: "error" } as const;

/**
 * The bidder's own outcome, shown only after the agency's recap or memo is posted (public.my_bid_outcome returns
 * nothing before that). The label is text, and the database's reason text goes with it; colour is only a hint.
 * Under the posted "all bids rejected" memo (memoReason set) an accepted bid reads "All bids rejected" with the memo's
 * reason, never "Accepted"; any other status keeps its own label and reason, with the memo below it.
 */
export function OutcomePanel({ status, reason, number, memoReason }: {
  status: string; reason: string | null; number: string | null; memoReason: string | null;
}) {
  const memo = memoReason !== null;
  const rejectedByMemo = memo && (status === "accepted" || status === "flag_accepted");
  const tone = rejectedByMemo ? "error" : Object.hasOwn(TONE, status) ? TONE[status as keyof typeof TONE] : "info";
  const detail = rejectedByMemo ? memoReason : reason;
  return (
    <Card title="Your bid outcome" data-testid="outcome-panel">
      <Notice tone={tone} data-testid="outcome-status">
        <strong>{postedOutcomeLabel(status, memo)}</strong>
        {detail ? <>: {detail}</> : null}
      </Notice>
      {memo && !rejectedByMemo ? (
        <p data-testid="outcome-memo">All bids rejected: {memoReason}.</p>
      ) : null}
      {number ? (
        <p>
          The posted {memo ? "memo is" : "recap and award are"} on the{" "}
          <Link href={`/solicitations/${number}`}>public page for solicitation {number}</Link>.
        </p>
      ) : null}
    </Card>
  );
}
