import "server-only";
import { createServerClient } from "@/lib/supabase/server";
import { canSetInitialPassword } from "./logic";

/**
 * True only for a signed-in invited user whose current session came from the invite link.
 * getClaims verifies the access token (with the auth server for symmetric keys) before its
 * `amr` claim is trusted; getUser reads `invited_at` from the auth server.
 */
export async function hasInviteSession(): Promise<boolean> {
  const supabase = await createServerClient();
  const { data, error } = await supabase.auth.getClaims();
  if (error || !data?.claims?.sub) return false;
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user || userData.user.id !== data.claims.sub) return false;
  return canSetInitialPassword(data.claims.amr, userData.user.invited_at);
}
