// Publishing an addendum: render the RFB and bid form of version n and the addendum PDF, store them (and the
// attachments) under solicitations/{id}/v{n}/ in the `published` bucket, then move the current pointer through
// publish_addendum. Mirrors ../../publish.ts (publishSolicitation): all I/O is injected so it can be tested, and the
// "use server" wrapper never lets a client pass its own deps.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";
import { dateChanges, type AddendumDocContext } from "@/documents/addendumDoc";
import type { DocContext } from "@/documents/clauses";
import { loadPublishedDocContext } from "@/documents/loadPublishedDocContext";
import { chromiumRenderer, renderPdf, type PdfRenderer } from "@/documents/pdf";
import { renderAddendumHtml, renderBidFormHtml, renderRfbHtml } from "@/documents/renderHtml";
import { diffSchedule } from "@/domain/addendum/diff";
import { lockedFieldChanges } from "@/domain/addendum/lockedFields";
import { parseStoredData } from "@/domain/solicitation/schema";
import type { SolicitationData } from "@/domain/solicitation/types";
import { validate, type Issue } from "@/domain/solicitation/validate";
import { todayIn, toUtc } from "@/domain/time";
import { INVALID_STORED_DATA, messageFor } from "../../logic";
import {
  cleanUpFailedPublish, copyAttachmentsTo, loadPublishSettings, publicSnapshot, supabasePublishStorage,
  type PublishStorage,
} from "../../publishShared";

export type PublishAddendumResult =
  | { ok: true; number: number }
  | { ok: false; message: string; errors: Issue[] };

export interface AddendumPublishRow {
  solicitationId: string;
  number: number;
  state: string;
  reviewerId: string | null;
  checkerId: string | null;
  narrative: string;
  /** null when the stored data does not match the schema (never thrown: publish returns a typed error). */
  data: SolicitationData | null;
}

export interface PublishAddendumStorage extends PublishStorage {
  /** Every object name under a published-bucket folder, at any depth. */
  list(prefix: string): Promise<string[]>;
}

export interface PublishAddendumDeps {
  now(): Date;
  /** The signed-in user (must be the addendum's reviewer or checker). */
  viewerId: string;
  renderer: PdfRenderer;
  loadAddendum(id: string): Promise<AddendumPublishRow | null>;
  settings(): Promise<{ tz: string; holidays: string[] }>;
  /** The solicitation's current published version: number, version, snapshot data, clauses and settings. */
  loadPublishedDocContext(solicitationId: string): Promise<DocContext>;
  /** The addendum's answered questions, as published (no names), in asked order. */
  loadAnswers(addendumId: string): Promise<{ publishedQuestion: string; answer: string }[]>;
  storage: PublishAddendumStorage;
  /** Calls publish_addendum as the signed-in user; returns the new version; throws Error(<database error code>). */
  publishRpc(args: {
    p_addendum_id: string; p_rfb_path: string; p_bid_form_path: string; p_addendum_path: string;
    p_snapshot: unknown; p_bid_due_at: string;
    /** Sent on its own: the snapshot is public and the funding amount is confidential (Ruling 2). */
    p_funding_cents: number;
  }): Promise<number>;
}

const fail = (message: string, errors: Issue[] = []): PublishAddendumResult => ({ ok: false, message, errors });

const LOCKED_MESSAGE = "An addendum can't change this field.";

