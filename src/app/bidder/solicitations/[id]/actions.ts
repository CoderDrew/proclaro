"use server";

import { randomUUID } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import { parseStoredData } from "@/domain/solicitation/schema";
import type { BidBondChoice } from "@/domain/bid/types";
import type { Database } from "@/lib/supabase/database.types";
import { createServerClient } from "@/lib/supabase/server";
import { requireBidderAction } from "../../guard";
import {
  bidMessageFor, bidUploadPath, denialFrom, isUploadSlot, isUuid, parseBiddingState, runAttachFile, runRemoveFile, runSavePrices, runSetBondChoice,
  runSubmitBid, toBidDraft, toResult, type BidActionResult, type BidReceipt, type FileDeps,
} from "./logic";

type Supabase = SupabaseClient<Database>;

function assertBidId(bidId: string) {
  if (!isUuid(bidId)) throw new Error("not_found");
}

/**
 * Why a write the caller's RLS refused was refused, as an error code for the message. Reads only what the caller
 * can already see, and asks the database (bidding_state) whether bidding is closed: the web server's clock never
 * decides. (The database decided; this only words it.)
 */
async function denialCode(supabase: Supabase, bidId: string): Promise<string> {
  const bid = await supabase.from("bids").select("solicitation_id").eq("id", bidId).maybeSingle();
  if (bid.error || !bid.data) return denialFrom({ bidVisible: false, state: "not_open", hasDraft: false });
  const [state, draft] = await Promise.all([
    supabase.rpc("bidding_state", { p_solicitation_id: bid.data.solicitation_id }),
    supabase.from("bid_drafts").select("bid_id").eq("bid_id", bidId).maybeSingle(),
  ]);
  return denialFrom({ bidVisible: true, state: parseBiddingState(state.data), hasDraft: !!draft.data });
}

/** Starts (or returns) the caller's bid on a solicitation: the start_bid database function does the checks. */
export async function startBid(solicitationId: string): Promise<BidActionResult<{ bidId: string }>> {
  return toResult(async () => {
    await requireBidderAction();
    if (!isUuid(solicitationId)) throw new Error("not_found");
    const supabase = await createServerClient();
    const { data, error } = await supabase.rpc("start_bid", { p_solicitation_id: solicitationId });
    if (error) throw new Error(error.message);
    return { ok: true, bidId: data };
  });
}

export async function saveBidPrices(
  bidId: string, input: { items: string[]; alternates: string[] },
): Promise<BidActionResult> {
  return toResult(async () => {
    await requireBidderAction();
    assertBidId(bidId);
    const supabase = await createServerClient();
    return runSavePrices(input, {
      async schedule() {
        const bid = await supabase.from("bids").select("solicitation_id").eq("id", bidId).maybeSingle();
        if (bid.error) throw new Error(bid.error.message);
        if (!bid.data) return null;
        const sol = await supabase.from("solicitations").select("published_snapshot").eq("id", bid.data.solicitation_id).maybeSingle();
        if (sol.error) throw new Error(sol.error.message);
        const snap = sol.data?.published_snapshot as { data?: unknown } | null | undefined;
        const data = parseStoredData(snap?.data);
        return data ? { items: data.schedule.items.length, alternates: data.schedule.alternates.length } : null;
      },
      async save(items, alternates) {
        const { data, error } = await supabase
          .from("bid_drafts")
          .update({ item_cents: items as number[], alternate_cents: alternates as number[] })
          .eq("bid_id", bidId)
          .select("bid_id");
        if (error) throw new Error(error.message);
        if (!data || data.length !== 1) throw new Error(await denialCode(supabase, bidId));
      },
    });
  });
}

function fileDeps(supabase: Supabase): FileDeps {
  return {
    async existingPath(bidId, slot) {
      const { data, error } = await supabase
        .from("bid_draft_files").select("path").eq("bid_id", bidId).eq("slot", slot).maybeSingle();
      if (error) throw new Error(error.message);
      return data?.path ?? null;
    },
    async removeObject(path) {
      const { error } = await supabase.storage.from("bid-files").remove([path]);
      if (error) throw new Error(error.message);
    },
    async deleteRow(bidId, slot) {
      const { data, error } = await supabase
        .from("bid_draft_files").delete().eq("bid_id", bidId).eq("slot", slot).select("slot");
      if (error) throw new Error(error.message);
      if (!data || data.length === 0) throw new Error(await denialCode(supabase, bidId));
    },
    async insertRow(bidId, slot, path, fileName) {
      const { error } = await supabase
        .from("bid_draft_files").insert({ bid_id: bidId, slot, path, file_name: fileName });
      if (!error) return;
      // 42501: RLS refused (closed or not the caller's bid). 23503: no draft row to hang the file on.
      if (error.code === "42501") throw new Error(await denialCode(supabase, bidId));
      if (error.code === "23503") throw new Error("invalid_state");
      throw new Error(error.message);
    },
  };
}

