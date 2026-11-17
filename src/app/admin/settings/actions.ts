"use server";

import { createServerClient } from "@/lib/supabase/server";
import { runAdmin } from "../actions-shared";
import type { AdminResult } from "../common";
import * as logic from "./logic";

export async function saveSettings(formData: FormData): Promise<AdminResult> {
  return runAdmin("/admin/settings", async (ctx) => {
    const supabase = await createServerClient();
    return logic.saveSettings(
      ctx,
      {
        stateName: formData.get("stateName"),
        officeName: formData.get("officeName"),
        timezone: formData.get("timezone"),
        fiscalYearStartMonth: formData.get("fiscalYearStartMonth"),
      },
      {
        async update(row) {
          const { data, error } = await supabase.from("settings").update(row).eq("id", 1).select("id");
          if (error) throw new Error(error.message);
          return data.length > 0;
        },
      },
    );
  });
}
