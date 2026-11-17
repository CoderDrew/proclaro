// Pure, server-free logic behind the agency actions. Kept out of the "use server" file so it can be
// tested with injected deps and so clients can never pass their own `deps` to a server action.
import { solicitationSchema } from "@/domain/solicitation/schema";
import type { SolicitationData } from "@/domain/solicitation/types";
import { validate, type Issue, type ValidationContext } from "@/domain/solicitation/validate";

export type SubmitResult =
  | { ok: true }
  | { ok: false; errors: Issue[]; unacknowledged: Issue[] };

export interface SubmitDeps {
  /** The stored row as the caller sees it (RLS), or null when invisible. */
  loadData(id: string): Promise<{ data: SolicitationData; state: string } | null>;
  validationContext(): Promise<ValidationContext>;
  loadAcks(id: string): Promise<{ code: string; field: string | null }[]>;
  /** Calls the submit_solicitation database function. */
  submit(id: string): Promise<void>;
}

/** Warnings with no matching acknowledgment. Acks match on code and field. */
export function unacknowledgedWarnings(
  warnings: Issue[],
  acks: { code: string; field: string | null }[],
): Issue[] {
  return warnings.filter((w) => !acks.some((a) => a.code === w.code && a.field === w.field));
}

/** Re-validates from the stored row (never client data), then submits when clean and acknowledged. */
export async function runSubmit(id: string, deps: SubmitDeps): Promise<SubmitResult> {
  const row = await deps.loadData(id);
  if (!row) throw new Error("not_found");
  if (row.state !== "draft") throw new Error("invalid_state");

  const { errors, warnings } = validate(row.data, await deps.validationContext());
  const acks = warnings.length > 0 ? await deps.loadAcks(id) : [];
  const unacknowledged = unacknowledgedWarnings(warnings, acks);
  if (errors.length > 0 || unacknowledged.length > 0) return { ok: false, errors, unacknowledged };

  await deps.submit(id);
  return { ok: true };
}

/** Zod-parses client data and checks every attachment lives in this solicitation's storage folder. */
export function prepareDraftData(id: string, input: unknown): SolicitationData {
  const data = solicitationSchema.parse(input);
  const prefix = `solicitations/${id}/`;
  for (const a of data.attachments) {
    if (!a.storagePath.startsWith(prefix) || a.storagePath.includes("..")) {
      throw new Error("invalid_attachment_path");
    }
  }
  return data;
}

/** Storage-safe file name: no directories, only [A-Za-z0-9._-]. */
export function safeFileName(name: string): string {
  const base = name.split(/[\/]/).pop() ?? "";
  const cleaned = base.replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^\.+/, "");
  return cleaned === "" ? "file" : cleaned.slice(-120);
}

/** Appends one attachment to the *latest* data. Upload completions must use this, never a stale list. */
export function appendAttachment(
  latest: SolicitationData,
  att: SolicitationData["attachments"][number],
): SolicitationData {
  return { ...latest, attachments: [...latest.attachments, att] };
}
