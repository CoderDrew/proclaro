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

export interface PublishStorage {
  /** Writes a new object (never overwrites). */
  put(path: string, bytes: Uint8Array, contentType: string): Promise<void>;
  /** Copies an object from the attachments bucket into the published bucket. */
  copyAttachment(from: string, to: string): Promise<void>;
  /** Deletes published objects. Best effort is the caller's concern. */
  remove(paths: string[]): Promise<void>;
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
    const prefix = `solicitations/${id}/`;
    const attachments = [];
    for (const a of ctx.data.attachments) {
      if (!a.storagePath.startsWith(prefix) || a.storagePath.includes("..")) {
        throw new Error("invalid_attachment_path");
      }
      const to = `${base}/attachments/${a.storagePath.slice(prefix.length)}`;
      uploaded.push(to);
      await d.storage.copyAttachment(a.storagePath, to);
      attachments.push({ ...a, storagePath: to });
    }

    // The snapshot is publicly readable, so the confidential funding amount stays out of it (Ruling 2).
    const { fundingAmountCents: _confidential, ...publicData } = ctx.data;
    void _confidential;
    const snapshot = {
      data: { ...publicData, attachments },
      clauses: ctx.clauses,
      settings: ctx.settings,
      renderedAt: d.now().toISOString(),
    };
    await d.publishRpc({
      p_id: id, p_rfb_path: rfbPath, p_bid_form_path: bidFormPath,
      p_snapshot: JSON.parse(JSON.stringify(snapshot)), p_bid_due_at: bidDueAt.toISOString(),
      p_funding_cents: fundingCents,
    });
    return { ok: true, number: ctx.number };
  } catch (e) {
    if (uploaded.length > 0) {
      try {
        await d.storage.remove(uploaded);
      } catch (cleanupError) {
        console.error("publish cleanup failed; orphaned objects:", uploaded, cleanupError);
      }
    }
    if (!(e instanceof Error) || !/^[a-z_]+$/.test(e.message)) console.error("publish failed", e);
    return fail(messageFor(e));
  }
}

// ---------------------------------------------------------------------------
// Real dependencies, bound to the caller's own client (RLS applies; never the admin client).
// ---------------------------------------------------------------------------

interface BucketLike {
  upload(path: string, body: Uint8Array, opts: { upsert: boolean; contentType?: string }):
    Promise<{ error: { message: string; statusCode?: string } | null }>;
  remove(paths: string[]): Promise<{ error: { message: string } | null }>;
}

const isDuplicate = (e: { message: string; statusCode?: string }) =>
  e.statusCode === "409" || /already exists|duplicate/i.test(e.message);

/**
 * Writes a new object with upsert off (there is no storage UPDATE policy). If an object is left over from an
 * earlier failed attempt whose cleanup also failed, it is deleted first (office may delete unpublished objects).
 */
export async function putObject(bucket: BucketLike, path: string, bytes: Uint8Array, contentType: string) {
  let { error } = await bucket.upload(path, bytes, { upsert: false, contentType });
  if (error && isDuplicate(error)) {
    const removed = await bucket.remove([path]);
    if (removed.error) throw new Error(removed.error.message);
    ({ error } = await bucket.upload(path, bytes, { upsert: false, contentType }));
  }
  if (error) throw new Error(error.message);
}

export function supabasePublishDeps(supabase: SupabaseClient<Database>, viewerId: string): PublishDeps {
  const published = supabase.storage.from("published");
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
    async settings() {
      const [settings, holidays] = await Promise.all([
        supabase.from("settings").select("timezone").eq("id", 1).single(),
        supabase.from("holidays").select("day"),
      ]);
      if (settings.error) throw new Error(settings.error.message);
      if (holidays.error) throw new Error(holidays.error.message);
      return { tz: settings.data.timezone, holidays: holidays.data.map((h) => h.day) };
    },
    loadDocContext: (id) => loadDocContext(supabase, id, { useLocks: true }),
    storage: {
      put: (path, bytes, contentType) => putObject(published, path, bytes, contentType),
      async copyAttachment(from, to) {
        const { data, error } = await supabase.storage.from("attachments").download(from);
        if (error || !data) throw new Error(error?.message ?? "attachment_download_failed");
        await putObject(published, to, new Uint8Array(await data.arrayBuffer()), data.type || "application/octet-stream");
      },
      async remove(paths) {
        const { error } = await published.remove(paths);
        if (error) throw new Error(error.message);
      },
    },
    async publishRpc(args) {
      const { error } = await supabase.rpc("publish_solicitation", args as never);
      if (error) throw new Error(error.message);
    },
  };
}
