import { todayIn } from "@/domain/time";
import { createServerClient } from "@/lib/supabase/server";
import { createSolicitation } from "./solicitations/new/actions";
import { requireAgencyPage } from "./guard";

export const dynamic = "force-dynamic";

export default async function AgencyHome() {
  const ctx = await requireAgencyPage();
  const supabase = await createServerClient();
  // RLS already limits this to the caller's agency; the filter states the intent.
  const { data: rows, error } = await supabase
    .from("solicitations")
    .select("id, number, state, data, created_at")
    .eq("agency_id", ctx.orgId)
    .order("created_at", { ascending: false });
  if (error) throw new Error(error.message);
  const settings = await supabase.from("settings").select("timezone").eq("id", 1).single();
  if (settings.error) throw new Error(settings.error.message);
  const tz = settings.data.timezone;

  async function create() {
    "use server";
    await createSolicitation();
  }

  return (
    <main>
      <h1>My solicitations</h1>
      <form action={create} style={{ margin: "0 0 12px" }}>
        <button type="submit">New solicitation</button>
      </form>
      {rows.length === 0 ? (
        <p>No solicitations yet.</p>
      ) : (
        <table className="list">
          <thead>
            <tr><th>Number</th><th>Title</th><th>State</th><th>Created</th></tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const title = (r.data as { shortTitle?: string } | null)?.shortTitle || "(untitled draft)";
              return (
                <tr key={r.id}>
                  <td>{r.number ?? "-"}</td>
                  <td><a href={`/agency/solicitations/${r.id}`}>{title}</a></td>
                  <td><span className="status-pill">{r.state}</span></td>
                  <td>{todayIn(tz, new Date(r.created_at))}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </main>
  );
}