export async function publishAddendum(addendumId: string, d: PublishAddendumDeps): Promise<PublishAddendumResult> {
  const uploaded: string[] = [];
  try {
    const row = await d.loadAddendum(addendumId);
    if (!row) return fail("That addendum was not found.");
    if (row.state !== "approved") return fail(messageFor(new Error("invalid_state")));
    if (d.viewerId !== row.reviewerId && d.viewerId !== row.checkerId) return fail(messageFor(new Error("not_authorized")));
    if (row.data === null) return fail(INVALID_STORED_DATA);
    const data = row.data;
    const sid = row.solicitationId;

    const current = await d.loadPublishedDocContext(sid);
    if (!current.number || current.version === null) return fail(messageFor(new Error("invalid_state")));

    // Locked fields first (the addendum validator skips their rules), then the addendum-mode validator.
    const now = d.now();
    const { tz, holidays } = await d.settings();
    const locked: Issue[] = lockedFieldChanges(current.data, data)
      .map((field) => ({ code: "locked_field", field, message: LOCKED_MESSAGE }));
    if (locked.length > 0) return fail(messageFor(new Error("locked_field")), locked);
    const { errors } = validate(data, { tz, holidays, submissionDate: todayIn(tz, now), mode: "addendum", now });
    if (errors.length > 0) return fail("Fix every problem before publishing.", errors);
    if (data.bidDueDate === null || data.fundingAmountCents === null) return fail(messageFor(new Error("invalid_data")));
    const fundingCents = data.fundingAmountCents;
    const bidDueAt = toUtc(data.bidDueDate, data.bidDueTime, tz);

    // Version n = current + 1 = addendum number + 1 (publish_addendum checks both).
    const version = current.version + 1;
    if (row.number !== version - 1) return fail(messageFor(new Error("invalid_state")));
    const base = `solicitations/${sid}/v${version}`;
    const rfbPath = `${base}/rfb.pdf`;
    const bidFormPath = `${base}/bid-form.pdf`;
    const addendumPath = `${base}/addendum.pdf`;

    const docCtx: DocContext = { ...current, data, version };
    const addendumCtx: AddendumDocContext = {
      number: row.number,
      version,
      solicitationNumber: current.number,
      title: data.longTitle,
      publishedOn: todayIn(tz, now),
      narrative: row.narrative,
      changes: diffSchedule(current.data.schedule, data.schedule),
      dateChanges: dateChanges(current.data, data, tz),
      answers: await d.loadAnswers(addendumId),
    };
    const rfb = await renderPdf(renderRfbHtml(docCtx, { draft: false }), d.renderer);
    const bidForm = await renderPdf(renderBidFormHtml(docCtx, { draft: false }), d.renderer);
    const addendum = await renderPdf(renderAddendumHtml(addendumCtx), d.renderer);

    // R18: a crashed earlier attempt may have left objects in this unpublished folder. Best effort: putObject also
    // replaces a leftover it collides with.
    try {
      const leftovers = [rfbPath, bidFormPath, addendumPath, ...(await d.storage.list(`${base}/attachments`))];
      await d.storage.remove(leftovers);
    } catch (sweepError) {
      console.error("publish addendum: leftover sweep failed", sweepError);
    }

    for (const [path, bytes] of [[rfbPath, rfb], [bidFormPath, bidForm], [addendumPath, addendum]] as const) {
      uploaded.push(path);
      await d.storage.put(path, bytes, "application/pdf");
    }

    // The addendum's attachments are attachments-bucket paths; copy each next to the PDFs, as v1 does.
    const attachments = await copyAttachmentsTo(base, sid, data.attachments, d.storage, uploaded);

    // The snapshot is publicly readable, so the confidential funding amount stays out of it (Ruling 2).
    await d.publishRpc({
      p_addendum_id: addendumId, p_rfb_path: rfbPath, p_bid_form_path: bidFormPath, p_addendum_path: addendumPath,
      p_snapshot: publicSnapshot(data, attachments, current, now), p_bid_due_at: bidDueAt.toISOString(),
      p_funding_cents: fundingCents,
    });
    return { ok: true, number: row.number };
  } catch (e) {
    await cleanUpFailedPublish(d.storage, uploaded, e, "publish addendum");
    return fail(messageFor(e));
  }
}

// ---------------------------------------------------------------------------
// Real dependencies, bound to the caller's own client (RLS applies; never the admin client).
// ---------------------------------------------------------------------------

export function supabasePublishAddendumDeps(supabase: SupabaseClient<Database>, viewerId: string): PublishAddendumDeps {
  const published = supabase.storage.from("published");

  async function listAll(prefix: string): Promise<string[]> {
    const { data, error } = await published.list(prefix, { limit: 1000 });
    if (error) throw new Error(error.message);
    const out: string[] = [];
    for (const entry of data ?? []) {
      const path = `${prefix}/${entry.name}`;
      // Folders come back without an id.
      if (entry.id === null) out.push(...(await listAll(path)));
      else out.push(path);
    }
    return out;
  }

  return {
    now: () => new Date(),
    viewerId,
    renderer: chromiumRenderer(),
    async loadAddendum(id) {
      const { data, error } = await supabase
        .from("addenda")
        .select("solicitation_id, number, state, reviewer_id, checker_id, narrative, data")
        .eq("id", id)
        .maybeSingle();
      if (error) throw new Error(error.message);
      if (!data) return null;
      return {
        solicitationId: data.solicitation_id,
        number: data.number,
        state: data.state,
        reviewerId: data.reviewer_id,
        checkerId: data.checker_id,
        narrative: data.narrative,
        data: parseStoredData(data.data),
      };
    },
    settings: () => loadPublishSettings(supabase),
    // Clauses stay at the versions locked at v1 (spec §2), which is what the current snapshot holds.
    loadPublishedDocContext: (sid) => loadPublishedDocContext(supabase, sid),
    async loadAnswers(addendumId) {
      const { data, error } = await supabase.rpc("addendum_answers_draft", { p_addendum_id: addendumId });
      if (error) throw new Error(error.message);
      return (data ?? []).map((a) => ({ publishedQuestion: a.published_question, answer: a.answer }));
    },
    storage: { ...supabasePublishStorage(supabase), list: listAll },
    async publishRpc(args) {
      const { data, error } = await supabase.rpc("publish_addendum", args as never);
      if (error) throw new Error(error.message);
      return data as number;
    },
  };
}
