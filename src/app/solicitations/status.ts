export type BidStatus = "Open" | "Closed";

/** Open while now < bid_due_at, otherwise Closed. */
export function bidStatus(bidDueAt: string | null, now: Date): BidStatus {
  return bidDueAt !== null && now.getTime() < new Date(bidDueAt).getTime() ? "Open" : "Closed";
}

/** A UTC instant shown in the configured zone, e.g. "Aug 31, 2026, 1:00 PM MDT". */
export function formatInstant(iso: string, tz: string): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: tz, dateStyle: "medium", timeStyle: "short",
  }).format(new Date(iso)).replace(/\u202f/g, " ") + " " + zoneName(iso, tz);
}

function zoneName(iso: string, tz: string): string {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: tz, timeZoneName: "short" }).formatToParts(new Date(iso));
  return parts.find((p) => p.type === "timeZoneName")?.value ?? tz;
}

/** The two filters a query needs to return only what is actually public. */
export interface PublicFilterable<Q> {
  eq(column: "state", value: "published"): Q;
  lte(column: "release_date", value: string): Q;
}

/**
 * Restricts a solicitations query to published rows released on or before `today` (the configured zone's date).
 * RLS alone is not enough: signed-in office staff can read every row, so without this the public pages would
 * show them unreleased solicitations.
 */
export function onlyPublic<Q extends PublicFilterable<Q>>(query: Q, today: string): Q {
  return query.eq("state", "published").lte("release_date", today);
}

/**
 * A bidder's posted outcome, worded for display; an unknown value is returned as it is. Under the posted "all bids
 * rejected" memo an accepted bid was rejected too, so it is never shown as accepted.
 */
export function postedOutcomeLabel(status: string, allRejected = false): string {
  switch (status) {
    case "accepted":
    case "flag_accepted":
      return allRejected ? "All bids rejected" : "Accepted";
    case "non_responsive":
      return "Non-responsive";
    case "flag_rejected":
      return "Rejected by the agency";
    default:
      return status;
  }
}
