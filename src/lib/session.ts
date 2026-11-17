import { createServerClient } from "@/lib/supabase/server";

export type SessionContext = {
  userId: string;
  orgId: string;
  orgKind: "agency" | "office";
  isAdmin: boolean;
  displayName: string;
} | null;

/** Where a user lands after sign-in. Pure: no I/O. */
export function homePathFor(ctx: SessionContext): string {
  if (!ctx) return "/login";
  if (ctx.isAdmin) return "/admin";
  return ctx.orgKind === "agency" ? "/agency" : "/office";
}

/** Current user joined with profile and organization, or null when signed out. */
export async function getSessionContext(): Promise<SessionContext> {
  const supabase = await createServerClient();
  const { data: userData } = await supabase.auth.getUser();
  const user = userData.user;
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("user_id, org_id, display_name, is_admin, organizations(kind)")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!profile) return null;

  const org = Array.isArray(profile.organizations)
    ? profile.organizations[0]
    : profile.organizations;
  if (!org) return null;

  return {
    userId: user.id,
    orgId: profile.org_id,
    orgKind: org.kind,
    isAdmin: profile.is_admin,
    displayName: profile.display_name,
  };
}
