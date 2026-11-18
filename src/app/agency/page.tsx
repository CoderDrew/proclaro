import { todayIn } from "@/domain/time";
import { createServerClient } from "@/lib/supabase/server";
import { createSolicitation } from "./solicitations/new/actions";
import { Button, Card, EmptyState, Page, PageHeader, StatusBadge, Table, Td, Th } from "@/components/ui";
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
    <Page width="full">
      <PageHeader
        title="My solicitations"
        actions={(
          <form action={create}>
            <Button type="submit" variant="primary">New solicitation</Button>
          </form>
        )}
      />
      <Card>
      {rows.length === 0 ? (
        <EmptyState>No solicitations yet.</EmptyState>
      ) : (
        <Table>
          <thead>
            <tr><Th>Number</Th><Th>Title</Th><Th>State</Th><Th>Created</Th></tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const title = (r.data as { shortTitle?: string } | null)?.shortTitle || "(untitled draft)";
              return (
                <tr key={r.id}>
                  <Td>{r.number ?? "-"}</Td>
                  <Td><a href={`/agency/solicitations/${r.id}`}>{title}</a></Td>
                  <Td><StatusBadge status={{ kind: "solicitation", state: r.state }} /></Td>
                  <Td>{todayIn(tz, new Date(r.created_at))}</Td>
                </tr>
              );
            })}
          </tbody>
        </Table>
      )}
      </Card>
    </Page>
  );
}
