import { redirect } from "next/navigation";
import { getSessionContext, homePathFor, type SessionContext } from "@/lib/session";

export type AgencyContext = NonNullable<SessionContext> & { orgKind: "agency" };

/** For pages: signed-out goes to login, office staff go to their own home. */
export async function requireAgencyPage(): Promise<AgencyContext> {
  const ctx = await getSessionContext();
  if (!ctx) redirect("/login");
  if (ctx.orgKind !== "agency") redirect(homePathFor(ctx));
  return ctx as AgencyContext;
}

/** For server actions: anything but an agency member is refused with an error. */
export async function requireAgencyAction(): Promise<AgencyContext> {
  const ctx = await getSessionContext();
  if (!ctx || ctx.orgKind !== "agency") throw new Error("not_authorized");
  return ctx as AgencyContext;
}
