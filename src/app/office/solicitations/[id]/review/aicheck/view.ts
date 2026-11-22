// The document check panel's view model: bid_ai_check's JSON, parsed and grouped for display. Pure (client-safe).
import { CHECKLIST, DOCUMENT_LABEL, type DocumentKind } from "@/domain/aicheck/checklist";

export interface CheckRun {
  id: string;
  status: string;
  startedAt: string;
  finishedAt: string | null;
  model: string;
  recorded: boolean;
  startedByMe: boolean;
}

export interface CheckReview { decision: "confirm" | "override"; reason: string | null; reviewedAt: string; reviewedBy?: string | null }

export interface CheckItemView {
  id: string;
  documentKind: DocumentKind;
  documentPath: string | null;
  code: string;
  label: string;
  method: "ai" | "rule";
  result: "met" | "not_met" | "unclear";
  page: number | null;
  excerpt: string | null;
  extracted: string | null;
  detail: string | null;
  callFailed: boolean;
  review: CheckReview | null;
}

export interface CheckView {
  run: CheckRun | null;
  items: CheckItemView[];
  runsUsed: number;
  runsLeft: number;
  callsLeftUser: number;
  callsLeftTotal: number;
}

const ORDER: DocumentKind[] = ["signed_form", "insurance", "bid_bond", "bid_bond_scan", "qualifications", "references",
  "current_work"];

function labelFor(kind: DocumentKind, code: string): string {
  return CHECKLIST[kind]?.find((i) => i.code === code)?.label ?? code;
}

export function parseCheck(json: unknown): CheckView {
  const j = (json ?? {}) as Record<string, unknown>;
  const items = Array.isArray(j.items) ? (j.items as Record<string, unknown>[]) : [];
  return {
    run: (j.run as CheckRun | null | undefined) ?? null,
    items: items.map((i) => {
      const kind = i.documentKind as DocumentKind;
      return {
        id: String(i.id), documentKind: kind, documentPath: (i.documentPath as string | null) ?? null,
        code: String(i.code), label: labelFor(kind, String(i.code)), method: i.method === "ai" ? "ai" : "rule",
        result: (i.result as CheckItemView["result"]) ?? "unclear", page: (i.page as number | null) ?? null,
        excerpt: (i.excerpt as string | null) ?? null, extracted: (i.extracted as string | null) ?? null,
        detail: (i.detail as string | null) ?? null, callFailed: i.callFailed === true,
        review: (i.review as CheckReview | null) ?? null,
      };
    }),
    runsUsed: Number(j.runsUsed ?? 0),
    runsLeft: Number(j.runsLeft ?? 0),
    callsLeftUser: Number(j.callsLeftUser ?? 0),
    callsLeftTotal: Number(j.callsLeftTotal ?? 0),
  };
}

export interface DocumentGroup { kind: DocumentKind; label: string; path: string | null; items: CheckItemView[] }

export function groupItems(items: CheckItemView[]): DocumentGroup[] {
  const groups: DocumentGroup[] = [];
  for (const kind of ORDER) {
    const its = items.filter((i) => i.documentKind === kind);
    if (its.length === 0) continue;
    const order = CHECKLIST[kind].map((s) => s.code);
    its.sort((a, b) => order.indexOf(a.code) - order.indexOf(b.code));
    groups.push({ kind, label: DOCUMENT_LABEL[kind], path: its[0].documentPath, items: its });
  }
  return groups;
}

export function summary(items: CheckItemView[]): string {
  const notMet = items.filter((i) => i.result === "not_met").length;
  const unclear = items.filter((i) => i.result === "unclear").length;
  return `${notMet} not met · ${unclear} unclear`;
}

export function runLabel(run: CheckRun | null): string {
  if (!run) return "Not run";
  if (run.recorded) return "Recorded result";
  if (run.status === "running") return "Running";
  if (run.status === "failed") return "Failed";
  return "Checked";
}
