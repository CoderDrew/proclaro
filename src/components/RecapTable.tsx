import { recapColumns, type RecapSnapshot } from "@/domain/recap/snapshot";
import { Money, Notice, Table, Td, Th } from "@/components/ui";

/** The rank cell: competition rank, with "tied" when another bid has the same evaluated key. */
function rankLabel(rank: number, tied: boolean): string {
  return tied ? `${rank} (tied)` : String(rank);
}

/**
 * The recap as computed in Postgres (app.build_recap). Every amount is Money of the snapshot's sealed cents; nothing is
 * recomputed here. Flags are text, never colour alone.
 */
export function RecapTable({ recap }: { recap: RecapSnapshot }) {
  const alternates = recapColumns(recap);
  // Only shown when apprentice credit applies, so the order of the ranks can be followed from the table.
  const showEvaluated = recap.rows.some((r) => r.apprenticeCredit);
  return (
    <>
      {recap.winnerOverFunding ? (
        <Notice tone="warning" data-testid="recap-over-funding">The expected award exceeds the funding amount.</Notice>
      ) : null}
      <p>
        Funding amount{recap.fundingFromEstimate ? " (taken from the estimate)" : ""}:{" "}
        <Money cents={recap.fundingCents} />.{" "}
        {recap.selectedAlternates.length === 0
          ? "No alternate is selected."
          : `Selected: ${recap.selectedAlternates.map((n) => `Alternate ${n}`).join(", ")}.`}
      </p>
      <Table data-testid="recap-table">
        <caption className="visually-hidden">Bid recap for {recap.solicitationNumber}</caption>
        <thead>
          <tr>
            <Th>Rank</Th><Th>Bidder</Th><Th>Reference</Th><Th numeric>Base</Th>
            {alternates.map((h) => <Th key={h} numeric>{h}</Th>)}
            <Th numeric>Total with selected alternates</Th>
            {showEvaluated ? <Th numeric>Evaluated price</Th> : null}
            <Th>Preferences</Th><Th>Expected award</Th>
          </tr>
        </thead>
        <tbody>
          {recap.rows.map((r) => {
            const winner = recap.expectedWinnerBidId === r.bidId;
            const flags = [r.residentPreferred ? "Resident preference" : null, r.apprenticeCredit ? "Apprentice credit" : null]
              .filter((f): f is string => f !== null);
            return (
              <tr key={r.bidId} data-testid={`recap-${r.reference}`}>
                <Td>{rankLabel(r.rank, r.tied)}</Td>
                <Td>{r.bidderName}</Td>
                <Td>{r.reference}</Td>
                <Td numeric><Money cents={r.baseCents} /></Td>
                {r.alternateCents.map((c, i) => <Td key={i} numeric><Money cents={c} /></Td>)}
                <Td numeric><Money cents={r.totalCents} /></Td>
                {showEvaluated ? <Td numeric><Money cents={r.evaluatedCents} /></Td> : null}
                <Td>{flags.length ? flags.join(", ") : "None"}</Td>
                <Td>{winner ? <strong>Expected award</strong> : null}</Td>
              </tr>
            );
          })}
        </tbody>
      </Table>
    </>
  );
}
