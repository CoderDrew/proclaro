import { notFound } from "next/navigation";
import { dateChanges } from "@/documents/addendumDoc";
import { describeScheduleChange, diffSchedule } from "@/domain/addendum/diff";
import { parseStoredData } from "@/domain/solicitation/schema";
import { createServerClient } from "@/lib/supabase/server";
import { Notice, Page, PageHeader } from "@/components/ui";
import { requireOfficePage } from "../../../../guard";
import { AddendumReviewPanel, type ReviewFlags } from "./AddendumReviewPanel";
import { addendumHistory } from "./logic";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const NO_FLAGS: ReviewFlags = {
  canStart: false, canReturn: false, canSend: false, canApprove: false, canDisagree: false, canApproveAlone: false,
  canReopen: false, canPublish: false, canWithdraw: false, afterAnswersDue: false,
};

export default async function OfficeAddendumPage({ params }: { params: Promise<{ id: string; addendumId: string }> }) {
  const ctx = await requireOfficePage();
  const { id, addendumId } = await params;
  if (!UUID.test(id) || !UUID.test(addendumId)) notFound();

  const supabase = await createServerClient();
  const [solRes, addRes] = await Promise.all([
    supabase.from("solicitations").select("id, number, version, data, published_snapshot, agency_id").eq("id", id)
      .maybeSingle(),
    supabase.from("addenda")
      .select("id, solicitation_id, number, state, data, narrative, reviewer_id, checker_id, single_reviewer, published_version, withdrawn_reason")
      .eq("id", addendumId).maybeSingle(),
  ]);
  if (solRes.error) throw new Error(solRes.error.message);
  if (addRes.error) throw new Error(addRes.error.message);
  const sol = solRes.data;
  const add = addRes.data;
  if (!sol || !add || add.solicitation_id !== id) notFound();

  const canWork = ctx.orgKind === "office";
  // The version the addendum changes: the one before it once published, else the current published version.
  const baseVersion = add.published_version ? add.published_version - 1 : sol.version ?? 1;
  const [settings, info, answers, audit, officeOrgs, base, agency] = await Promise.all([
    supabase.from("settings").select("timezone").eq("id", 1).single(),
    canWork ? supabase.rpc("addendum_review_info", { p_addendum_id: addendumId }) : Promise.resolve(null),
    supabase.rpc("addendum_answers_draft", { p_addendum_id: addendumId }),
    supabase.from("audit_log").select("id, actor_id, action, detail, created_at").eq("solicitation_id", id)
      .eq("detail->>addendum_id", addendumId)
      .order("created_at", { ascending: false }).order("id", { ascending: false }),
    supabase.from("organizations").select("id").eq("kind", "office"),
    supabase.from("solicitation_versions").select("snapshot").eq("solicitation_id", id).eq("version", baseVersion)
      .maybeSingle(),
    supabase.from("organizations").select("name").eq("id", sol.agency_id).single(),
  ]);
  for (const r of [settings, info, answers, audit, officeOrgs, base, agency]) {
    if (r && r.error) throw new Error(r.error.message);
  }

  const staff = await supabase.from("profiles").select("user_id, display_name")
    .in("org_id", officeOrgs.data!.map((o) => o.id));
  if (staff.error) throw new Error(staff.error.message);
  const names = new Map(staff.data.map((p) => [p.user_id, p.display_name]));

  const tz = settings.data!.timezone;
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: tz, dateStyle: "medium", timeStyle: "short" });
  const history = addendumHistory(audit.data!, names, (iso) => fmt.format(new Date(iso)));

  const crumbs = (
    <>
      <a href="/office">Office queues</a> / <a href={`/office/solicitations/${id}`}>{sol.number ?? "Solicitation"}</a>
    </>
  );
  const title = `Addendum ${add.number}`;
  const eyebrow = sol.number ? `${sol.number} · ${agency.data!.name}` : agency.data!.name;

  const data = parseStoredData(add.data);
  // Unpublished: the current published snapshot is the fallback (it is the same version).
  const baseData = parseStoredData((base.data?.snapshot as { data?: unknown } | null)?.data)
    ?? (add.published_version ? null : parseStoredData((sol.published_snapshot as { data?: unknown } | null)?.data));
  const row = info?.data?.[0];
  const flags: ReviewFlags = row ? {
    canStart: row.can_start, canReturn: row.can_return, canSend: row.can_send, canApprove: row.can_approve,
    canDisagree: row.can_disagree, canApproveAlone: row.can_approve_alone, canReopen: row.can_reopen,
    canPublish: row.can_publish, canWithdraw: row.can_withdraw, afterAnswersDue: row.after_answers_due,
  } : NO_FLAGS;
  const effectiveState = row?.effective_state ?? add.state;

  return (
    <Page width="full">
      <PageHeader crumbs={crumbs} eyebrow={eyebrow} title={title} />
      {data === null && (
        <Notice tone="error" role="alert">
          This addendum&apos;s saved data could not be read, so its changes can&apos;t be shown. Return it to the agency.
        </Notice>
      )}
      <AddendumReviewPanel
        key={`${effectiveState}:${add.reviewer_id}:${history.length}`}
        addendumId={addendumId}
        number={add.number}
        state={effectiveState}
        canWork={canWork}
        flags={flags}
        reviewerId={add.reviewer_id}
        reviewerName={add.reviewer_id ? names.get(add.reviewer_id) ?? null : null}
        checkerName={add.checker_id ? names.get(add.checker_id) ?? null : null}
        singleReviewer={add.single_reviewer}
        withdrawnReason={add.withdrawn_reason}
        publishedVersion={add.published_version}
        solicitationNumber={sol.number}
        narrative={add.narrative}
        changes={data && baseData ? diffSchedule(baseData.schedule, data.schedule).map(describeScheduleChange) : null}
        dateChanges={data && baseData ? dateChanges(baseData, data, tz) : null}
        answers={answers.data!.map((a) => ({ questionId: a.question_id, publishedQuestion: a.published_question, answer: a.answer }))}
        staff={staff.data.map((p) => ({ userId: p.user_id, name: p.display_name }))}
        history={history}
      />
    </Page>
  );
}
