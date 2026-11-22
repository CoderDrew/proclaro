// The AI document check's checklist: the items per document kind, which method decides each one, and what the model is
// asked. Kept in sync with app.ai_check_codes (0036_ai_check.sql) by a parity test.
//   ai:   the model judges the item from the document (met / not met / unclear, with page and excerpt).
//   rule: the model only extracts a value (with page and excerpt); a rule in rules.ts compares it with the portal.

export type DocumentKind =
  | "signed_form" | "bid_bond_scan" | "insurance" | "bid_bond" | "qualifications" | "references" | "current_work";

export interface ItemSpec {
  code: string;
  label: string;
  method: "ai" | "rule";
  /** The instruction to the model for this item. */
  asks: string;
}

const BOND: readonly ItemSpec[] = [
  { code: "principal_name", label: "Principal matches the bidder", method: "rule",
    asks: "Extract the principal (the contractor) named on the bond, exactly as written." },
  { code: "obligee", label: "Obligee is the agency", method: "rule",
    asks: "Extract the obligee named on the bond, exactly as written." },
  { code: "surety_signature", label: "Surety signature present", method: "ai",
    asks: "Is there a handwritten or electronic signature for the surety (or its attorney-in-fact)? met if present, not_met if the signature line is blank." },
];

const SECTION = (what: string): readonly ItemSpec[] => [
  { code: "document_matches_slot", label: `The document is the ${what}`, method: "ai",
    asks: `Is this document the bidder's ${what}? met if it clearly is, not_met if it is clearly something else, unclear otherwise.` },
];

export const CHECKLIST: Record<DocumentKind, readonly ItemSpec[]> = {
  // aicheck-codes:start (order matches app.ai_check_codes)
  signed_form: [
    { code: "signature_present", label: "Signature on the signature page", method: "ai",
      asks: "Is the bid form signed by the bidder on its signature page? met if a signature is present, not_met if the signature line is blank." },
    { code: "amount_in_words", label: "Amount in words matches the portal total", method: "rule",
      asks: "Extract the total bid amount written in words, exactly as written." },
    { code: "addenda_listed", label: "Addenda listed match the published addenda", method: "rule",
      asks: "List only the addendum numbers written on the 'Addenda acknowledged' line, comma-separated (for example 1, 2), or None if none are listed. Leave out dates." },
    { code: "form_version", label: "Form version matches the version submitted", method: "rule",
      asks: "Extract the version number printed in the form's footer (for example 'Version 2')." },
    { code: "resident_certificate", label: "Resident certificate number matches the claim", method: "rule",
      asks: "Extract the resident bidder certificate number written on the form, if any." },
  ],
  insurance: [
    { code: "insured_name", label: "Insured name matches the bidder", method: "rule",
      asks: "Extract the insured party's name, exactly as written." },
    { code: "coverage_dates", label: "Coverage in force on the bid due date", method: "rule",
      asks: "Extract the policy effective and expiration dates as 'YYYY-MM-DD to YYYY-MM-DD'." },
  ],
  bid_bond: BOND,
  bid_bond_scan: BOND,
  qualifications: SECTION("statement of qualifications"),
  references: SECTION("list of project references"),
  current_work: SECTION("list of current work in progress"),
  // aicheck-codes:end
};

export const DOCUMENT_LABEL: Record<DocumentKind, string> = {
  signed_form: "Signed bid form (scan)",
  bid_bond_scan: "Bid bond (paper, scan)",
  insurance: "Insurance certificate",
  bid_bond: "Bid bond",
  qualifications: "Qualifications",
  references: "References",
  current_work: "Current work",
};
