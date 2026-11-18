import { createServerClient } from "@/lib/supabase/server";
import { todayIn } from "@/domain/time";
import { formatInstant } from "@/app/solicitations/status";
import { requireOfficePage } from "./guard";
import { Card, EmptyState, Page, PageHeader, Table, Td, Th } from "@/components/ui";

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
  const [rows, orgs, staff, settings, published] = await Promise.all([
    supabase.from("solicitations")
      .select("id, number, state, data, agency_id, reviewer_id, latest_submitted_at")
      .in("state", ["submitted", "in_review", "in_check", "approved"])
      .order("latest_submitted_at", { ascending: true }),
    supabase.from("organizations").select("id, name"),
    supabase.from("profiles").select("user_id, display_name"),
    supabase.from("settings").select("timezone").eq("id", 1).single(),
    supabase.from("solicitations")
      .select("id, number, data, agency_id, bid_due_at")
      .eq("state", "published")
      .order("bid_due_at", { ascending: true }),
  ]);
  for (const r of [rows, orgs, staff, settings, published]) if (r.error) throw new Error(r.error.message);
  const agencyName = new Map(orgs.data!.map((o) => [o.id, o.name]));
  const staffName = new Map(staff.data!.map((p) => [p.user_id, p.display_name]));
  const all = rows.data as Row[];
  const tz = settings.data!.timezone;

  function table(list: Row[], empty: string) {
    if (list.length === 0) return <EmptyState>{empty}</EmptyState>;
    return (
      <Table>
        <thead>
          <tr><Th>Number</Th><Th>Title</Th><Th>Agency</Th><Th>Reviewer</Th><Th>Submitted</Th></tr>
        </thead>
        <tbody>
          {list.map((r) => (
            <tr key={r.id}>
              <Td>{r.number ?? "-"}</Td>
              <Td>
                <a href={`/office/solicitations/${r.id}`}>
                  {(r.data as { shortTitle?: string } | null)?.shortTitle || "(untitled)"}
                </a>
              </Td>
              <Td>{agencyName.get(r.agency_id) ?? ""}</Td>
              <Td>{r.reviewer_id ? staffName.get(r.reviewer_id) ?? "" : "-"}</Td>
              <Td>{r.latest_submitted_at ? todayIn(tz, new Date(r.latest_submitted_at)) : "-"}</Td>
            </tr>
          ))}
        </tbody>
      </Table>
    );
  }

  const inReview = all.filter((r) => r.state === "in_review");
  const shownReview = mineOnly ? inReview.filter((r) => r.reviewer_id === ctx.userId) : inReview;

  return (
    <Page width="full">
      <PageHeader title="Procurement office" />

      <Card title="Submitted">
        {table(all.filter((r) => r.state === "submitted"), "Nothing is waiting for review.")}
      </Card>

      <Card title="In review">
        <p className="ui-segmented">
          {mineOnly ? <strong aria-current="true">Mine</strong> : <a href="/office?review=mine">Mine</a>}
          {mineOnly ? <a href="/office?review=all">All</a> : <strong aria-current="true">All</strong>}
        </p>
        {table(shownReview, mineOnly ? "You are not reviewing anything." : "Nothing is in review.")}
      </Card>

      <Card title="In check">
        {table(all.filter((r) => r.state === "in_check"), "Nothing is waiting for a check.")}
      </Card>

      <Card title="Approved">
        {table(all.filter((r) => r.state === "approved"), "Nothing is approved yet.")}
      </Card>

      <Card title="Published" titleId="published">
        {published.data!.length === 0 ? <EmptyState>Nothing is published.</EmptyState> : (
          <Table data-testid="published">
            <thead>
              <tr><Th>Number</Th><Th>Title</Th><Th>Agency</Th><Th>Bid due</Th><Th>Bids</Th></tr>
            </thead>
            <tbody>
              {published.data!.map((r) => (
                <tr key={r.id}>
                  <Td>{r.number ?? "-"}</Td>
                  <Td>
                    <a href={`/office/solicitations/${r.id}`}>
                      {(r.data as { shortTitle?: string } | null)?.shortTitle || "(untitled)"}
                    </a>
                  </Td>
                  <Td>{agencyName.get(r.agency_id) ?? ""}</Td>
                  <Td>{r.bid_due_at ? formatInstant(r.bid_due_at, tz) : "-"}</Td>
                  <Td><a href={`/office/solicitations/${r.id}/bids`} aria-label={`Originals log and tabulation for ${r.number ?? ((r.data as { shortTitle?: string } | null)?.shortTitle || "untitled")}`}>Originals log and tabulation</a></Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </Page>
  );
}
