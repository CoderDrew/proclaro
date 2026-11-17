import { redirect } from "next/navigation";
import { getSessionContext, homePathFor, type SessionContext } from "@/lib/session";

export type OfficeContext = NonNullable<SessionContext>;

/** For pages: signed-out goes to login, agency members go to their own home. Admins may also view. */
export async function requireOfficePage(): Promise<OfficeContext> {
  const ctx = await getSessionContext();
  if (!ctx) redirect("/login");
  if (ctx.orgKind !== "office" && !ctx.isAdmin) redirect(homePathFor(ctx));
  return ctx;
}

/** For server actions: only office staff may act. (The database functions enforce this too.) */
export async function requireOfficeAction(): Promise<OfficeContext> {
  const ctx = await getSessionContext();
  if (!ctx || ctx.orgKind !== "office") throw new Error("not_authorized");
  return ctx;
}
