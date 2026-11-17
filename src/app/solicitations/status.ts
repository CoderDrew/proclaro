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
