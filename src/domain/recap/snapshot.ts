// The recap and award snapshots as JSON, the contract with app.rank_recap / app.build_recap (0021). Every figure is
// computed in Postgres from sealed bid prices; this module only parses and labels what the database returned.
import { z } from "zod";
import { formatMoney } from "@/domain/money";
import { alternateHeader } from "@/app/office/solicitations/[id]/bids/tabulation";

const cents = z.number().int();
const alternate = z.object({ kind: z.enum(["additive", "deductive"]), description: z.string() });

export const recapRowSchema = z.object({
  bidId: z.string(),
  reference: z.string(),
  bidderName: z.string(),
  baseCents: cents,
  alternateCents: z.array(cents),
  totalCents: cents,
  /** Display only: the exact evaluated price (hundredths of a cent) rounded half-up to cents. */
  evaluatedCents: cents,
  resident: z.boolean(),
  apprenticeCredit: z.boolean(),
  residentPreferred: z.boolean(),
  rank: z.number().int().positive(),
  tied: z.boolean(),
});

const common = {
  solicitationNumber: z.string(),
  fundingCents: cents,
  fundingFromEstimate: z.boolean(),
  alternates: z.array(alternate),
};

export const recapSnapshotSchema = z.object({
  ...common,
  kind: z.literal("recap"),
  reason: z.null(),
  /** 1-based, ascending. */
  selectedAlternates: z.array(z.number().int().positive()),
  rows: z.array(recapRowSchema).min(1),
  expectedWinnerBidId: z.string().nullable(),
  winnerOverFunding: z.boolean(),
});

/** "All bids rejected": the memo discloses no bid, so rows and selectedAlternates are empty. */
export const memoSnapshotSchema = z.object({
  ...common,
  kind: z.literal("all_rejected"),
  reason: z.enum(["over_funding", "no_accepted_bids"]),
  selectedAlternates: z.tuple([]),
  rows: z.tuple([]),
  expectedWinnerBidId: z.null(),
  winnerOverFunding: z.literal(false),
});

export const awardSnapshotSchema = z.object({
  bidId: z.string(),
  reference: z.string(),
  bidderName: z.string(),
  amountCents: cents,
  selectedAlternates: z.array(z.number().int().positive()),
  alternates: z.array(alternate),
  expectedWinnerBidId: z.string().nullable(),
  differsFromExpected: z.boolean(),
});

export type RecapRow = z.infer<typeof recapRowSchema>;
export type RecapSnapshot = z.infer<typeof recapSnapshotSchema>;
export type MemoSnapshot = z.infer<typeof memoSnapshotSchema>;
export type AwardSnapshot = z.infer<typeof awardSnapshotSchema>;

const recapOrMemo = z.discriminatedUnion("kind", [recapSnapshotSchema, memoSnapshotSchema]);

export function parseRecap(raw: unknown): RecapSnapshot | MemoSnapshot | null {
  const r = recapOrMemo.safeParse(raw);
  return r.success ? r.data : null;
}

export function parseAward(raw: unknown): AwardSnapshot | null {
  const r = awardSnapshotSchema.safeParse(raw);
  return r.success ? r.data : null;
}

/** One header per alternate, marked "(selected)" when the recap took it. */
export function recapColumns(s: RecapSnapshot): string[] {
  return s.alternates.map(
    (a, i) => `${alternateHeader(i, a.kind)}${s.selectedAlternates.includes(i + 1) ? " (selected)" : ""}`,
  );
}

/** Why every bid was rejected, without the "All bids rejected" heading. */
export function memoReason(s: MemoSnapshot): string {
  return s.reason === "over_funding"
    ? `every accepted bid exceeds the funding amount of ${formatMoney(s.fundingCents)}`
    : "no bid was accepted";
}

export function memoText(s: MemoSnapshot): string {
  return `All bids rejected: ${memoReason(s)}.`;
}
