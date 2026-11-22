// The AI document check's actions, pure of Next.js: every dependency is injected, so the "use server" wrapper never
// lets a client choose its own. Postgres decides who may run a check and when (0036); this file runs one document at a
// time, so no request handles a whole bid.
import { PDFDocument } from "pdf-lib";
import { CHECKLIST, type DocumentKind } from "@/domain/aicheck/checklist";
import { evaluate, type CheckItem, type Facts } from "@/domain/aicheck/evaluate";

export type AiCheckResult<T = object> = ({ ok: true } & T) | { ok: false; message: string };

export interface AiCheckConfig { enabled: boolean; configured: boolean; model: string }
export interface CheckDocumentResult { raw: unknown; failed: boolean; errorClass?: string }

export interface AiCheckDeps {
  config(): AiCheckConfig;
  /** Calls a public function as the signed-in user; throws Error(<database error code>) on failure. */
  rpc(fn: string, args: Record<string, unknown>): Promise<unknown>;
  download(path: string): Promise<Uint8Array>;
  check(kind: DocumentKind, pdf: Uint8Array, model: string): Promise<CheckDocumentResult>;
  facts(bidId: string, solicitationId: string): Promise<Facts>;
}

export const TURNED_OFF = "Document checks are turned off.";
export const NOT_CONFIGURED = "The AI check is not configured.";
export const SCAN_NOT_ATTACHED = "Scan not attached";
export const CALL_FAILED = "The AI service did not answer. Run the check again.";
const GENERIC = "Something went wrong. Reload the page and try again.";

