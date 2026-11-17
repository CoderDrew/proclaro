"use server";

import { createServerClient } from "@/lib/supabase/server";
import { runAdmin } from "../actions-shared";
import type { AdminResult } from "../common";
import * as logic from "./logic";

async function deps(): Promise<logic.HolidayDeps> {
  const supabase = await createServerClient();
  return {
    async insert(row) {
      const { error } = await supabase.from("holidays").insert(row);
      if (!error) return "ok";
      if (error.code === "23505") return "duplicate";
      throw new Error(error.message);
    },
    async remove(day) {
      const { data, error } = await supabase.from("holidays").delete().eq("day", day).select("day");
      if (error) throw new Error(error.message);
      return data.length > 0;
    },
  };
}

export async function addHoliday(formData: FormData): Promise<AdminResult> {
  return runAdmin("/admin/holidays", async (ctx) =>
    logic.addHoliday(ctx, { day: formData.get("day"), name: formData.get("name") }, await deps()));
}

export async function removeHoliday(formData: FormData): Promise<AdminResult> {
  return runAdmin("/admin/holidays", async (ctx) => logic.removeHoliday(ctx, formData.get("day"), await deps()));
}
