// The office's internal tabulation, built only from what public.opened_bids / opened_bid_files return. Every money
// string comes from formatMoney of stored integer cents; nothing is recomputed or typed in here.
import { formatMoney } from "@/domain/money";
import { UPLOAD_SLOT_LABELS, type UploadSlot } from "@/domain/bid/types";
import type { SolicitationData } from "@/domain/solicitation/types";

export type BondChoice = "electronic" | "paper";

/** One row of public.opened_bids. */
export interface OpenedBid {
  bid_id: string;
  reference: string;
  version: number;
  submitted_at: string;
  bidder_org_id: string;
  bidder_name: string;
  item_cents: number[];
  alternate_cents: number[];
  base_total_cents: number;
  bid_bond_choice: BondChoice | null;
  original_received: boolean;
  non_responsive_reason: string | null;
  /** Paper bond only: whether its paper original was counted. Null otherwise. */
  bond_original_received: boolean | null;
}

/** One row of public.opened_bid_files. */
export interface OpenedFile {
  bid_id: string;
  slot: UploadSlot;
  path: string;
  file_name: string;
  file_status: "ok" | "missing" | "changed" | string;
}

export interface TabulationRow {
  bidId: string;
  reference: string;
  bidderName: string;
  version: number;
  baseTotal: string;
  alternates: string[];
  originalReceived: boolean;
  /** The database's non-responsive reason, verbatim, or null when responsive. */
  reason: string | null;
  bond: string;
  /** "{slot label}: missing|changed" for each file whose storage object no longer matches what was sealed. */
  fileFlags: string[];
}

/**
 * The bid bond as the bidder chose it. Display only: the cure status, not this label, decides responsiveness.
 * An electronic bond may be submitted without its file (Ruling 7), so "uploaded" needs a sealed bid_bond file.
 */
export function bondLabel(choice: BondChoice | null, paperReceived: boolean | null, bondFileUploaded: boolean): string {
  if (choice === "electronic") return bondFileUploaded ? "Electronic bond (uploaded)" : "Electronic bond (not uploaded)";
  if (choice === "paper") return `Paper original mailed: ${paperReceived ? "received" : "not received"}`;
  return "Not required";
}

const CURE_NOTES: Record<string, string> = {
  pending: "cure pending",
  cured: "cured after close",
  failed: "not received by the cure deadline",
};

/**
 * The bond label plus its cure status (from public.review_bids), so a bond cured after close does not read as
 * missing. The label alone reflects only what was sealed at submission.
 */
export function bondWithCure(label: string, cureStatus: string | undefined): string {
  return cureStatus && Object.hasOwn(CURE_NOTES, cureStatus) ? `${label}; ${CURE_NOTES[cureStatus]}` : label;
}

export function alternateHeader(index: number, kind: "additive" | "deductive"): string {
  return `Alternate ${index + 1} (${kind === "additive" ? "add" : "deduct"})`;
}

export function toTabulation(
  rows: OpenedBid[],
  alternates: SolicitationData["schedule"]["alternates"],
  files: OpenedFile[] = [],
  /** bid_id -> app.bond_cure status (pending, cured, failed, ok, not_required). */
  cures: Record<string, string> = {},
): { headers: string[]; rows: TabulationRow[] } {
  return {
    headers: alternates.map((a, i) => alternateHeader(i, a.kind)),
    rows: rows.map((r) => ({
      bidId: r.bid_id,
      reference: r.reference,
      bidderName: r.bidder_name,
      version: r.version,
      baseTotal: formatMoney(r.base_total_cents),
      alternates: r.alternate_cents.map(formatMoney),
      originalReceived: r.original_received,
      reason: r.non_responsive_reason,
      bond: bondWithCure(bondLabel(r.bid_bond_choice, r.bond_original_received,
        files.some((f) => f.bid_id === r.bid_id && f.slot === "bid_bond")), cures[r.bid_id]),
      fileFlags: files
        .filter((f) => f.bid_id === r.bid_id && f.file_status !== "ok")
        .map((f) => `${UPLOAD_SLOT_LABELS[f.slot] ?? f.slot}: ${f.file_status}`),
    })),
  };
}
