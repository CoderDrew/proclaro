import "server-only";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

/**
 * Service-role client: bypasses RLS. Server code only, and import it only
 * from src/app/admin/** and from src/app/login/devLogin.ts (development-only email sign-in, gated by
 * devEmailLoginEnabled). The server-only import makes bundling it for the client a build error.
 */
export function createAdminClient() {
  return createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
