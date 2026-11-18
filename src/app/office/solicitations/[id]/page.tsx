import { notFound } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { requireOfficePage } from "../../guard";
import { describeChanges } from "./history";
import { InvalidDataPanel } from "./InvalidDataPanel";
import { parseStoredData } from "@/domain/solicitation/schema";
import { submissionDateOf } from "./logic";
import { ReviewPanel, type AuditRow } from "./ReviewPanel";
import { Page, PageHeader } from "@/components/ui";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const ACTION_LABELS: Record<string, string> = {
  submit_solicitation: "Submitted", start_review: "Review started", reassign_review: "Review reassigned",
  office_update_data: "Edited by reviewer", return_to_agency: "Returned to agency", send_to_check: "Sent to check",
  approve_check: "Approved by checker", disagree: "Checker disagreed", approve_alone: "Approved alone (fallback)",
  publish_solicitation: "Published", acknowledge_warning: "Warning acknowledged",
  reopen_review: "Reopened to correct dates",
};

type Detail = Record<string, unknown>;

/** The reason or note shown under a history row, when the action carries one. */
function noteFor(action: string, d: Detail, names: Map<string, string>): string | null {
  if (typeof d.reason === "string" && d.reason !== "") {
    return `Reason: ${d.reason}`;
  }
  if (action === "disagree" && typeof d.comment === "string") return `Comment: ${d.comment}`;
  if (action === "approve_alone") return "Fallback: no second reviewer available. Recorded as a single-reviewer approval.";
  if (action === "return_to_agency" && Array.isArray(d.comments)) {
    return (d.comments as { field: string | null; body: string }[])
      .map((c) => (c.field ? `${c.field}: ${c.body}` : c.body)).join(" | ");
  }
  if (action === "reassign_review") {
    const to = typeof d.new_reviewer_id === "string" ? names.get(d.new_reviewer_id) : null;
    return to ? `New reviewer: ${to}` : null;
  }
  return null;
}

export default async function OfficeSolicitationPage({ params }: { params: Promise<{ id: string }> }) {
  const ctx = await requireOfficePage();
  const { id } = await params;
  if (!UUID.test(id)) notFound();

  const supabase = await createServerClient();
  const { data: row, error } = await supabase
    .from("solicitations")
    .select("id, agency_id, state, number, data, latest_submitted_at, reviewer_id, checker_id, fallback_approved")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!row) notFound();

  const [settings, holidays, acks, comments, audit, agency, officeOrgs] = await Promise.all([
    supabase.from("settings").select("timezone").eq("id", 1).single(),
    supabase.from("holidays").select("day"),
    supabase.from("warning_acks").select("code, field").eq("solicitation_id", id),
    supabase.from("comments").select("field, body, created_at").eq("solicitation_id", id).eq("kind", "disagree")
      .order("created_at", { ascending: false }),
    supabase.from("audit_log").select("id, actor_id, action, detail, created_at").eq("solicitation_id", id)
      .order("created_at", { ascending: false }).order("id", { ascending: false }),
    supabase.from("organizations").select("name").eq("id", row.agency_id).single(),
    supabase.from("organizations").select("id").eq("kind", "office"),
  ]);
  for (const r of [settings, holidays, acks, comments, audit, agency, officeOrgs]) if (r.error) throw new Error(r.error.message);

  const staff = await supabase.from("profiles").select("user_id, display_name")
    .in("org_id", officeOrgs.data!.map((o) => o.id));
  if (staff.error) throw new Error(staff.error.message);
  const names = new Map(staff.data.map((p) => [p.user_id, p.display_name]));

  const tz = settings.data!.timezone;
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: tz, dateStyle: "medium", timeStyle: "short" });
  const auditRows: AuditRow[] = audit.data!.map((a) => ({
    id: a.id,
    actor: (a.actor_id && names.get(a.actor_id)) || "Agency author",
    action: ACTION_LABELS[a.action] ?? a.action,
    when: fmt.format(new Date(a.created_at)),
    reason: noteFor(a.action, (a.detail ?? {}) as Detail, names),
    changes: a.action === "office_update_data" ? describeChanges((a.detail as Detail | null)?.changes) : [],
  }));

  // Checker comments from before the latest review start belong to an earlier round.
  const lastStart = audit.data!.find((a) => a.action === "start_review")?.created_at ?? "";
  const checkerComments = comments.data!
    .filter((c) => c.created_at >= lastStart)
    .map((c) => ({ field: c.field, body: c.body }));

  const data = parseStoredData(row.data);
  if (data === null) {
    // Stored data that no longer matches the schema cannot be edited or published here; the agency must fix it.
    return (
      <Page width="full">
        <PageHeader
          crumbs={<>
              <a href="/office">Office queues</a>
              {row.state === "published" && <> · <a href={`/office/solicitations/${id}/bids`}>Bids</a></>}
            </>}
          title={row.number ?? "(unnumbered solicitation)"}
        />
        <InvalidDataPanel
          id={id}
          state={row.state}
          canWork={ctx.orgKind === "office"}
          isReviewer={row.reviewer_id === ctx.userId}
          agencyName={agency.data!.name}
          audit={auditRows}
        />
      </Page>
    );
  }

  return (
    <Page width="full">
      <PageHeader
        crumbs={<>
          <a href="/office">Office queues</a>
          {row.state === "published" && <> · <a href={`/office/solicitations/${id}/bids`}>Bids</a></>}
        </>}
        eyebrow={row.number ? `${row.number} · ${agency.data!.name}` : undefined}
        title={data.shortTitle || "(untitled)"}
      />
      <ReviewPanel
        key={`${row.state}:${row.reviewer_id}:${auditRows.length}`}
        id={id}
        initial={data}
        state={row.state}
        number={row.number}
        agencyName={agency.data!.name}
        reviewerId={row.reviewer_id}
        checkerId={row.checker_id}
        reviewerName={row.reviewer_id ? names.get(row.reviewer_id) ?? null : null}
        fallbackApproved={row.fallback_approved}
        viewerId={ctx.userId}
        canWork={ctx.orgKind === "office"}
        tz={tz}
        holidays={holidays.data!.map((h) => h.day)}
        submissionDate={submissionDateOf(row.latest_submitted_at, tz)}
        acks={acks.data!.map((a) => `${a.code}|${a.field ?? ""}`)}
        checkerComments={checkerComments}
        staff={staff.data.map((p) => ({ userId: p.user_id, name: p.display_name }))}
        audit={auditRows}
      />
    </Page>
  );
}
