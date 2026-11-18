import { notFound } from "next/navigation";
import { parseStoredData } from "@/domain/solicitation/schema";
import { createServerClient } from "@/lib/supabase/server";
import { Notice, Page, PageHeader } from "@/components/ui";
import { requireAgencyPage } from "../../guard";
import { SolicitationForm } from "./SolicitationForm";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function SolicitationPage({ params }: { params: Promise<{ id: string }> }) {
  const ctx = await requireAgencyPage();
  const { id } = await params;
  if (!UUID.test(id)) notFound();

  const supabase = await createServerClient();
  // RLS hides other agencies' rows; the explicit agency check is a second line of defense.
  const { data: row, error } = await supabase
    .from("solicitations")
    .select("id, agency_id, state, number, data")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!row || row.agency_id !== ctx.orgId) notFound();

  const [settings, holidays, acks, comments] = await Promise.all([
    supabase.from("settings").select("timezone").eq("id", 1).single(),
    supabase.from("holidays").select("day"),
    supabase.from("warning_acks").select("code, field").eq("solicitation_id", id),
    supabase.from("comments").select("field, body, created_at").eq("solicitation_id", id).eq("kind", "return")
      .order("created_at", { ascending: false }),
  ]);
  for (const r of [settings, holidays, acks, comments]) if (r.error) throw new Error(r.error.message);

  const data = parseStoredData(row.data);
  if (data === null) {
    return (
      <Page width="full">
        <PageHeader crumbs={<a href="/agency">My solicitations</a>} title={row.number ?? "Solicitation"} />
        <Notice tone="error" role="alert">
          This solicitation&apos;s saved data could not be read, so it cannot be shown or edited here.
          Contact the procurement office.
        </Notice>
      </Page>
    );
  }

  return (
    <Page width="full">
      <PageHeader crumbs={<a href="/agency">My solicitations</a>} title={data.shortTitle || "New solicitation"} />
      <SolicitationForm
        id={id}
        initial={data}
        state={row.state}
        number={row.number}
        tz={settings.data!.timezone}
        holidays={holidays.data!.map((h) => h.day)}
        acks={acks.data!.map((a) => `${a.code}|${a.field ?? ""}`)}
        comments={comments.data!.map((c) => ({ field: c.field, body: c.body }))}
      />
    </Page>
  );
}
