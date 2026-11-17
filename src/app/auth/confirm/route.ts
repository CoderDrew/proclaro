import type { NextRequest } from "next/server";
import { createServerClient } from "@/lib/supabase/server";
import { LINK_INVALID_PATH, parseConfirmParams, SET_PASSWORD_PATH } from "../logic";

/**
 * Relative redirect: keeps the browser on the host it used (127.0.0.1 or localhost), so the session
 * cookies set here are sent on the next request. Next's dev server reports its own host in
 * request.url, which can differ. Cookies set through next/headers are added to this response.
 */
function seeOther(path: string): Response {
  return new Response(null, { status: 303, headers: { Location: path } });
}

/**
 * Target of the invite email (see supabase/templates/invite.html). Verifies the one-time
 * token hash with the auth server, which sets the session cookies, then sends the user on
 * to choose a password. The token is single-use and expires after `otp_expiry`.
 */
export async function GET(request: NextRequest) {
  const parsed = parseConfirmParams(request.nextUrl.searchParams);
  if (!parsed) return seeOther(LINK_INVALID_PATH);

  const supabase = await createServerClient();
  // Drop any existing session in this browser first, so the invite never mixes with another account.
  await supabase.auth.signOut({ scope: "local" });
  const { error } = await supabase.auth.verifyOtp({ type: parsed.type, token_hash: parsed.tokenHash });
  if (error) return seeOther(LINK_INVALID_PATH);
  return seeOther(SET_PASSWORD_PATH);
}
