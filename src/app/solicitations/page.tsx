import Link from "next/link";
import { createServerClient } from "@/lib/supabase/server";
import { todayIn } from "@/domain/time";
import { DateTime, EmptyState, Page, PageHeader, StatusBadge, Table, Td, Th } from "@/components/ui";
import { bidStatus, onlyPublic } from "./status";

export const dynamic = "force-dynamic";

/**
 * Public listing: published and released solicitations only, whoever is signed in. RLS hides the rest from anon,
 * but office staff can read every row, so the release filter is applied here too.
 */
export default async function SolicitationsPage() {
  const supabase = await createServerClient();
  const settings = await supabase.from("settings").select("timezone").eq("id", 1).single();
  if (settings.error) throw new Error(settings.error.message);
  const tz = settings.data.timezone;
  const now = new Date();
  const [rows, orgs] = await Promise.all([
    onlyPublic(supabase.from("solicitations").select("number, data, agency_id, bid_due_at, release_date"), todayIn(tz, now))
      .order("bid_due_at", { ascending: false }),
    supabase.from("organizations").select("id, name"),
  ]);
  for (const r of [rows, orgs]) if (r.error) throw new Error(r.error.message);
  const agency = new Map(orgs.data!.map((o) => [o.id, o.name]));

  return (
    <Page width="full">
      <PageHeader title="Solicitations" />
      {rows.data!.length === 0 ? (
        <EmptyState>No solicitations are open for bidding right now.</EmptyState>
      ) : (
        <Table>
          <thead>
            <tr><Th>Number</Th><Th>Title</Th><Th>Agency</Th><Th>Bid due</Th><Th>Status</Th></tr>
          </thead>
          <tbody>
            {rows.data!.map((r) => {
              const title = (r.data as { longTitle?: string } | null)?.longTitle || "(untitled)";
              return (
                <tr key={r.number}>
                  <Td><Link href={`/solicitations/${r.number}`}>{r.number}</Link></Td>
                  <Td>{title}</Td>
                  <Td>{agency.get(r.agency_id) ?? ""}</Td>
                  <Td>{r.bid_due_at ? <DateTime iso={r.bid_due_at} tz={tz} /> : "-"}</Td>
                  <Td><StatusBadge status={{ kind: "bidding", status: bidStatus(r.bid_due_at, now) }} /></Td>
                </tr>
              );
            })}
          </tbody>
        </Table>
      )}
    </Page>
  );
}
