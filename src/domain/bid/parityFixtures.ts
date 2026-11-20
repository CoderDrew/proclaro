import type { OptionalSection } from "../solicitation/types";
import type { BidBondChoice, BidIssueCode, UploadSlot } from "./types";

/**
 * Shared fixtures for the TypeScript validator and app.bid_draft_problems. parity.test.ts runs each case through
 * validateBidDraft; the same cases are rendered into supabase/tests/bid_parity.test.sql, which runs them through
 * the database function. `expected` is the list of distinct codes in first-appearance order, which is the order
 * the database returns them. file_missing is database-only and is not part of these cases (every attached slot
 * gets a Storage object with size and eTag in SQL).
 */
export interface ParityCase {
  name: string;
  solicitation: { items: number; alternates: number; estimateCents: number | null; optionalSections: OptionalSection[] };
  draft: {
    itemCents: (number | null)[];
    alternateCents: (number | null)[];
    bidBondChoice: BidBondChoice | null;
    slots: UploadSlot[];
    apprenticeCommitment: boolean | null;
  };
  expected: BidIssueCode[];
}

const big = { items: 2, alternates: 1, estimateCents: 15_000_000, optionalSections: ["references"] as OptionalSection[] };
const small = { ...big, estimateCents: 14_999_999 };
const full = {
  itemCents: [12_500_000, 234_567] as (number | null)[],
  alternateCents: [1_500_000] as (number | null)[],
  bidBondChoice: "paper" as BidBondChoice | null,
  slots: ["insurance", "references"] as UploadSlot[],
  apprenticeCommitment: null as boolean | null,
};

export const PARITY_CASES: ParityCase[] = [
  { name: "complete draft with a paper bond", solicitation: big, draft: full, expected: [] },
  { name: "complete draft with an electronic bond", solicitation: big,
    draft: { ...full, bidBondChoice: "electronic", slots: ["insurance", "references", "bid_bond"] }, expected: [] },
  { name: "null item price", solicitation: big, draft: { ...full, itemCents: [12_500_000, null] }, expected: ["price_missing"] },
  { name: "null alternate price", solicitation: big, draft: { ...full, alternateCents: [null] }, expected: ["price_missing"] },
  { name: "empty price arrays are price_missing", solicitation: big,
    draft: { ...full, itemCents: [], alternateCents: [] }, expected: ["price_missing"] },
  { name: "empty item array only", solicitation: big, draft: { ...full, itemCents: [] }, expected: ["price_missing"] },
  { name: "too many item prices", solicitation: big, draft: { ...full, itemCents: [1, 2, 3] }, expected: ["price_count"] },
  { name: "too few item prices", solicitation: big, draft: { ...full, itemCents: [1] }, expected: ["price_count"] },
  { name: "too many alternate prices", solicitation: big, draft: { ...full, alternateCents: [1, 2] }, expected: ["price_count"] },
  { name: "alternate prices where the schedule has none", solicitation: { ...big, alternates: 0 },
    draft: { ...full, alternateCents: [1] }, expected: ["price_count"] },
  { name: "empty alternates are fine when the schedule has none", solicitation: { ...big, alternates: 0 },
    draft: { ...full, alternateCents: [] }, expected: [] },
  { name: "count and missing together", solicitation: big,
    draft: { ...full, itemCents: [1, 2, 3], alternateCents: [null] }, expected: ["price_count", "price_missing"] },
  { name: "count on one array, empty on the other", solicitation: big,
    draft: { ...full, itemCents: [1, 2, 3], alternateCents: [] }, expected: ["price_count", "price_missing"] },
  { name: "missing insurance upload", solicitation: big,
    draft: { ...full, slots: ["references"] }, expected: ["upload_missing"] },
  { name: "missing optional section upload", solicitation: big,
    draft: { ...full, slots: ["insurance"] }, expected: ["upload_missing"] },
  { name: "no uploads at all", solicitation: big, draft: { ...full, slots: [] }, expected: ["upload_missing"] },
  { name: "electronic bond without the bond file is curable after submit", solicitation: big,
    draft: { ...full, bidBondChoice: "electronic" }, expected: [] },
  { name: "electronic bond without the bond file, insurance still missing", solicitation: big,
    draft: { ...full, bidBondChoice: "electronic", slots: ["references"] }, expected: ["upload_missing"] },
  { name: "electronic bond without the bond file, no bond choice is not the same", solicitation: big,
    draft: { ...full, bidBondChoice: null, slots: ["insurance", "references"] }, expected: ["bond_choice_missing"] },
  { name: "extra bond file with a paper choice is not an issue", solicitation: big,
    draft: { ...full, slots: ["insurance", "references", "bid_bond"] }, expected: [] },
  { name: "no bond choice at $150,000.00", solicitation: big,
    draft: { ...full, bidBondChoice: null }, expected: ["bond_choice_missing"] },
  { name: "bond choice below the threshold", solicitation: small, draft: full, expected: ["bond_not_required"] },
  { name: "electronic choice below the threshold", solicitation: small,
    draft: { ...full, bidBondChoice: "electronic", slots: ["insurance", "references", "bid_bond"] },
    expected: ["bond_not_required"] },
  { name: "no choice below the threshold", solicitation: small, draft: { ...full, bidBondChoice: null }, expected: [] },
  { name: "unknown estimate is below the threshold", solicitation: { ...big, estimateCents: null },
    draft: { ...full, bidBondChoice: null }, expected: [] },
  { name: "several optional sections in solicitation order",
    solicitation: { ...small, optionalSections: ["qualifications", "current_work"] },
    draft: { ...full, bidBondChoice: null, slots: ["insurance", "qualifications"] }, expected: ["upload_missing"] },
  { name: "everything wrong at once", solicitation: big,
    draft: { itemCents: [1, 2, 3], alternateCents: [null], bidBondChoice: null, slots: [], apprenticeCommitment: null },
    expected: ["price_count", "price_missing", "upload_missing", "bond_choice_missing"] },
  { name: "apprentice answer missing at $1,000,000.00", solicitation: { ...big, estimateCents: 100_000_000 },
    draft: full, expected: ["apprentice_missing"] },
  { name: "apprentice answered below $1,000,000.00", solicitation: { ...big, estimateCents: 99_999_999 },
    draft: { ...full, apprenticeCommitment: true }, expected: ["apprentice_not_required"] },
  { name: "apprentice answered no at $1,000,000.00", solicitation: { ...big, estimateCents: 100_000_000 },
    draft: { ...full, apprenticeCommitment: false }, expected: [] },
  { name: "apprentice answered yes at $1,000,000.00", solicitation: { ...big, estimateCents: 100_000_000 },
    draft: { ...full, apprenticeCommitment: true }, expected: [] },
  { name: "bond and apprentice problems together, bond first", solicitation: { ...big, estimateCents: 100_000_000 },
    draft: { ...full, bidBondChoice: null }, expected: ["bond_choice_missing", "apprentice_missing"] },
  { name: "unknown estimate never asks for an apprentice answer", solicitation: { ...big, estimateCents: null },
    draft: { ...full, bidBondChoice: null, apprenticeCommitment: false }, expected: ["apprentice_not_required"] },
];

