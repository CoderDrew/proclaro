import type { Cents } from "../money";
import type { OptionalSection, Requirements } from "./types";

/** Inclusive lower bounds, in integer cents. */
export const BLOCKED_BELOW = 5_000_000;
export const PREVAILING_WAGE_AT = 10_000_000;
export const BONDS_AT = 15_000_000;
export const APPRENTICE_CREDIT_AT = 100_000_000;

export function deriveRequirements(
  estimateCents: Cents,
  federalFunds: boolean,
  optional: OptionalSection[],
): Requirements {
  return {
    blocked: estimateCents < BLOCKED_BELOW,
    prevailingWage: estimateCents >= PREVAILING_WAGE_AT,
    bonds: estimateCents >= BONDS_AT,
    apprenticeCredit: estimateCents >= APPRENTICE_CREDIT_AT,
    federalClauses: federalFunds,
    requiredSections: [
      "bid_form_1", "bid_form_2", "signature_page", "insurance",
      ...optional,
    ],
  };
}
