/**
 * The fixed review note for a bid missing acknowledgments. Same text as app.ack_note() in
 * supabase/migrations/0031_acknowledgments.sql (kept in sync by ack.test.ts). Pass the numbers ascending, as
 * missingAcknowledgments returns them.
 */
export function ackNote(missing: number[]): string {
  return `Did not acknowledge Addendum ${missing.join(", ")}.`;
}

/** Published addendum numbers without an acknowledgment, ascending (as app.missing_acknowledgments). */
export function missingAcknowledgments(published: number[], acknowledged: number[]): number[] {
  const acked = new Set(acknowledged);
  return published.filter((n) => !acked.has(n)).sort((a, b) => a - b);
}
