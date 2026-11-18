import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";
import { todayIn } from "@/domain/time";
import { onlyPublic } from "@/app/solicitations/status";
import type { DocContext } from "./clauses";
import { SolicitationNotFound } from "./loadDocContext";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NO_STORE = { "Cache-Control": "private, no-store" };
const json = (error: string, status: number) => Response.json({ error }, { status, headers: NO_STORE });

export interface BlankFormDeps {
  supabase: SupabaseClient<Database>;
  now: Date;
  loadContext: (supabase: SupabaseClient<Database>, solicitationId: string) => Promise<DocContext>;
  renderPdf: (ctx: DocContext) => Promise<Uint8Array>;
}

/**
 * The unfilled bid form of a published, released solicitation, for a bidder who fills it in by hand. Every read goes
 * through the caller's own client (never the admin client). Signed out is 401; a solicitation the caller cannot see
 * (unpublished, not yet released, or any id that does not exist) is 404. Every response is `private, no-store`.
 * The form comes from the published snapshot, with no fill, in its final (not draft) footer format.
 */
export async function blankFormResponse(deps: BlankFormDeps, id: string): Promise<Response> {
  const { supabase } = deps;
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) return json("Not signed in", 401);
  if (!UUID.test(id)) return json("Not found", 404);

  // The same visibility filter the bidder pages use: office staff can read unreleased rows through RLS.
  const settings = await supabase.from("settings").select("timezone").eq("id", 1).single();
  if (settings.error) throw settings.error;
  const sol = await onlyPublic(
    supabase.from("solicitations").select("id").eq("id", id),
    todayIn(settings.data.timezone, deps.now),
  ).maybeSingle();
  if (sol.error) throw sol.error;
  if (!sol.data) return json("Not found", 404);

  try {
    const ctx = await deps.loadContext(supabase, id);
    const pdf = await deps.renderPdf(ctx);
    return new Response(Buffer.from(pdf), {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `inline; filename="bid-form-${ctx.number ?? "blank"}-blank.pdf"`,
        ...NO_STORE,
      },
    });
  } catch (e) {
    if (e instanceof SolicitationNotFound) return json("Not found", 404);
    throw e;
  }
}
