import type { AwardSnapshot } from "@/domain/recap/snapshot";
import { DateTime, Money } from "@/components/ui";

/**
 * The posted award (public.awards snapshot). The amount is the recap row's total with the selected alternates, computed
 * in Postgres; nothing is recomputed here. The pick reason is not part of the public award.
 */
export function AwardSummary(props: { award: AwardSnapshot; postedAt: string; singleReviewer: boolean; tz: string }) {
  const { award } = props;
  const selected = award.selectedAlternates
    .map((n) => `Alternate ${n}${award.alternates[n - 1] ? ` (${award.alternates[n - 1].description})` : ""}`);
  return (
    <div className="ui-stack-tight" data-testid="award-summary">
      <p>
        <strong>Awarded to {award.bidderName}</strong> (bid {award.reference}) for <Money cents={award.amountCents} />.
      </p>
      <p>{selected.length === 0 ? "No alternate is included." : `Includes ${selected.join(", ")}.`}</p>
      {award.differsFromExpected ? (
        <p data-testid="award-differs">Differs from the expected award in the recap.</p>
      ) : null}
      <p className="muted">
        Posted <DateTime iso={props.postedAt} tz={props.tz} />. The award is public and cannot change.
        {props.singleReviewer ? " It was posted without a second reviewer (no second reviewer available)." : ""}
      </p>
    </div>
  );
}
