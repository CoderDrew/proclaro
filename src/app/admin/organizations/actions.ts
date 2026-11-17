"use server";

import { createServerClient } from "@/lib/supabase/server";
import { runAdmin } from "../actions-shared";
import type { AdminResult } from "../common";
import * as logic from "./logic";

async function deps(): Promise<logic.OrgDeps> {
  const supabase = await createServerClient();
  return {
    async insert(row) {
      const { error } = await supabase.from("organizations").insert(row);
      if (!error) return "ok";
      if (error.code === "23505") return "duplicate";
      throw new Error(error.message);
    },
    async rename(id, name) {
      const { data, error } = await supabase.from("organizations").update({ name }).eq("id", id).select("id");
      if (error?.code === "23505") return "duplicate";
      if (error) throw new Error(error.message);
      return data.length > 0 ? "ok" : "missing";
    },
  };
}

export async function createOrganization(formData: FormData): Promise<AdminResult> {
  return runAdmin("/admin/organizations", async (ctx) =>
    logic.createOrganization(ctx, { name: formData.get("name"), kind: formData.get("kind") }, await deps()));
}

export async function renameOrganization(formData: FormData): Promise<AdminResult> {
  return runAdmin("/admin/organizations", async (ctx) =>
    logic.renameOrganization(ctx, { id: formData.get("id"), name: formData.get("name") }, await deps()));
}
