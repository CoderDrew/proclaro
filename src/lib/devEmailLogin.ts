/**
 * Gate for the development-only "sign in by email, no password" feature. Pure so it can be unit-tested.
 * It is on only when ALL of these hold: not a production build, DEV_EMAIL_LOGIN is exactly "1", and the
 * Supabase URL points at this machine. Never trust a client for this: the server action checks it again.
 */
export function devEmailLoginEnabled(env: Record<string, string | undefined>): boolean {
  if (env.NODE_ENV === "production") return false;
  if (env.DEV_EMAIL_LOGIN !== "1") return false;
  const url = env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) return false;
  try {
    const host = new URL(url).hostname;
    return host === "127.0.0.1" || host === "localhost";
  } catch {
    return false;
  }
}
