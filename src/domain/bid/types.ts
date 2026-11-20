import type { Cents } from "../money";

export type UploadSlot = "insurance" | "qualifications" | "references" | "current_work" | "bid_bond";
export type BidBondChoice = "electronic" | "paper";

export interface BidDraft {
  bidId: string;
  reference: string;
  /** The version the draft will become when submitted. */
  version: number;
  itemCents: (Cents | null)[];
  alternateCents: (Cents | null)[];
  bidBondChoice: BidBondChoice | null;
  /** The apprentice commitment answer ($1M+ solicitations only); null when unanswered. Sealed with the prices. */
  apprenticeCommitment: boolean | null;
  files: { slot: UploadSlot; path: string; fileName: string }[];
}

/** Matches the codes app.bid_draft_problems returns (file_missing is raised by the database only). */
export type BidIssueCode =
  | "price_count" | "price_missing" | "upload_missing" | "file_missing" | "bond_choice_missing" | "bond_not_required"
  | "apprentice_missing" | "apprentice_not_required";

export interface BidIssue {
  code: BidIssueCode;
  /** For example "items.1", "alternates", "uploads.references", "bond", "apprentice". */
  field: string;
  message: string;
}

/** The largest price the database accepts, in cents. */
export const MAX_PRICE_CENTS = 999_999_999_999;

/** Plain-language names for the upload slots (the sections match the bid form checklist). */
export const UPLOAD_SLOT_LABELS: Record<UploadSlot, string> = {
  insurance: "Proof of Insurance",
  qualifications: "Statement of Qualifications",
  references: "References",
  current_work: "Current Work",
  bid_bond: "Electronic bid bond",
};