export const AI_CHECK_MESSAGES: Record<string, string> = {
  ai_check_running: "A check is already running for this bid.",
  ai_cap_reached: "The check limit has been reached. Try again tomorrow.",
  sealed: "Bids are still sealed.",
  scan_too_large: "The scan is larger than 20 MB.",
  not_scannable: "That log entry was voided.",
  not_authorized: "You are not allowed to do that.",
  not_found: "That bid was not found. Reload the page.",
  invalid_state: "This check is no longer running. Reload the page.",
  invalid_data: "That request was not valid. Reload the page and try again.",
  reason_required: "Give a reason for the override.",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function fail(e: unknown): { ok: false; message: string } {
  const code = e instanceof Error ? e.message : "";
  if (!(code in AI_CHECK_MESSAGES)) console.error("AI check failed", e);
  return { ok: false, message: AI_CHECK_MESSAGES[code] ?? GENERIC };
}

export async function startCheck(
  bidId: string, d: AiCheckDeps,
): Promise<AiCheckResult<{ runId: string; documents: { kind: DocumentKind; path: string | null }[] }>> {
  const cfg = d.config();
  if (!cfg.enabled) return { ok: false, message: TURNED_OFF };
  if (!cfg.configured) return { ok: false, message: NOT_CONFIGURED };
  if (!UUID.test(bidId)) return { ok: false, message: AI_CHECK_MESSAGES.invalid_data };
  try {
    const runId = (await d.rpc("start_ai_check", { p_bid_id: bidId, p_model: cfg.model })) as string;
    const rows = (await d.rpc("ai_check_documents", { p_bid_id: bidId })) as { document_kind: DocumentKind; path: string | null }[];
    return { ok: true, runId, documents: rows.map((r) => ({ kind: r.document_kind, path: r.path })) };
  } catch (e) {
    return fail(e);
  }
}

function rows(kind: DocumentKind, path: string | null, items: CheckItem[], callFailed = false) {
  return items.map((i) => ({
    document_kind: kind, document_path: path, item_code: i.code, method: i.method, result: i.result, page: i.page,
    excerpt: i.excerpt, extracted: i.extracted, detail: i.detail, call_failed: callFailed,
  }));
}

function unclearAll(kind: DocumentKind, facts: Facts | null, detail: string): CheckItem[] {
  return CHECKLIST[kind]
    .filter((s) => s.code !== "resident_certificate" || (facts?.residentCertificate ?? null) !== null)
    .map((s) => ({ code: s.code, method: s.method, result: "unclear", page: null, excerpt: null, extracted: null, detail }));
}

/**
 * Checks one document of a running run. Order matters for cost: config, then the database reservation (run ownership,
 * the document belongs to the run's bid, not already checked, the daily caps), and only then the download and the paid
 * model call. The bid and solicitation come from the reservation, never from the client.
 */
export async function checkOne(
  input: { runId: string; kind: DocumentKind; path: string | null }, d: AiCheckDeps,
): Promise<AiCheckResult<{ callFailed: boolean }>> {
  const cfg = d.config();
  if (!cfg.enabled) return { ok: false, message: TURNED_OFF };
  if (!cfg.configured) return { ok: false, message: NOT_CONFIGURED };
  if (!UUID.test(input.runId) || !Object.hasOwn(CHECKLIST, input.kind)) {
    return { ok: false, message: AI_CHECK_MESSAGES.invalid_data };
  }
  try {
    const begun = (await d.rpc("begin_ai_check_document",
      { p_run_id: input.runId, p_kind: input.kind, p_path: input.path })) as { bid_id: string; solicitation_id: string }[];
    const own = begun?.[0];
    if (!own) return { ok: false, message: AI_CHECK_MESSAGES.not_found };
    const facts = await d.facts(own.bid_id, own.solicitation_id);
    let items: ReturnType<typeof rows>;
    let callFailed = false;
    if (input.path === null) {
      items = rows(input.kind, null, unclearAll(input.kind, facts, SCAN_NOT_ATTACHED));
    } else {
      const pdf = await d.download(input.path);
      const res = await d.check(input.kind, pdf, cfg.model);
      callFailed = res.failed;
      items = res.failed
        ? rows(input.kind, input.path,
               unclearAll(input.kind, facts, `${CALL_FAILED} (${res.errorClass ?? "error"})`), true)
        : rows(input.kind, input.path, evaluate(input.kind, res.raw, facts));
    }
    await d.rpc("record_ai_check_document", { p_run_id: input.runId, p_items: items });
    return { ok: true, callFailed };
  } catch (e) {
    return fail(e);
  }
}

export async function finishCheck(runId: string, status: "done" | "failed", d: AiCheckDeps): Promise<AiCheckResult> {
  if (!UUID.test(runId)) return { ok: false, message: AI_CHECK_MESSAGES.invalid_data };
  try {
    await d.rpc("finish_ai_check", { p_run_id: runId, p_status: status });
    return { ok: true };
  } catch (e) {
    return fail(e);
  }
}

export async function reviewItem(
  itemId: string, decision: "confirm" | "override", reason: string, d: AiCheckDeps,
): Promise<AiCheckResult> {
  if (!UUID.test(itemId)) return { ok: false, message: AI_CHECK_MESSAGES.invalid_data };
  if (decision === "override" && reason.trim() === "") return { ok: false, message: AI_CHECK_MESSAGES.reason_required };
  try {
    await d.rpc("review_ai_check_item", { p_item_id: itemId, p_decision: decision, p_reason: reason.trim() || null });
    return { ok: true };
  } catch (e) {
    return fail(e);
  }
}

export async function pageCount(bytes: Uint8Array): Promise<number> {
  const doc = await PDFDocument.load(bytes, { ignoreEncryption: true });
  return doc.getPageCount();
}

/** Why a scan can't be attached, or null. Checked in the browser before upload (size is also enforced in SQL). */
export async function scanProblem(name: string, type: string, bytes: Uint8Array): Promise<string | null> {
  if (type !== "application/pdf" && !name.toLowerCase().endsWith(".pdf")) return "Attach the scan as a PDF.";
  if (bytes.byteLength > 20 * 1024 * 1024) return AI_CHECK_MESSAGES.scan_too_large;
  try {
    if ((await pageCount(bytes)) > 30) return "A scan can have at most 30 pages.";
  } catch {
    return "That file could not be read as a PDF.";
  }
  return null;
}