/** The fixture solicitation's schedule, shared by the TypeScript test and the SQL renderer. */
export function schedulePieces(s: ParityCase["solicitation"]) {
  return {
    items: Array.from({ length: s.items }, (_, i) => ({ name: `Item ${i + 1}`, description: "" })),
    alternates: Array.from({ length: s.alternates }, (_, i) => ({ kind: "deductive" as const, description: `Alternate ${i + 1}` })),
  };
}

const pgArray = (a: (number | null)[]) => `{${a.map((v) => (v === null ? "NULL" : String(v))).join(",")}}`;
const sqlText = (s: string) => `'${s.replace(/'/g, "''")}'`;

/** supabase/tests/bid_parity.test.sql: every case run through app.bid_draft_problems. */
export function renderParitySql(cases: ParityCase[] = PARITY_CASES): string {
  const out: string[] = [];
  out.push(
    "-- GENERATED from src/domain/bid/parityFixtures.ts by parity.test.ts. Do not edit by hand:",
    "-- run `UPDATE_PARITY_SQL=1 npm test -- parity` after changing the fixtures.",
    "-- Each case builds a bid and its draft, then compares app.bid_draft_problems with the TypeScript validator's",
    "-- expected codes (the same cases run through validateBidDraft in parity.test.ts).",
    "begin;",
    "",
    `select plan(${cases.length});`,
    "",
    "insert into public.organizations (id, name, kind) values",
    "  ('00000000-0000-0000-0000-0000000008a1', 'BP Agency', 'agency');",
    "select tests.make_user('bp.author@test.test', '00000000-0000-0000-0000-0000000008a1') as author \\gset",
    "select tests.make_bidder('bp.bidder@test.test', 'BP Bidder') as bidder \\gset",
    "select p.org_id as org from public.profiles p where p.user_id = :'bidder' \\gset",
    "",
  );
  cases.forEach((c, i) => {
    const n = i + 1;
    const { items, alternates } = schedulePieces(c.solicitation);
    const overrides = {
      schedule: { items, alternates },
      estimateCents: c.solicitation.estimateCents,
      optionalSections: c.solicitation.optionalSections,
    };
    out.push(
      `-- ${n}: ${c.name}`,
      `select tests.make_published_solicitation('00000000-0000-0000-0000-0000000008a1', :'author', now() + interval '1 day', ${sqlText(JSON.stringify(overrides))}::jsonb) as sol_${n} \\gset`,
      `insert into public.bids (solicitation_id, bidder_org_id, reference, created_by) values (:'sol_${n}', :'org', app.new_bid_reference(), :'bidder') returning id as bid_${n} \\gset`,
      `insert into public.bid_drafts (bid_id, version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment) values (:'bid_${n}', 1, ${sqlText(pgArray(c.draft.itemCents))}::bigint[], ${sqlText(pgArray(c.draft.alternateCents))}::bigint[], ${c.draft.bidBondChoice ? sqlText(c.draft.bidBondChoice) : "null"}, ${c.draft.apprenticeCommitment === null ? "null" : String(c.draft.apprenticeCommitment)});`,
    );
    for (const slot of c.draft.slots) {
      out.push(
        `select 'bids/' || :'bid_${n}' || '/' || gen_random_uuid() || '/${slot}.pdf' as path_${n}_${slot} \\gset`,
        `insert into storage.objects (bucket_id, name, metadata) values ('bid-files', :'path_${n}_${slot}', jsonb_build_object('eTag', '"parity-${n}-${slot}"', 'size', 1024));`,
        `insert into public.bid_draft_files (bid_id, slot, path, file_name) values (:'bid_${n}', '${slot}', :'path_${n}_${slot}', '${slot}.pdf');`,
      );
    }
    out.push(
      `select is(app.bid_draft_problems(:'bid_${n}')::text, '{${c.expected.join(",")}}', ${sqlText(c.name)});`,
      "",
    );
  });
  out.push("select * from finish();", "rollback;", "");
  return out.join("\n");
}
