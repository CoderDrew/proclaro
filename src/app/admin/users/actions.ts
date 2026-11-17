"use server";

import { createServerClient } from "@/lib/supabase/server";
// The only place the service-role client is used: the invite and the profile insert that must follow it.
import { createAdminClient } from "@/lib/supabase/admin";
import { runAdmin } from "../actions-shared";
import type { AdminResult } from "../common";
import { inviteRedirectUrl } from "@/app/auth/logic";
import * as logic from "./logic";

export async function createUser(formData: FormData): Promise<AdminResult> {
  return runAdmin("/admin/users", async (ctx) => {
    const supabase = await createServerClient();
    const admin = createAdminClient(); // only used after logic.createUser has confirmed the caller is an admin
    return logic.createUser(
      ctx,
      {
        email: formData.get("email"),
        displayName: formData.get("displayName"),
        orgId: formData.get("orgId"),
        isAdmin: formData.get("isAdmin") === "on",
      },
      {
        async orgExists(id) {
          const { data, error } = await supabase.from("organizations").select("id").eq("id", id).maybeSingle();
          if (error) throw new Error(error.message);
          return !!data;
        },
        async invite(email, displayName) {
          const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
            data: { display_name: displayName },
            // The invite email links here (supabase/templates/invite.html); must be allow-listed in config.toml.
            redirectTo: inviteRedirectUrl(process.env.SITE_URL),
          });
          if (error || !data.user) return { error: error?.message ?? "invite failed" };
          return { userId: data.user.id };
        },
        async profileExists(userId) {
          const { data, error } = await admin.from("profiles").select("user_id").eq("user_id", userId).maybeSingle();
          if (error) throw new Error(error.message);
          return !!data;
        },
        async insertProfile(row) {
          const { error } = await admin.from("profiles").insert({
            user_id: row.userId, org_id: row.orgId, display_name: row.displayName, is_admin: row.isAdmin,
          });
          if (error) console.error("profile insert failed", error.message);
          return !error;
        },
        async deleteAuthUser(userId) {
          const { error } = await admin.auth.admin.deleteUser(userId);
          if (error) console.error("could not remove auth user after failed profile insert", userId, error.message);
        },
      },
    );
  });
}
