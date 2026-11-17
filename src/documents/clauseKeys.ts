/** The fixed set of admin-maintained clause records. Version 1 of each is seeded in 0003_clauses_seed.sql. */
export const CLAUSE_KEYS = [
  "notice",
  "prebid_meeting",
  "background_check",
  "addenda",
  "substitutions",
  "submission",
  "bid_deposit",
  "performance_bond",
  "modification_withdrawal",
  "award_contract",
  "resident_preference",
  "registrations",
  "apprentice_credit",
  "reservation_of_rights",
  "questions",
  "communication_restrictions",
  "insurance",
  "prevailing_wage",
  "warranty",
  "federal_domestic_content",
  "evaluation_award",
  "bid_form_instructions",
  "bid_form_terms",
  "signature_certifications",
] as const;

export type ClauseKey = (typeof CLAUSE_KEYS)[number];

/** The variables a clause body may reference. Seed text must use only these. */
export const CLAUSE_VARIABLES = [
  "stateName",
  "officeName",
  "agencyName",
  "number",
  "bidDueDate",
  "bidDueTime",
  "questionsDue",
  "answersDue",
  "bidValidityDays",
] as const;
