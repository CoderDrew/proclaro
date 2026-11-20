import type { Cents } from "../money";
import { deriveRequirements } from "../solicitation/valueBands";
import type { SolicitationData } from "../solicitation/types";
import { UPLOAD_SLOT_LABELS, type BidBondChoice, type BidDraft, type BidIssue, type UploadSlot } from "./types";

/** The parts of a solicitation the bid rules read (a full SolicitationData fits). */
export type BidRules = Pick<SolicitationData, "estimateCents" | "optionalSections" | "schedule">;

/** Whether the solicitation needs a bid bond. An unknown estimate counts as below the threshold, as in SQL. */
function bondsRequired(data: BidRules): boolean {
  return deriveRequirements(data.estimateCents ?? 0, false, data.optionalSections).bonds;
}

/** Whether the bid form asks for the apprentice commitment ($1,000,000.00 and up). Unknown counts as below. */
export function apprenticeRequired(data: BidRules): boolean {
  return deriveRequirements(data.estimateCents ?? 0, false, data.optionalSections).apprenticeCredit;
}

/**
 * Upload slots the bid needs, in the database's order (app.required_bid_slots): insurance, each optional
 * section in solicitation order, then the bond file when a bond is required and the choice is electronic.
 * This is what the form offers. The bond file is NOT needed to submit (Ruling 7): it may be cured after submit,
 * so validateBidDraft ignores the bid_bond slot.
 */
export function requiredUploadSlots(data: BidRules, choice: BidBondChoice | null): UploadSlot[] {
  const slots: UploadSlot[] = ["insurance", ...data.optionalSections];
  if (bondsRequired(data) && choice === "electronic") slots.push("bid_bond");
  return slots;
}

export function baseTotalCents(itemCents: Cents[]): Cents {
  return itemCents.reduce((sum, c) => sum + c, 0);
}

type PriceKind = { key: "items" | "alternates"; label: string };
const ITEM: PriceKind = { key: "items", label: "Item" };
const ALTERNATE: PriceKind = { key: "alternates", label: "Alternate" };

/**
 * Problems that block submitting the draft, in the order app.bid_draft_problems reports them (count, missing,
 * uploads, bond, apprentice). upload_missing never names bid_bond: the bond file is curable after submit. `file_missing` is database-only: it needs the Storage objects. An empty price array is
 * price_missing, not price_count, exactly as in SQL.
 */
export function validateBidDraft(draft: BidDraft, data: BidRules): BidIssue[] {
  const counts: BidIssue[] = [];
  const missing: BidIssue[] = [];
  const check = (kind: PriceKind, prices: (Cents | null)[], expected: number) => {
    if (prices.length === 0 && expected > 0) {
      for (let i = 0; i < expected; i++) {
        missing.push({ code: "price_missing", field: `${kind.key}.${i}`, message: `Enter a price for ${kind.label} ${i + 1}.` });
      }
    } else if (prices.length !== expected) {
      counts.push({
        code: "price_count", field: kind.key,
        message: `${kind.label} prices do not match the schedule: expected ${expected}, found ${prices.length}.`,
      });
    } else {
      prices.forEach((p, i) => {
        if (p === null) {
          missing.push({ code: "price_missing", field: `${kind.key}.${i}`, message: `Enter a price for ${kind.label} ${i + 1}.` });
        }
      });
    }
  };
  check(ITEM, draft.itemCents, data.schedule.items.length);
  check(ALTERNATE, draft.alternateCents, data.schedule.alternates.length);

  const uploads: BidIssue[] = requiredUploadSlots(data, draft.bidBondChoice)
    .filter((slot) => slot !== "bid_bond" && !draft.files.some((f) => f.slot === slot))
    .map((slot) => ({ code: "upload_missing" as const, field: `uploads.${slot}`, message: `Upload the file for ${UPLOAD_SLOT_LABELS[slot]}.` }));

  const bond: BidIssue[] = [];
  const bonds = bondsRequired(data);
  if (bonds && draft.bidBondChoice === null) {
    bond.push({ code: "bond_choice_missing", field: "bond", message: "Choose how the bid bond will be provided." });
  } else if (!bonds && draft.bidBondChoice !== null) {
    bond.push({ code: "bond_not_required", field: "bond", message: "This solicitation does not require a bid bond." });
  }

  const apprentice: BidIssue[] = [];
  const asked = apprenticeRequired(data);
  if (asked && draft.apprenticeCommitment === null) {
    apprentice.push({ code: "apprentice_missing", field: "apprentice", message: "Answer the apprentice commitment question." });
  } else if (!asked && draft.apprenticeCommitment !== null) {
    apprentice.push({
      code: "apprentice_not_required", field: "apprentice",
      message: "This solicitation does not ask for an apprentice commitment.",
    });
  }

  return [...counts, ...missing, ...uploads, ...bond, ...apprentice];
}