/**
 * A signed upload URL for one file. The file goes browser -> Storage, never through an action body. The Storage
 * insert policy (the caller's own bid, bidding open) is evaluated with the caller's JWT. Throws a plain-language
 * message, like the agency createUploadUrl.
 */
export async function createBidUploadUrl(
  bidId: string, slot: string, fileName: string,
): Promise<{ path: string; token: string }> {
  try {
    await requireBidderAction();
    assertBidId(bidId);
    if (!isUploadSlot(slot)) throw new Error("invalid_upload_slot");
    const supabase = await createServerClient();
    const path = bidUploadPath(bidId, randomUUID(), String(fileName));
    const { data, error } = await supabase.storage.from("bid-files").createSignedUploadUrl(path);
    if (error || !data) throw new Error(await denialCode(supabase, bidId));
    return { path: data.path, token: data.token };
  } catch (e) {
    throw new Error(bidMessageFor(e));
  }
}

/** Records an uploaded file in its slot, replacing any earlier file for that slot. */
export async function attachBidFile(bidId: string, slot: string, path: string, fileName: string): Promise<BidActionResult> {
  return toResult(async () => {
    await requireBidderAction();
    assertBidId(bidId);
    return runAttachFile(bidId, slot, path, fileName, fileDeps(await createServerClient()));
  });
}

export async function removeBidFile(bidId: string, slot: string): Promise<BidActionResult> {
  return toResult(async () => {
    await requireBidderAction();
    assertBidId(bidId);
    return runRemoveFile(bidId, slot, fileDeps(await createServerClient()));
  });
}

export async function setBidBondChoice(bidId: string, choice: BidBondChoice | null): Promise<BidActionResult> {
  return toResult(async () => {
    await requireBidderAction();
    assertBidId(bidId);
    const supabase = await createServerClient();
    return runSetBondChoice(bidId, choice, {
      ...fileDeps(supabase),
      async setChoice(id, c) {
        const { data, error } = await supabase
          .from("bid_drafts").update({ bid_bond_choice: c }).eq("bid_id", id).select("bid_id");
        if (error) throw new Error(error.message);
        if (!data || data.length !== 1) throw new Error(await denialCode(supabase, id));
      },
    });
  });
}

/** Submits the stored draft. The draft is loaded and re-validated here; the database does the final checks. */
export async function submitBid(bidId: string): Promise<Awaited<ReturnType<typeof runSubmitBid>>> {
  try {
    await requireBidderAction();
    assertBidId(bidId);
    const supabase = await createServerClient();
    return await runSubmitBid(bidId, {
      async loadDraft(id) {
        const bid = await supabase.from("bids").select("id, reference, solicitation_id").eq("id", id).maybeSingle();
        if (bid.error) throw new Error(bid.error.message);
        if (!bid.data) return null;
        const [draft, files, sol] = await Promise.all([
          supabase.from("bid_drafts").select("version, item_cents, alternate_cents, bid_bond_choice").eq("bid_id", id).maybeSingle(),
          supabase.from("bid_draft_files").select("slot, path, file_name").eq("bid_id", id),
          supabase.from("solicitations").select("published_snapshot").eq("id", bid.data.solicitation_id).maybeSingle(),
        ]);
        for (const r of [draft, files, sol]) if (r.error) throw new Error(r.error.message);
        const data = parseStoredData((sol.data?.published_snapshot as { data?: unknown } | null | undefined)?.data);
        if (!draft.data || !data) return null;
        return { draft: toBidDraft(bid.data, draft.data, files.data ?? []), data };
      },
      async submit(id): Promise<BidReceipt> {
        const { data, error } = await supabase.rpc("submit_bid", { p_bid_id: id });
        if (error) throw new Error(error.message);
        const r = data?.[0];
        if (!r) throw new Error("invalid_state");
        // A fresh submit is the current version and not withdrawn.
        return { reference: r.reference, version: r.version, submittedAt: r.submitted_at, withdrawnAt: null, isCurrent: true };
      },
    });
  } catch (e) {
    console.error("submitBid failed", e);
    return { ok: false, message: bidMessageFor(e) };
  }
}

/** Starts a new, empty draft as the next version. */
export async function replaceBid(bidId: string): Promise<BidActionResult> {
  return toResult(async () => {
    await requireBidderAction();
    assertBidId(bidId);
    const supabase = await createServerClient();
    const { error } = await supabase.rpc("replace_bid", { p_bid_id: bidId });
    if (error) throw new Error(error.message);
    return { ok: true };
  });
}

/** Withdraws the latest version. A new version can still be submitted before the due time. */
export async function withdrawBid(bidId: string): Promise<BidActionResult> {
  return toResult(async () => {
    await requireBidderAction();
    assertBidId(bidId);
    const supabase = await createServerClient();
    const { error } = await supabase.rpc("withdraw_bid", { p_bid_id: bidId });
    if (error) throw new Error(error.message);
    return { ok: true };
  });
}
