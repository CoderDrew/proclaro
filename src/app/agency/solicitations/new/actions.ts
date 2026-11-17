"use server";

import { redirect } from "next/navigation";
import { emptySolicitation } from "@/domain/solicitation/schema";
import { createServerClient } from "@/lib/supabase/server";
import { requireAgencyAction } from "../../guard";

/** Inserts an empty draft for the caller's agency (state defaults to draft; RLS enforces agency and ownership), then opens it. */
export async function createSolicitation(): Promise<{ id: string }> {
  const ctx = await requireAgencyAction();
  const supabase = await createServerClient();
  const { data, error } = await supabase
    .from("solicitations")
    .insert({
      agency_id: ctx.orgId,
      created_by: ctx.userId,
      data: JSON.parse(JSON.stringify(emptySolicitation())),
    })
    .select("id")
    .single();
  if (error || !data) throw new Error(error?.message ?? "create_failed");
  redirect(`/agency/solicitations/${data.id}`);
}
