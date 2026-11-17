import { redirect } from "next/navigation";
import { getSessionContext, homePathFor, type SessionContext } from "@/lib/session";

export type AdminContext = NonNullable<SessionContext> & { isAdmin: true };

/** For pages: signed-out goes to login; signed-in non-admins go to their own home. Middleware only checks sign-in. */
export async function requireAdminPage(): Promise<AdminContext> {
  const ctx = await getSessionContext();
  if (!ctx) redirect("/login");
  if (!ctx.isAdmin) redirect(homePathFor(ctx));
  return ctx as AdminContext;
}
