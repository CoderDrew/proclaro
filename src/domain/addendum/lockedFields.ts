import type { SolicitationData } from "../solicitation/types";

/**
 * Data keys an addendum can't change: they are history once the solicitation is published. Kept in sync with
 * app.locked_fields() in supabase/migrations/0027_addenda.sql by lockedFields.test.ts.
 */
export const LOCKED_FIELDS: readonly (keyof SolicitationData)[] = [
  "releaseDate", "adStart", "adEnd", "newspapers", "category",
];

/** The locked keys whose values differ between `base` and `next`, in LOCKED_FIELDS order. */
export function lockedFieldChanges(base: SolicitationData, next: SolicitationData): (keyof SolicitationData)[] {
  return LOCKED_FIELDS.filter((k) => JSON.stringify(base[k] ?? null) !== JSON.stringify(next[k] ?? null));
}
