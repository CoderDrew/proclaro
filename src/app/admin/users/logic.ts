import { z } from "zod";
import type { SessionContext } from "@/lib/session";
import { cleanText, isAdminCtx, NOT_ADMIN, type AdminResult } from "../common";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface UserDeps {
  /** Through the caller's RLS client. */
  orgExists(id: string): Promise<boolean>;
  /** auth.admin.inviteUserByEmail. Returns the new auth user id, or the provider's error text. */
  invite(email: string, displayName: string): Promise<{ userId: string } | { error: string }>;
  /** Whether this auth user already has a profile (re-inviting an existing email returns the existing user). */
  profileExists(userId: string): Promise<boolean>;
  /** The profile insert that must follow the invite (service role: profiles has no application insert policy). */
  insertProfile(row: { userId: string; orgId: string; displayName: string; isAdmin: boolean }): Promise<boolean>;
  /** Undo for a failed profile insert, so an invited user never exists without a profile. */
  deleteAuthUser(userId: string): Promise<void>;
}

export async function createUser(
  ctx: SessionContext,
  input: { email: unknown; displayName: unknown; orgId: unknown; isAdmin: unknown },
  d: UserDeps,
): Promise<AdminResult> {
  if (!isAdminCtx(ctx)) return NOT_ADMIN;
  const email = z.string().trim().toLowerCase().max(254).email().safeParse(input.email);
  if (!email.success) return { ok: false, message: "Enter a valid email address." };
  const name = cleanText(input.displayName, "Display name");
  if ("error" in name) return { ok: false, message: name.error };
  // Shape check only (like the other actions): zod's uuid() also demands RFC version bits, which seed ids lack.
  const orgId = typeof input.orgId === "string" && UUID.test(input.orgId) ? input.orgId : null;
  if (!orgId || !(await d.orgExists(orgId))) return { ok: false, message: "Choose an organization." };
  const isAdmin = input.isAdmin === true;

  const invited = await d.invite(email.data, name.value);
  if ("error" in invited) return { ok: false, message: `Could not invite that user: ${invited.error}` };

  // Inviting an address that already has an account returns that existing user. Never touch it (the cleanup
  // below would delete a real account along with its profile).
  if (await d.profileExists(invited.userId)) return { ok: false, message: "A user with that email address already exists." };

  const inserted = await d.insertProfile({ userId: invited.userId, orgId, displayName: name.value, isAdmin });
  if (!inserted) {
    await d.deleteAuthUser(invited.userId);
    return { ok: false, message: "The invitation was not completed (profile could not be created). Nothing was saved; try again." };
  }
  return { ok: true, message: `Invitation sent to ${email.data}.` };
}
