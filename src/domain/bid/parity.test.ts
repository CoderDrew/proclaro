import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { emptySolicitation } from "../solicitation/schema";
import type { SolicitationData } from "../solicitation/types";
import { PARITY_CASES, renderParitySql, schedulePieces, type ParityCase } from "./parityFixtures";
import { validateBidDraft } from "./validate";
import type { BidDraft } from "./types";

const SQL_PATH = fileURLToPath(new URL("../../../supabase/tests/bid_parity.test.sql", import.meta.url));
const CRLF = new RegExp(String.fromCharCode(13) + String.fromCharCode(10), "g");

function solicitationOf(s: ParityCase["solicitation"]): SolicitationData {
  const { items, alternates } = schedulePieces(s);
  return { ...emptySolicitation(), estimateCents: s.estimateCents, optionalSections: s.optionalSections, schedule: { items, alternates } };
}

function draftOf(d: ParityCase["draft"]): BidDraft {
  return {
    bidId: "b", reference: "AAAA-BBBB", version: 1,
    itemCents: d.itemCents, alternateCents: d.alternateCents, bidBondChoice: d.bidBondChoice,
    apprenticeCommitment: d.apprenticeCommitment,
    files: d.slots.map((slot) => ({ slot, path: `bids/b/u/${slot}.pdf`, fileName: `${slot}.pdf` })),
  };
}

/** Distinct codes in first-appearance order: the shape app.bid_draft_problems returns. */
const distinctCodes = (codes: string[]) => [...new Set(codes)];

describe("TypeScript validator matches app.bid_draft_problems (shared fixtures)", () => {
  for (const c of PARITY_CASES) {
    it(c.name, () => {
      const codes = validateBidDraft(draftOf(c.draft), solicitationOf(c.solicitation)).map((i) => i.code);
      expect(distinctCodes(codes)).toEqual(c.expected);
    });
  }

  it("covers every code the TypeScript validator can emit", () => {
    const seen = new Set<string>(PARITY_CASES.flatMap((c) => c.expected));
    for (const code of ["price_count", "price_missing", "upload_missing", "bond_choice_missing", "bond_not_required",
      "apprentice_missing", "apprentice_not_required"]) {
      expect(seen.has(code), code).toBe(true);
    }
  });

  it("keeps supabase/tests/bid_parity.test.sql in step with the fixtures", () => {
    const rendered = renderParitySql();
    if (process.env.UPDATE_PARITY_SQL === "1") writeFileSync(SQL_PATH, rendered);
    // Git may check the file out with CRLF line endings on Windows.
    expect(readFileSync(SQL_PATH, "utf8").replace(CRLF, "\n"), "run: UPDATE_PARITY_SQL=1 npm test -- parity").toBe(rendered);
  });
});
