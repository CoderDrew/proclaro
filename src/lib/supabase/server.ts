import { cookies } from "next/headers";
import { createServerClient as createSsrClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

/** Cookie-based Supabase client for server components, actions and route handlers. */
export async function createServerClient(): Promise<SupabaseClient<Database>> {
  const cookieStore = await cookies();
  return createSsrClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (toSet) => {
          try {
            toSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Called from a Server Component: cookies are read-only there.
            // Middleware refreshes the session, so this is safe to ignore.
          }
        },
      },
    },
  );
}
