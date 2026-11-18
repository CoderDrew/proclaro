import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { devEmailLoginEnabled } from "@/lib/devEmailLogin";

/**
 * DEVELOPMENT ONLY. The one place outside src/app/admin that uses the service-role client; imported
 * only by the login action. For an email that already belongs to a user with a profile, returns the
 * hashed magic-link token that the caller's server client exchanges (verifyOtp) for session cookies.
 * Returns null for any other email, and never creates a user. Throws if the dev gate is not open.
 */
export async function mintDevLoginTokenHash(email: string): Promise<string | null> {
  if (!devEmailLoginEnabled(process.env)) throw new Error("Development email sign-in is not enabled.");
  const admin = createAdminClient();
  const wanted = email.trim().toLowerCase();

  // generateLink would create a missing user, so look the user up first. Local stacks hold a handful of users.
  let userId: string | null = null;
  for (let page = 1; page <= 20 && !userId; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) return null;
    userId = data.users.find((u) => u.email?.toLowerCase() === wanted)?.id ?? null;
    if (data.users.length < 200) break;
  }
  if (!userId) return null;

  const { data: profile } = await admin.from("profiles").select("user_id").eq("user_id", userId).maybeSingle();
  if (!profile) return null;

  const { data, error } = await admin.auth.admin.generateLink({ type: "magiclink", email: wanted });
  if (error) return null;
  return data.properties?.hashed_token ?? null;
}
