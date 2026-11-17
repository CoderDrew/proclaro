import { revalidatePath } from "next/cache";
import { getSessionContext, type SessionContext } from "@/lib/session";
import type { AdminResult } from "./common";

/**
 * Runs an admin action body: resolves the session, turns unexpected errors into a typed failure and refreshes the page.
 * The body must pass `ctx` to its logic function, which refuses anyone who is not an administrator.
 */
export async function runAdmin(path: string, body: (ctx: SessionContext) => Promise<AdminResult>): Promise<AdminResult> {
  try {
    const result = await body(await getSessionContext());
    if (result.ok) revalidatePath(path);
    return result;
  } catch (e) {
    // Next redacts thrown messages in production, so return a typed failure instead.
    console.error("admin action failed", e);
    return { ok: false, message: "Something went wrong. Reload the page and try again." };
  }
}
