import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { CHECKLIST, type DocumentKind } from "./checklist";
import { wordsToCents } from "./words";
import { addendaMatch, coversDate, namesMatch } from "./rules";
import { evaluate, type Facts } from "./evaluate";

/** app.ai_check_codes from the migration, between its marker comments: kind -> codes. */
function migrationCodes(): Record<string, string[]> {
  const sql = readFileSync(join(process.cwd(), "supabase/migrations/0036_ai_check.sql"), "utf8");
  const block = /aicheck-codes:start([\s\S]*?)-- aicheck-codes:end/.exec(sql);
  if (!block) throw new Error("marker comments not found in 0036_ai_check.sql");
  const out: Record<string, string[]> = {};
  for (const m of block[1].matchAll(/when '([a-z_]+)' then array\[([^\]]*)\]/g)) {
    out[m[1]] = [...m[2].matchAll(/'([a-z_]+)'/g)].map((c) => c[1]);
  }
  return out;
}

describe("checklist parity", () => {
  it("matches app.ai_check_codes in 0036", () => {
    const ts = Object.fromEntries(Object.entries(CHECKLIST).map(([k, v]) => [k, v.map((i) => i.code)]));
    expect(ts).toEqual(migrationCodes());
  });
});

describe("wordsToCents", () => {
  it("parses fractions over 100", () => {
    expect(wordsToCents("One Million Two Hundred Thousand and 50/100 Dollars")).toBe(120000050);
    expect(wordsToCents("Fifteen Thousand Two Hundred Dollars and 00/100")).toBe(1520000);
  });
  it("parses 'only' and plain dollars", () => {
    expect(wordsToCents("Twelve thousand dollars only")).toBe(1200000);
  });
  it("parses hyphens, commas and cents", () => {
    expect(wordsToCents("Ninety-Nine Thousand, Nine Hundred Ninety-Nine Dollars and Ninety-Nine Cents")).toBe(9999999);
  });
  it("returns null for anything it can't parse", () => {
    expect(wordsToCents("asdf qwerty")).toBeNull();
    expect(wordsToCents("")).toBeNull();
    expect(wordsToCents("Twelve bananas")).toBeNull();
  });
});

describe("namesMatch", () => {
  it("ignores case, punctuation and company suffix spelling", () => {
    expect(namesMatch("Ridgeback Builders LLC", "RIDGEBACK BUILDERS, L.L.C.")).toBe(true);
    expect(namesMatch("Ridgeback Builders LLC", "Ridgeback Builders Inc")).toBe(true);
  });
  it("rejects a different company", () => {
    expect(namesMatch("Ridgeback Builders LLC", "Granite Mesa Contractors")).toBe(false);
  });
});

describe("coversDate", () => {
  it("is false when coverage ends before the due date", () => {
    expect(coversDate("2026-01-01", "2026-12-01", "2026-12-04")).toBe(false);
  });
  it("is true when the due date is inside", () => {
    expect(coversDate("01/01/2026", "12/31/2026", "2026-12-04")).toBe(true);
  });
  it("is null when a date is missing", () => {
    expect(coversDate(null, "2026-12-31", "2026-12-04")).toBeNull();
  });
});

describe("addendaMatch", () => {
  it("parses lists", () => {
    expect(addendaMatch("1 and 2", [1, 2])).toBe(true);
    expect(addendaMatch("#1, #2", [1, 2])).toBe(true);
    expect(addendaMatch("1", [1, 2])).toBe(false);
    expect(addendaMatch("None", [])).toBe(true);
  });
  it("is null when unreadable", () => {
    expect(addendaMatch(null, [1])).toBeNull();
  });
  it("ignores dates and reads ranges (final review #3)", () => {
    expect(addendaMatch("Addendum No. 1 dated 11/05/2026", [1])).toBe(true);
    expect(addendaMatch("#1, #2 (2026-11-10)", [1, 2])).toBe(true);
    expect(addendaMatch("1 through 3", [1, 2, 3])).toBe(true);
    expect(addendaMatch("Addenda 1-3", [1, 2, 3])).toBe(true);
    expect(addendaMatch("1 through 3", [1, 2])).toBe(false);
  });
});

const FACTS: Facts = {
  legalName: "Juniper Ridge Construction Inc",
  baseTotalCents: 120000050,
  publishedAddenda: [1],
  submittedFormVersion: 2,
  residentCertificate: null,
  agencyName: "Calder Department of Corrections",
  dueLocalDate: "2026-12-04",
};

describe("evaluate", () => {
  it("makes every item unclear for invalid model output (Review Focus 1)", () => {
    for (const bad of ["not json", null, { items: "x" }, { items: [{ code: "signature_present", result: "maybe" }] }]) {
      const items = evaluate("signed_form", bad, FACTS);
      expect(items.every((i) => i.result === "unclear")).toBe(true);
    }
  });

  it("reports an item the model left out as unclear", () => {
    const items = evaluate("insurance", { items: [{ code: "insured_name", result: "met", page: 1, excerpt: "x",
      extracted: "Juniper Ridge Construction, Inc." }] }, FACTS);
    const dates = items.find((i) => i.code === "coverage_dates");
    expect(dates?.result).toBe("unclear");
    expect(dates?.detail).toBe("The model did not report this item.");
    expect(items.find((i) => i.code === "insured_name")?.result).toBe("met");
  });

  it("uses the rule, not the model, for a rule item", () => {
    const items = evaluate("signed_form", { items: [
      { code: "amount_in_words", result: "met", page: 3, excerpt: "Twelve thousand", extracted: "Twelve thousand dollars" },
    ] }, FACTS);
    const amount = items.find((i) => i.code === "amount_in_words")!;
    expect(amount.result).toBe("not_met");
    expect(amount.method).toBe("rule");
  });

  it("is unclear when a rule item's extraction can't be parsed", () => {
    const items = evaluate("signed_form", { items: [
      { code: "amount_in_words", result: "met", page: 3, excerpt: "smudged", extracted: "smudged" },
    ] }, FACTS);
    expect(items.find((i) => i.code === "amount_in_words")!.result).toBe("unclear");
  });

  it("truncates excerpts to 300 characters", () => {
    const items = evaluate("qualifications", { items: [
      { code: "document_matches_slot", result: "met", page: 1, excerpt: "x".repeat(500), extracted: null },
    ] }, FACTS);
    expect(items[0].excerpt).toHaveLength(300);
  });

  it("drops resident_certificate when the bid doesn't claim residency", () => {
    const items = evaluate("signed_form", { items: [] }, FACTS);
    expect(items.some((i) => i.code === "resident_certificate")).toBe(false);
    const claimed = evaluate("signed_form", { items: [
      { code: "resident_certificate", result: "met", page: 2, excerpt: "CR-0042", extracted: "CR 0042" },
    ] }, { ...FACTS, residentCertificate: "CR-0042" });
    expect(claimed.find((i) => i.code === "resident_certificate")!.result).toBe("met");
  });

  it("covers every document kind", () => {
    const kinds: DocumentKind[] = ["signed_form", "bid_bond_scan", "insurance", "bid_bond", "qualifications",
      "references", "current_work"];
    for (const k of kinds) expect(evaluate(k, { items: [] }, FACTS).length).toBeGreaterThan(0);
  });
});
