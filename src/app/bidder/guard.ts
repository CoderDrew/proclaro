import { redirect } from "next/navigation";
import { getAuthState, homePathFor, landingPathFor, type SessionContext } from "@/lib/session";

export type BidderContext = NonNullable<SessionContext> & { orgKind: "bidder" };

/** For pages: signed-out goes to login, unregistered to registration, staff to their own home. */
export async function requireBidderPage(): Promise<BidderContext> {
  const s = await getAuthState();
  if (s.status !== "member") redirect(landingPathFor(s));
  if (s.ctx.orgKind !== "bidder") redirect(homePathFor(s.ctx));
  return s.ctx as BidderContext;
}

/** For server actions: anything but a registered bidder is refused with an error. */
export async function requireBidderAction(): Promise<BidderContext> {
  const s = await getAuthState();
  if (s.status !== "member" || s.ctx.orgKind !== "bidder") throw new Error("not_authorized");
  return s.ctx as BidderContext;
}
