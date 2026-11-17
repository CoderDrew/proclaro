"use server";

import { redirect } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { getSessionContext, homePathFor } from "@/lib/session";
import { hasInviteSession } from "../guard";
import { LINK_INVALID_PATH, validateNewPassword } from "../logic";

export type SetPasswordState = { error?: string } | undefined;

export async function setPassword(_prev: SetPasswordState, formData: FormData): Promise<SetPasswordState> {
  // Re-checked here, not just on the page: a server action is reachable without rendering the page.
  if (!(await hasInviteSession())) redirect(LINK_INVALID_PATH);

  const checked = validateNewPassword(formData.get("password"), formData.get("confirm"));
  if ("error" in checked) return { error: checked.error };

  const supabase = await createServerClient();
  const { error } = await supabase.auth.updateUser({ password: checked.password });
  if (error) {
    console.error("set password failed", error.code ?? error.message);
    return { error: "The password could not be saved. Try a different password." };
  }

  const ctx = await getSessionContext();
  if (!ctx) {
    await supabase.auth.signOut();
    redirect("/login");
  }
  redirect(homePathFor(ctx));
}
