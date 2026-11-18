import { createServerClient } from "@/lib/supabase/server";

export type SessionContext = {
  userId: string;
  orgId: string;
  orgKind: "agency" | "office" | "bidder";
  isAdmin: boolean;
  displayName: string;
} | null;

export type AuthState =
  | { status: "signed_out" }
  | { status: "unregistered"; userId: string; invited: boolean }
  | { status: "member"; ctx: NonNullable<SessionContext> };

/** Where a user lands after sign-in. Pure: no I/O. */
export function homePathFor(ctx: SessionContext): string {
  if (!ctx) return "/login";
  if (ctx.isAdmin) return "/admin";
  if (ctx.orgKind === "bidder") return "/bidder";
  return ctx.orgKind === "agency" ? "/agency" : "/office";
}

/**
 * Where an auth state lands. A signed-in account with no profile registers a company, unless it was
 * invited: invited accounts are staff and never self-register, so they go back to sign-in.
 */
export function landingPathFor(s: AuthState): string {
  if (s.status === "signed_out") return "/login";
  if (s.status === "unregistered") return s.invited ? "/login" : "/register";
  return homePathFor(s.ctx);
}

/** Signed out, signed in without a profile, or a member with a role. */
export async function getAuthState(): Promise<AuthState> {
  const supabase = await createServerClient();
  const { data: userData } = await supabase.auth.getUser();
  const user = userData.user;
  if (!user) return { status: "signed_out" };

  const { data: profile } = await supabase
    .from("profiles")
    .select("user_id, org_id, display_name, is_admin, organizations(kind)")
    .eq("user_id", user.id)
    .maybeSingle();

  const org = profile
    ? Array.isArray(profile.organizations)
      ? profile.organizations[0]
      : profile.organizations
    : null;
  if (!profile || !org) {
    return { status: "unregistered", userId: user.id, invited: Boolean(user.invited_at) };
  }

  return {
    status: "member",
    ctx: {
      userId: user.id,
      orgId: profile.org_id,
      orgKind: org.kind,
      isAdmin: profile.is_admin,
      displayName: profile.display_name,
    },
  };
}

/** Current user joined with profile and organization, or null when signed out or not yet registered. */
export async function getSessionContext(): Promise<SessionContext> {
  const s = await getAuthState();
  return s.status === "member" ? s.ctx : null;
}
