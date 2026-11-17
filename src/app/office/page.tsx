import { createServerClient } from "@/lib/supabase/server";
import { todayIn } from "@/domain/time";
import { requireOfficePage } from "./guard";

export const dynamic = "force-dynamic";

type Row = {
  id: string; number: string | null; state: string; data: unknown; agency_id: string;
  reviewer_id: string | null; latest_submitted_at: string | null;
};

export default async function OfficeHome({ searchParams }: { searchParams: Promise<{ review?: string }> }) {
  const ctx = await requireOfficePage();
  const { review } = await searchParams;
  const mineOnly = review !== "all";

  const supabase = await createServerClient();
  const [rows, orgs, staff, settings] = await Promise.all([
    supabase.from("solicitations")
      .select("id, number, state, data, agency_id, reviewer_id, latest_submitted_at")
      .in("state", ["submitted", "in_review", "in_check", "approved"])
      .order("latest_submitted_at", { ascending: true }),
    supabase.from("organizations").select("id, name"),
    supabase.from("profiles").select("user_id, display_name"),
    supabase.from("settings").select("timezone").eq("id", 1).single(),
  ]);
  for (const r of [rows, orgs, staff, settings]) if (r.error) throw new Error(r.error.message);
  const agencyName = new Map(orgs.data!.map((o) => [o.id, o.name]));
  const staffName = new Map(staff.data!.map((p) => [p.user_id, p.display_name]));
  const all = rows.data as Row[];
  const tz = settings.data!.timezone;

  function table(list: Row[], empty: string) {
    if (list.length === 0) return <p>{empty}</p>;
    return (
      <table className="list">
        <thead>
          <tr><th>Number</th><th>Title</th><th>Agency</th><th>Reviewer</th><th>Submitted</th></tr>
        </thead>
        <tbody>
          {list.map((r) => (
            <tr key={r.id}>
              <td>{r.number ?? "-"}</td>
              <td>
                <a href={`/office/solicitations/${r.id}`}>
                  {(r.data as { shortTitle?: string } | null)?.shortTitle || "(untitled)"}
                </a>
              </td>
              <td>{agencyName.get(r.agency_id) ?? ""}</td>
              <td>{r.reviewer_id ? staffName.get(r.reviewer_id) ?? "" : "-"}</td>
              <td>{r.latest_submitted_at ? todayIn(tz, new Date(r.latest_submitted_at)) : "-"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    );
  }

  const inReview = all.filter((r) => r.state === "in_review");
  const shownReview = mineOnly ? inReview.filter((r) => r.reviewer_id === ctx.userId) : inReview;

  return (
    <main>
      <h1>Procurement office</h1>

      <h2>Submitted</h2>
      {table(all.filter((r) => r.state === "submitted"), "Nothing is waiting for review.")}

      <h2>In review</h2>
      <p style={{ margin: "0 0 6px" }}>
        {mineOnly ? <strong>Mine</strong> : <a href="/office?review=mine">Mine</a>}
        {" · "}
        {mineOnly ? <a href="/office?review=all">All</a> : <strong>All</strong>}
      </p>
      {table(shownReview, mineOnly ? "You are not reviewing anything." : "Nothing is in review.")}

      <h2>In check</h2>
      {table(all.filter((r) => r.state === "in_check"), "Nothing is waiting for a check.")}

      <h2>Approved</h2>
      {table(all.filter((r) => r.state === "approved"), "Nothing is approved yet.")}
    </main>
  );
}
