import type { SessionContext } from "@/lib/session";
import { cleanText, isAdminCtx, NOT_ADMIN, type AdminResult } from "../common";

export interface OrgDeps {
  insert(row: { name: string; kind: "agency" | "office" }): Promise<"ok" | "duplicate">;
  rename(id: string, name: string): Promise<"ok" | "duplicate" | "missing">;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DUPLICATE: AdminResult = { ok: false, message: "An organization with that name already exists." };

export async function createOrganization(ctx: SessionContext, input: { name: unknown; kind: unknown }, d: OrgDeps): Promise<AdminResult> {
  if (!isAdminCtx(ctx)) return NOT_ADMIN;
  const name = cleanText(input.name, "Name");
  if ("error" in name) return { ok: false, message: name.error };
  if (input.kind !== "agency" && input.kind !== "office") return { ok: false, message: "Choose agency or office." };
  return (await d.insert({ name: name.value, kind: input.kind })) === "ok"
    ? { ok: true, message: "Organization created." }
    : DUPLICATE;
}

export async function renameOrganization(ctx: SessionContext, input: { id: unknown; name: unknown }, d: OrgDeps): Promise<AdminResult> {
  if (!isAdminCtx(ctx)) return NOT_ADMIN;
  if (typeof input.id !== "string" || !UUID.test(input.id)) return { ok: false, message: "Organization not found." };
  const name = cleanText(input.name, "Name");
  if ("error" in name) return { ok: false, message: name.error };
  const res = await d.rename(input.id, name.value);
  if (res === "duplicate") return DUPLICATE;
  if (res === "missing") return { ok: false, message: "Organization not found." };
  return { ok: true, message: "Renamed." };
}
