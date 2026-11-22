// Publishing: render the final documents from the locked clauses, store them (and the attachments) in the
// `published` bucket, then freeze the row through publish_solicitation. Pure of Next.js: all I/O is injected so it
// can be tested, and the "use server" wrapper in actions.ts never lets a client pass its own deps.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";
import type { DocContext } from "@/documents/clauses";
import { loadDocContext } from "@/documents/loadDocContext";
import { chromiumRenderer, renderPdf, type PdfRenderer } from "@/documents/pdf";
import { renderBidFormHtml, renderRfbHtml } from "@/documents/renderHtml";
import { parseStoredData } from "@/domain/solicitation/schema";
import type { SolicitationData } from "@/domain/solicitation/types";
import { toUtc } from "@/domain/time";
import { validate, type Issue } from "@/domain/solicitation/validate";
import { INVALID_STORED_DATA, messageFor, releasePassed, submissionDateOf } from "./logic";
import {
  cleanUpFailedPublish, copyAttachmentsTo, loadPublishSettings, publicSnapshot, supabasePublishStorage,
  type PublishStorage,
} from "./publishShared";

export { putObject, type PublishStorage } from "./publishShared";

export type PublishResult =
  | { ok: true; number: string }
  | { ok: false; message: string; errors: Issue[] };

export interface PublishRow {
  state: string;
  reviewerId: string | null;
  checkerId: string | null;
  latestSubmittedAt: string | null;
  /** null when the stored data does not match the schema (never thrown: publish returns a typed error). */
  data: SolicitationData | null;
}

export interface PublishDeps {
  now(): Date;
  /** The signed-in user (must be the reviewer or checker). */
  viewerId: string;
  renderer: PdfRenderer;
  loadRow(id: string): Promise<PublishRow | null>;
  settings(): Promise<{ tz: string; holidays: string[] }>;
  /** Clause bodies from the locked versions; throws when a locked version is missing. */
  loadDocContext(id: string): Promise<DocContext>;
  storage: PublishStorage;
  /** Calls publish_solicitation as the signed-in user; throws Error(<database error code>) on failure. */
  publishRpc(args: {
    p_id: string; p_rfb_path: string; p_bid_form_path: string; p_snapshot: unknown; p_bid_due_at: string;
    /** Sent on its own: the snapshot is public and the funding amount is confidential (Ruling 2). */
    p_funding_cents: number;
  }): Promise<void>;
}

const fail = (message: string, errors: Issue[] = []): PublishResult => ({ ok: false, message, errors });

export async function publishSolicitation(id: string, d: PublishDeps): Promise<PublishResult> {
  const uploaded: string[] = [];
  try {
    const row = await d.loadRow(id);
    if (!row) return fail(messageFor(new Error("not_found")));
    if (row.state !== "approved") return fail(messageFor(new Error("invalid_state")));
    if (d.viewerId !== row.reviewerId && d.viewerId !== row.checkerId) return fail(messageFor(new Error("not_authorized")));

    if (row.data === null) return fail(INVALID_STORED_DATA);
    const data = row.data;

    const { tz, holidays } = await d.settings();
    const { errors } = validate(data, { tz, holidays, submissionDate: submissionDateOf(row.latestSubmittedAt, tz) });
    // The submission anchor above is the latest submission, so "today" is checked separately.
    const passed = releasePassed(data, tz, d.now());
    if (passed) errors.unshift(passed);
    if (errors.length > 0) return fail("Fix every problem before publishing.", errors);
    if (data.bidDueDate === null || data.fundingAmountCents === null) return fail(messageFor(new Error("invalid_data")));
    const fundingCents = data.fundingAmountCents;
    const bidDueAt = toUtc(data.bidDueDate, data.bidDueTime, tz);

    const ctx = await d.loadDocContext(id);
    if (!ctx.number) return fail(messageFor(new Error("invalid_data")));
    const finalCtx: DocContext = { ...ctx, version: 1 };

    const rfb = await renderPdf(renderRfbHtml(finalCtx, { draft: false }), d.renderer);
    const bidForm = await renderPdf(renderBidFormHtml(finalCtx, { draft: false }), d.renderer);

    const base = `solicitations/${id}/v1`;
    const rfbPath = `${base}/rfb.pdf`;
    const bidFormPath = `${base}/bid-form.pdf`;
    for (const [path, bytes] of [[rfbPath, rfb], [bidFormPath, bidForm]] as const) {
      uploaded.push(path);
      await d.storage.put(path, bytes, "application/pdf");
    }

    // The attachments bucket is closed to the public (and to the agency once published), so publish copies each
    // attachment next to the PDFs and the snapshot records the published location.
    const attachments = await copyAttachmentsTo(base, id, ctx.data.attachments, d.storage, uploaded);

    // The snapshot is publicly readable, so the confidential funding amount stays out of it (Ruling 2).
    await d.publishRpc({
      p_id: id, p_rfb_path: rfbPath, p_bid_form_path: bidFormPath,
      p_snapshot: publicSnapshot(ctx.data, attachments, ctx, d.now()), p_bid_due_at: bidDueAt.toISOString(),
      p_funding_cents: fundingCents,
    });
    return { ok: true, number: ctx.number };
  } catch (e) {
    await cleanUpFailedPublish(d.storage, uploaded, e, "publish");
    return fail(messageFor(e));
  }
}

// ---------------------------------------------------------------------------
// Real dependencies, bound to the caller's own client (RLS applies; never the admin client).
// ---------------------------------------------------------------------------

export function supabasePublishDeps(supabase: SupabaseClient<Database>, viewerId: string): PublishDeps {
  return {
    now: () => new Date(),
    viewerId,
    renderer: chromiumRenderer(),
    async loadRow(id) {
      const { data, error } = await supabase
        .from("solicitations")
        .select("state, data, latest_submitted_at, reviewer_id, checker_id")
        .eq("id", id)
        .maybeSingle();
      if (error) throw new Error(error.message);
      if (!data) return null;
      return {
        state: data.state,
        reviewerId: data.reviewer_id,
        checkerId: data.checker_id,
        latestSubmittedAt: data.latest_submitted_at,
        data: parseStoredData(data.data),
      };
    },
    settings: () => loadPublishSettings(supabase),
    loadDocContext: (id) => loadDocContext(supabase, id, { useLocks: true }),
    storage: supabasePublishStorage(supabase),
    async publishRpc(args) {
      const { error } = await supabase.rpc("publish_solicitation", args as never);
      if (error) throw new Error(error.message);
    },
  };
}
