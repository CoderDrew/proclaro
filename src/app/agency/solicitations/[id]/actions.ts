"use server";

import { randomUUID } from "node:crypto";
import { parseStoredData } from "@/domain/solicitation/schema";
import { todayIn } from "@/domain/time";
import { createServerClient } from "@/lib/supabase/server";
import { requireAgencyAction } from "../../guard";
import { prepareDraftData, runSubmit, safeFileName, type SubmitResult } from "./logic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function assertId(id: string) {
  if (typeof id !== "string" || !UUID.test(id)) throw new Error("not_found");
}

/** The draft row as the caller's client sees it. RLS hides other agencies' rows (-> not_found). */
async function loadOwnRow(id: string) {
  const supabase = await createServerClient();
  const { data, error } = await supabase
    .from("solicitations")
    .select("id, state, data")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error("not_found");
  return { supabase, row: data };
}

export async function saveDraft(id: string, data: unknown): Promise<void> {
  await requireAgencyAction();
  assertId(id);
  const parsed = prepareDraftData(id, data);
  const supabase = await createServerClient();
  // RLS limits updates to the caller's own agency drafts; the state filter makes a stale save fail loudly.
  const { data: updated, error } = await supabase
    .from("solicitations")
    .update({ data: JSON.parse(JSON.stringify(parsed)) })
    .eq("id", id)
    .eq("state", "draft")
    .select("id");
  if (error) throw new Error(error.message);
  if (!updated || updated.length !== 1) throw new Error("invalid_state");
}

export async function createUploadUrl(id: string, fileName: string): Promise<{ path: string; token: string }> {
  await requireAgencyAction();
  assertId(id);
  const { supabase, row } = await loadOwnRow(id);
  if (row.state !== "draft") throw new Error("invalid_state");
  const path = `solicitations/${id}/${randomUUID().slice(0, 8)}-${safeFileName(String(fileName))}`;
  // Storage insert policy (agency, not published) is evaluated with the caller's JWT.
  const { data, error } = await supabase.storage.from("attachments").createSignedUploadUrl(path);
  if (error || !data) throw new Error(error?.message ?? "upload_url_failed");
  return { path: data.path, token: data.token };
}

export async function acknowledgeWarning(id: string, code: string, field: string | null): Promise<void> {
  await requireAgencyAction();
  assertId(id);
  const supabase = await createServerClient();
  const { error } = await supabase.rpc("acknowledge_warning", {
    p_id: id,
    p_code: code,
    // The database function does not normalize '' to null, so do it here.
    p_field: field === null || field === "" ? (null as unknown as string) : field,
  });
  if (error) throw new Error(error.message);
}

export async function submitSolicitation(id: string): Promise<SubmitResult> {
  await requireAgencyAction();
  assertId(id);
  const supabase = await createServerClient();
  return runSubmit(id, {
    async loadData(sid) {
      const { data, error } = await supabase
        .from("solicitations")
        .select("state, data")
        .eq("id", sid)
        .maybeSingle();
      if (error) throw new Error(error.message);
      if (!data) return null;
      const parsed = parseStoredData(data.data);
      if (!parsed) throw new Error("invalid_data");
      return { state: data.state, data: parsed };
    },
    async validationContext() {
      const [settings, holidays] = await Promise.all([
        supabase.from("settings").select("timezone").eq("id", 1).single(),
        supabase.from("holidays").select("day"),
      ]);
      if (settings.error) throw new Error(settings.error.message);
      if (holidays.error) throw new Error(holidays.error.message);
      const tz = settings.data.timezone;
      return { tz, holidays: holidays.data.map((h) => h.day), submissionDate: todayIn(tz, new Date()) };
    },
    async loadAcks(sid) {
      const { data, error } = await supabase.from("warning_acks").select("code, field").eq("solicitation_id", sid);
      if (error) throw new Error(error.message);
      return data;
    },
    async submit(sid) {
      const { error } = await supabase.rpc("submit_solicitation", { p_id: sid });
      if (error) throw new Error(error.message);
    },
  });
}
