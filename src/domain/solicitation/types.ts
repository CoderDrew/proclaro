import type { Cents } from "../money";
import type { LocalDate, LocalTime } from "../time";

export type Category = "construction" | "major_maintenance" | "capital_construction";
export type FundingSource = "capital_construction" | "major_maintenance" | "other";
export type PreBidKind = "none" | "optional" | "mandatory";
export type PreBidFormat = "in_person" | "phone" | "video";
export type BidSection =
  | "bid_form_1" | "bid_form_2" | "signature_page" | "insurance"
  | "qualifications" | "references" | "current_work";
export type OptionalSection = "qualifications" | "references" | "current_work";
export type AttachmentKind = "plans" | "specifications" | "sample_contract" | "prevailing_wage" | "other";

export interface Contact { name: string; email: string; phone: string }

export interface SolicitationData {
  shortTitle: string; longTitle: string; category: Category | null;
  summary: string; projectDescription: string; scopeNotes: string; specialProvisions: string;
  location: { address: string; city: string; county: string };
  requester: Contact; projectManager: Contact;
  estimateCents: Cents | null;
  /** The most the agency can spend. Confidential until the recap is posted (Ruling 2): frozen at publish into
   *  solicitation_funding and never in the public data or snapshot. */
  fundingAmountCents: Cents | null;
  fundingSource: FundingSource | null; fundingOther: string; federalFunds: boolean | null;
  releaseDate: LocalDate | null; adStart: LocalDate | null; adEnd: LocalDate | null; newspapers: string;
  questionsDue: { date: LocalDate; time: LocalTime } | null;
  answersDue: { date: LocalDate; time: LocalTime } | null;
  bidDueDate: LocalDate | null; bidDueTime: LocalTime;
  tentativeAwardDate: LocalDate | null; estimatedStartDate: LocalDate | null; estimatedCompletionDate: LocalDate | null;
  bidValidityDays: number;
  preBid: { kind: PreBidKind; format: PreBidFormat | null; date: LocalDate | null; time: LocalTime | null; location: string };
  backgroundCheck: { required: boolean; contact: string; leadDays: number | null };
  schedule: {
    items: { name: string; description: string }[];
    alternates: { kind: "additive" | "deductive"; description: string }[];
  };
  optionalSections: OptionalSection[];
  pageLimits: Partial<Record<BidSection, number>>;
  attachments: { kind: AttachmentKind; label: string; storagePath: string; issueDate: LocalDate | null }[];
}

export interface Requirements {
  blocked: boolean; prevailingWage: boolean; bonds: boolean; apprenticeCredit: boolean;
  federalClauses: boolean; requiredSections: BidSection[];
}
