"use server";

import { createServerClient } from "@/lib/supabase/server";
import { runAdmin } from "../actions-shared";
import type { AdminResult } from "../common";
import * as logic from "./logic";

export async function saveClause(key: string, body: string): Promise<AdminResult> {
  return runAdmin("/admin/clauses", async (ctx) => {
    const supabase = await createServerClient();
    return logic.saveClause(ctx, key, body, {
      async latest(k) {
        const { data, error } = await supabase
          .from("clauses").select("version, body").eq("key", k).order("version", { ascending: false }).limit(1);
        if (error) throw new Error(error.message);
        return data[0] ?? null;
      },
      async insert(row) {
        const { error } = await supabase.from("clauses").insert({
          key: row.key, version: row.version, body: row.body, created_by: row.createdBy,
        });
        if (!error) return "ok";
        if (error.code === "23505") return "conflict";
        throw new Error(error.message);
      },
    });
  });
}

/** Form wrapper: the page binds `key`; the textarea is named `body`. */
export async function saveClauseForm(key: string, formData: FormData): Promise<AdminResult> {
  return saveClause(key, String(formData.get("body") ?? ""));
}
