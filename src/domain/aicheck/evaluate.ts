// The model's response plus the portal's facts, to the items stored for one document. The model decides "ai" items;
// for "rule" items only its extracted value is used, and a rule compares it. Anything unreadable is "unclear".
import { z } from "zod";
import { CHECKLIST, type DocumentKind } from "./checklist";
import { wordsToCents } from "./words";
import { addendaMatch, certificateMatch, coversDate, nameIncludes, namesMatch, splitRange, versionMatch } from "./rules";

export type CheckResult = "met" | "not_met" | "unclear";

export interface Facts {
  legalName: string;
  baseTotalCents: number;
  publishedAddenda: number[];
  submittedFormVersion: number;
  residentCertificate: string | null;
  agencyName: string;
  dueLocalDate: string;
}

export interface CheckItem {
  code: string;
  method: "ai" | "rule";
  result: CheckResult;
  page: number | null;
  excerpt: string | null;
  extracted: string | null;
  detail: string | null;
}

const modelItem = z.object({
  code: z.string(),
  result: z.enum(["met", "not_met", "unclear"]),
  page: z.number().int().positive().nullable().optional(),
  excerpt: z.string().nullable().optional(),
  extracted: z.string().nullable().optional(),
});
const modelResponse = z.object({ items: z.array(modelItem) });
export type ModelItem = z.infer<typeof modelItem>;

export const NOT_REPORTED = "The model did not report this item.";
export const UNREADABLE = "The model's response could not be read.";

const fromBool = (b: boolean | null): CheckResult => (b === null ? "unclear" : b ? "met" : "not_met");

function rule(code: string, extracted: string | null, f: Facts): { result: CheckResult; detail: string | null } {
  switch (code) {
    case "amount_in_words": {
      const cents = extracted ? wordsToCents(extracted) : null;
      if (cents === null) return { result: "unclear", detail: "The amount in words could not be read." };
      return { result: fromBool(cents === f.baseTotalCents),
               detail: cents === f.baseTotalCents ? null : "The amount in words differs from the portal total." };
    }
    case "addenda_listed": {
      const r = addendaMatch(extracted, f.publishedAddenda);
      return { result: fromBool(r), detail: r === false ? "The addenda listed differ from the published addenda." : null };
    }
    case "form_version": {
      const r = versionMatch(extracted, f.submittedFormVersion);
      return { result: fromBool(r), detail: r === false ? "The form's version differs from the version submitted." : null };
    }
    case "resident_certificate": {
      const r = f.residentCertificate === null ? null : certificateMatch(extracted, f.residentCertificate);
      return { result: fromBool(r), detail: r === false ? "The certificate number differs from the claim." : null };
    }
    case "insured_name":
    case "principal_name": {
      const r = extracted && extracted.trim() !== "" ? namesMatch(extracted, f.legalName) : null;
      return { result: fromBool(r), detail: r === false ? "The name differs from the bidder's legal name." : null };
    }
    case "obligee": {
      const r = nameIncludes(extracted, f.agencyName);
      return { result: fromBool(r), detail: r === false ? "The obligee is not the agency." : null };
    }
    case "coverage_dates": {
      const [from, to] = splitRange(extracted);
      const r = coversDate(from, to, f.dueLocalDate);
      return { result: fromBool(r), detail: r === false ? "Coverage is not in force on the bid due date." : null };
    }
    default:
      return { result: "unclear", detail: null };
  }
}

export function evaluate(kind: DocumentKind, model: unknown, facts: Facts): CheckItem[] {
  let raw = model;
  if (typeof raw === "string") {
    try { raw = JSON.parse(raw); } catch { raw = null; }
  }
  const parsed = modelResponse.safeParse(raw);
  const byCode = new Map<string, ModelItem>(parsed.success ? parsed.data.items.map((i) => [i.code, i]) : []);
  const specs = CHECKLIST[kind].filter((s) => s.code !== "resident_certificate" || facts.residentCertificate !== null);

  return specs.map((spec) => {
    const m = byCode.get(spec.code);
    if (!parsed.success || !m) {
      return { code: spec.code, method: spec.method, result: "unclear", page: null, excerpt: null, extracted: null,
               detail: parsed.success ? NOT_REPORTED : UNREADABLE };
    }
    const base = { code: spec.code, method: spec.method, page: m.page ?? null,
                   excerpt: m.excerpt == null ? null : m.excerpt.slice(0, 300), extracted: m.extracted ?? null };
    if (spec.method === "ai") return { ...base, result: m.result, detail: null };
    return { ...base, ...rule(spec.code, base.extracted, facts) };
  });
}
