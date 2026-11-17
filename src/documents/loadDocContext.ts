import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";
import { emptySolicitation, solicitationSchema } from "@/domain/solicitation/schema";
import type { DocContext } from "./clauses";

export class SolicitationNotFound extends Error {
  constructor(id: string) {
    super(`SolicitationNotFound: ${id}`);
    this.name = "SolicitationNotFound";
  }
}

/**
 * Builds the rendering context through the caller's own client, so RLS decides what is visible.
 * With `useLocks`, clause bodies come from the versions locked to the solicitation (falling back to the
 * latest for any key without a lock; a lock whose version is missing throws); otherwise every clause is its latest version.
 */
export async function loadDocContext(
  supabase: SupabaseClient<Database>,
  solicitationId: string,
  opts: { useLocks: boolean },
): Promise<DocContext> {
  const { data: sol, error } = await supabase
    .from("solicitations")
    .select("id, agency_id, number, version, data")
    .eq("id", solicitationId)
    .maybeSingle();
  if (error) throw error;
  if (!sol) throw new SolicitationNotFound(solicitationId);

  const [settingsRes, orgRes, clausesRes, locksRes] = await Promise.all([
    supabase.from("settings").select("state_name, office_name, timezone").eq("id", 1).single(),
    supabase.from("organizations").select("name").eq("id", sol.agency_id).single(),
    supabase.from("clauses").select("key, version, body"),
    opts.useLocks
      ? supabase.from("solicitation_clause_locks").select("clause_key, clause_version").eq("solicitation_id", sol.id)
      : Promise.resolve({ data: [], error: null }),
  ]);
  for (const r of [settingsRes, orgRes, clausesRes, locksRes]) if (r.error) throw r.error;

  const locked = new Map((locksRes.data ?? []).map((l) => [l.clause_key, l.clause_version]));
  const best = new Map<string, { version: number; body: string }>();
  for (const c of clausesRes.data ?? []) {
    const want = opts.useLocks ? locked.get(c.key) : undefined;
    if (want !== undefined) {
      if (c.version === want) best.set(c.key, { version: c.version, body: c.body });
    } else if (!locked.has(c.key)) {
      const cur = best.get(c.key);
      if (!cur || c.version > cur.version) best.set(c.key, { version: c.version, body: c.body });
    }
  }

  // Publishing must never ship a document with a missing clause: a lock without its version is an error.
  if (opts.useLocks) {
    for (const [key, version] of locked) {
      if (best.get(key)?.version !== version) throw new Error(`Locked clause ${key} version ${version} is missing`);
    }
  }

  return {
    data: solicitationSchema.parse({ ...emptySolicitation(), ...(sol.data as object) }),
    number: sol.number,
    version: sol.version,
    settings: {
      stateName: settingsRes.data!.state_name,
      officeName: settingsRes.data!.office_name,
      timezone: settingsRes.data!.timezone,
    },
    agencyName: orgRes.data!.name,
    clauses: Object.fromEntries([...best].map(([k, v]) => [k, v.body])),
  };
}
