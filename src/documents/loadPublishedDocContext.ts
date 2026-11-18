import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";
import { emptySolicitation, solicitationSchema } from "@/domain/solicitation/schema";
import type { DocContext } from "./clauses";
import { SolicitationNotFound } from "./loadDocContext";

interface Snapshot {
  data?: object;
  clauses?: Record<string, string>;
  settings?: DocContext["settings"];
}

/**
 * The rendering context of a PUBLISHED solicitation, built only from its published snapshot through the caller's
 * own client. Clause text comes from the snapshot: clause locks are invisible to bidders and the live clauses
 * may have changed since publishing, so neither table is read.
 */
export async function loadPublishedDocContext(
  supabase: SupabaseClient<Database>,
  solicitationId: string,
): Promise<DocContext> {
  const { data: sol, error } = await supabase
    .from("solicitations")
    .select("id, agency_id, number, version, published_snapshot")
    .eq("id", solicitationId)
    .maybeSingle();
  if (error) throw error;
  const snap = sol?.published_snapshot as Snapshot | null | undefined;
  if (!sol || !snap || !snap.data || !snap.clauses || !snap.settings || sol.number === null || sol.version === null) {
    throw new SolicitationNotFound(solicitationId);
  }

  const org = await supabase.from("organizations").select("name").eq("id", sol.agency_id).single();
  if (org.error) throw org.error;

  return {
    data: solicitationSchema.parse({ ...emptySolicitation(), ...snap.data }),
    number: sol.number,
    version: sol.version,
    settings: snap.settings,
    agencyName: org.data.name,
    clauses: snap.clauses,
  };
}
