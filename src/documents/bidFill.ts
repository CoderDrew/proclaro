import type { BidBondChoice, BidDraft } from "@/domain/bid/types";
import type { Cents } from "@/domain/money";
import type { Database } from "@/lib/supabase/database.types";

export type BidderCompany = Database["public"]["Tables"]["bidder_companies"]["Row"];

/** Everything the pre-filled bid form prints about a bid. Prices are complete: no nulls. */
export interface BidFill {
  legalName: string;
  address: string;
  /** "Ana Ridge, 555-0142, ana@example.test" */
  contact: string;
  residentClaimed: boolean;
  residentCertificate: string | null;
  reference: string;
  /** The version the draft will become when submitted. */
  bidVersion: number;
  itemCents: Cents[];
  alternateCents: Cents[];
  bidBond: BidBondChoice | null;
}

/** A draft with any missing price cannot be printed; the caller answers 409. */
export function toBidFill(company: BidderCompany, legalName: string, draft: BidDraft): BidFill | { incomplete: true } {
  const complete = (a: (Cents | null)[]): a is Cents[] => a.every((c) => c !== null);
  if (draft.itemCents.length === 0 || !complete(draft.itemCents) || !complete(draft.alternateCents)) {
    return { incomplete: true };
  }
  return {
    legalName,
    address: company.address,
    contact: [company.contact_name, company.contact_phone, company.contact_email].join(", "),
    residentClaimed: company.resident_claimed,
    residentCertificate: company.resident_certificate,
    reference: draft.reference,
    bidVersion: draft.version,
    itemCents: draft.itemCents,
    alternateCents: draft.alternateCents,
    bidBond: draft.bidBondChoice,
  };
}
