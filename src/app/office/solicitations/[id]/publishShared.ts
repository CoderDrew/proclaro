// Pieces shared by publishSolicitation (./publish.ts, version 1) and publishAddendum
// (./addenda/[addendumId]/publish.ts, version n). The attachment path guard and the funding exclusion are
// security-relevant, so both publish paths use these single copies.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";
import type { DocContext } from "@/documents/clauses";
import type { SolicitationData } from "@/domain/solicitation/types";

export interface PublishStorage {
  /** Writes a new object (never overwrites). */
  put(path: string, bytes: Uint8Array, contentType: string): Promise<void>;
  /** Copies an object from the attachments bucket into the published bucket. */
  copyAttachment(from: string, to: string): Promise<void>;
  /** Deletes published objects. Best effort is the caller's concern. */
  remove(paths: string[]): Promise<void>;
}

type Attachment = SolicitationData["attachments"][number];

/**
 * Copies each attachment (an attachments-bucket path under solicitations/{sid}/) to `${base}/attachments/...` in the
 * published bucket and returns the attachments with their published paths. Each destination is pushed to `uploaded`
 * before the copy, so a failure cleans it up. Throws invalid_attachment_path for a path outside the solicitation.
 */
export async function copyAttachmentsTo(
  base: string, solicitationId: string, attachments: Attachment[], storage: PublishStorage, uploaded: string[],
): Promise<Attachment[]> {
  const prefix = `solicitations/${solicitationId}/`;
  const out: Attachment[] = [];
  for (const a of attachments) {
    if (!a.storagePath.startsWith(prefix) || a.storagePath.includes("..")) {
      throw new Error("invalid_attachment_path");
    }
    const to = `${base}/attachments/${a.storagePath.slice(prefix.length)}`;
    uploaded.push(to);
    await storage.copyAttachment(a.storagePath, to);
    out.push({ ...a, storagePath: to });
  }
  return out;
}

/**
 * The publicly readable snapshot: the data with its published attachment paths and WITHOUT the confidential funding
 * amount (Ruling 2), the clauses and settings it was rendered with, and the render time. JSON round-tripped.
 */
export function publicSnapshot(
  data: SolicitationData, attachments: Attachment[], ctx: Pick<DocContext, "clauses" | "settings">, now: Date,
): unknown {
  const { fundingAmountCents: _confidential, ...publicData } = data;
  void _confidential;
  return JSON.parse(JSON.stringify({
    data: { ...publicData, attachments },
    clauses: ctx.clauses,
    settings: ctx.settings,
    renderedAt: now.toISOString(),
  }));
}

/** After a failed publish: remove what was uploaded (logging orphans), and log anything that isn't a database code. */
export async function cleanUpFailedPublish(storage: PublishStorage, uploaded: string[], e: unknown, what: string) {
  if (uploaded.length > 0) {
    try {
      await storage.remove(uploaded);
    } catch (cleanupError) {
      console.error(`${what} cleanup failed; orphaned objects:`, uploaded, cleanupError);
    }
  }
  if (!(e instanceof Error) || !/^[a-z_]+$/.test(e.message)) console.error(`${what} failed`, e);
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

/** The published-bucket storage used by both publish paths. */
export function supabasePublishStorage(supabase: SupabaseClient<Database>): PublishStorage {
  const published = supabase.storage.from("published");
  return {
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
  };
}

/** The configured time zone and holidays. */
export async function loadPublishSettings(supabase: SupabaseClient<Database>): Promise<{ tz: string; holidays: string[] }> {
  const [settings, holidays] = await Promise.all([
    supabase.from("settings").select("timezone").eq("id", 1).single(),
    supabase.from("holidays").select("day"),
  ]);
  if (settings.error) throw new Error(settings.error.message);
  if (holidays.error) throw new Error(holidays.error.message);
  return { tz: settings.data.timezone, holidays: holidays.data.map((h) => h.day) };
}
