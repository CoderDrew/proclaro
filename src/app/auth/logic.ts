// First sign-in for invited users. Pure: no Next, no Supabase.

/** Path of the route that turns an emailed invite token into a session. */
export const CONFIRM_PATH = "/auth/confirm";
export const SET_PASSWORD_PATH = "/auth/set-password";
export const LINK_INVALID_PATH = "/auth/link-invalid";

/** App's own password floor. The auth server's floor (config.toml) is lower; this one wins in the UI. */
export const MIN_PASSWORD_LENGTH = 8;
/** bcrypt ignores bytes past 72, so longer passwords give a false sense of strength. */
export const MAX_PASSWORD_LENGTH = 72;

const DEFAULT_SITE_URL = "http://127.0.0.1:3000";

/**
 * The invite `redirectTo`: the app's confirm route on the configured site origin.
 * The auth server accepts it only if it is listed in `additional_redirect_urls`.
 */
export function inviteRedirectUrl(siteUrl: string | undefined): string {
  const base = (siteUrl?.trim() || DEFAULT_SITE_URL).replace(/\/+$/, "");
  return `${base}${CONFIRM_PATH}`;
}

/**
 * Reads the confirm link's query string. Only invite links are accepted: this route never
 * handles signup, magic-link, recovery or email-change tokens.
 */
export function parseConfirmParams(params: URLSearchParams): { tokenHash: string; type: "invite" } | null {
  const tokenHash = params.get("token_hash")?.trim();
  const type = params.get("type");
  if (!tokenHash || type !== "invite") return null;
  // GoTrue token hashes are hex; anything else is a mangled or forged link.
  if (!/^[0-9a-f]{20,128}$/i.test(tokenHash)) return null;
  return { tokenHash, type };
}

/**
 * Whether this session may set the account's first password: the user was invited, and the
 * session itself came from an emailed one-time token. The access token's `amr` claim records
 * how the session was authenticated. Verifying an invite token hash records "otp"; a password
 * sign-in records "password". Login offers no magic link, so an "otp" session can only come
 * from the invite link.
 */
export function canSetInitialPassword(amr: unknown, invitedAt: string | null | undefined): boolean {
  if (!invitedAt || !Array.isArray(amr)) return false;
  // The claim is either detailed entries ({ method, timestamp }) or RFC 8176 plain strings.
  return amr.some(
    (entry) =>
      entry === "otp" ||
      (typeof entry === "object" && entry !== null && (entry as { method?: unknown }).method === "otp"),
  );
}

export function validateNewPassword(password: unknown, confirm: unknown): { password: string } | { error: string } {
  if (typeof password !== "string" || password === "") return { error: "Enter a password." };
  if (password.length < MIN_PASSWORD_LENGTH) return { error: `Use at least ${MIN_PASSWORD_LENGTH} characters.` };
  if (new TextEncoder().encode(password).length > MAX_PASSWORD_LENGTH) {
    return { error: `Use at most ${MAX_PASSWORD_LENGTH} characters.` };
  }
  if (password.trim() !== password) return { error: "The password cannot start or end with a space." };
  if (password !== confirm) return { error: "The two passwords do not match." };
  return { password };
}
