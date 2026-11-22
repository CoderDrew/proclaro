"use server";

// The AI document check's server actions. Office only (requireOfficeAction, then every database function checks again).
// Dependencies are bound here to the caller's own client: never the admin client, never a client-supplied dependency.
import { createServerClient } from "@/lib/supabase/server";
import { aiCheckConfig, checkDocument } from "@/server/aicheck/openai";
import { todayIn } from "@/domain/time";
import type { DocumentKind } from "@/domain/aicheck/checklist";
import type { Facts } from "@/domain/aicheck/evaluate";
import { requireOfficeAction } from "../../../../guard";
import {
  AI_CHECK_MESSAGES, checkOne, finishCheck, reviewItem, startCheck, type AiCheckDeps, type AiCheckResult,
} from "./logic";

const NOT_AUTHORIZED = { ok: false as const, message: AI_CHECK_MESSAGES.not_authorized };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function deps(): Promise<AiCheckDeps> {
  const supabase = await createServerClient();
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await supabase.rpc(fn as never, args as never);
    if (error) throw new Error(error.message);
    return data as unknown;
  };
  return {
    config: () => aiCheckConfig(),
    rpc,
    async download(path) {
      const { data, error } = await supabase.storage.from("bid-files").download(path);
      if (error || !data) throw new Error("not_found");
      return new Uint8Array(await data.arrayBuffer());
    },
    check: (kind, pdf, model) => checkDocument(kind, pdf, { model }),
    async facts(bidId, solicitationId): Promise<Facts> {
      const [opened, addenda, check, claims, sol, settings] = await Promise.all([
        rpc("opened_bids", { p_solicitation_id: solicitationId }),
        rpc("solicitation_addenda", { p_solicitation_id: solicitationId }),
        rpc("bid_ai_check", { p_bid_id: bidId }),
        rpc("resident_claims", { p_solicitation_id: solicitationId }),
        supabase.from("solicitations").select("bid_due_at, agency_id").eq("id", solicitationId).single(),
        supabase.from("settings").select("timezone").eq("id", 1).single(),
      ]);
      const bid = (opened as { bid_id: string; bidder_name: string; base_total_cents: number }[])
        .find((b) => b.bid_id === bidId);
      if (!bid || sol.error || !sol.data?.bid_due_at) throw new Error("not_found");
      const agency = await supabase.from("organizations").select("name").eq("id", sol.data.agency_id).single();
      const claim = (claims as { bid_id: string; certificate: string | null }[]).find((c) => c.bid_id === bidId);
      const run = (check as { run: { solicitationVersion?: number } | null }).run;
      return {
        legalName: bid.bidder_name,
        baseTotalCents: Number(bid.base_total_cents),
        publishedAddenda: (addenda as { number: number; state: string }[])
          .filter((a) => a.state === "published").map((a) => a.number),
        submittedFormVersion: run?.solicitationVersion ?? 1,
        residentCertificate: claim?.certificate ?? null,
        agencyName: agency.data?.name ?? "",
        dueLocalDate: todayIn(settings.data?.timezone ?? "America/Denver", new Date(sol.data.bid_due_at)),
      };
    },
  };
}

async function guarded<T>(run: (d: AiCheckDeps) => Promise<AiCheckResult<T>>): Promise<AiCheckResult<T>> {
  try {
    await requireOfficeAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  return run(await deps());
}

export async function startAiCheck(bidId: string) {
  return guarded((d) => startCheck(bidId, d));
}

export async function checkAiDocument(input: { runId: string; kind: DocumentKind; path: string | null }) {
  return guarded((d) => checkOne(input, d));
}

export async function finishAiCheck(runId: string, status: "done" | "failed") {
  return guarded((d) => finishCheck(runId, status, d));
}

export async function reviewAiCheckItem(itemId: string, decision: "confirm" | "override", reason: string) {
  return guarded((d) => reviewItem(itemId, decision, reason, d));
}

/** A signed upload URL for a scan of a log entry (the browser checks type, size and pages before calling this). */
export async function createScanUploadUrl(
  bidId: string, logEntryId: string,
): Promise<AiCheckResult<{ path: string; token: string }>> {
  try {
    await requireOfficeAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  if (!UUID.test(bidId) || !UUID.test(logEntryId)) return { ok: false, message: AI_CHECK_MESSAGES.invalid_data };
  const supabase = await createServerClient();
  const path = `bids/${bidId}/${logEntryId}/scan-${crypto.randomUUID()}.pdf`;
  const { data, error } = await supabase.storage.from("bid-files").createSignedUploadUrl(path);
  if (error || !data) return { ok: false, message: AI_CHECK_MESSAGES.sealed };
  return { ok: true, path, token: data.token };
}

export async function attachScan(logEntryId: string, path: string): Promise<AiCheckResult> {
  return guarded(async (d) => {
    if (!UUID.test(logEntryId)) return { ok: false, message: AI_CHECK_MESSAGES.invalid_data };
    try {
      await d.rpc("attach_original_scan", { p_log_entry_id: logEntryId, p_path: path });
      return { ok: true };
    } catch (e) {
      const code = e instanceof Error ? e.message : "";
      return { ok: false, message: AI_CHECK_MESSAGES[code] ?? "Something went wrong. Reload the page and try again." };
    }
  });
}
