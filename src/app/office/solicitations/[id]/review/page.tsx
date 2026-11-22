import { notFound } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { formatInstant } from "@/app/solicitations/status";
import { requireOfficePage } from "../../../guard";
import { Notice, Page, PageHeader, StatusBadge } from "@/components/ui";
import { cureView, outcomeEditable, outcomeFormNote, sendFlagsEnabled } from "./logic";
import { ReviewTable, type ClaimView, type ReviewRowView } from "./ReviewTable";
import { RecapPanel, type RecapPanelProps } from "./RecapPanel";
import { AwardPanel, type AwardPanelProps } from "./AwardPanel";
import { parseAward, parseRecap } from "@/domain/recap/snapshot";
import { aiCheckConfig } from "@/server/aicheck/openai";
import { DocumentCheckPanel } from "./aicheck/DocumentCheckPanel";
import { parseCheck, type CheckView } from "./aicheck/view";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The office's bid review after close: one row per opened bid with its derived status (public.review_bids), an
 * outcome form per bid, and the resident certificate checks. The database decides everything: sealing (review_bids
 * raises `sealed` before close), the automatic statuses and the stage that allows changes.
 */
export default async function OfficeReviewPage({ params }: { params: Promise<{ id: string }> }) {
  const ctx = await requireOfficePage();
  const { id } = await params;
  if (!UUID.test(id)) notFound();

  const supabase = await createServerClient();
  const { data: sol, error } = await supabase
    .from("solicitations")
    .select("id, number, state, data, bid_due_at")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!sol) notFound();
  const title = (sol.data as { shortTitle?: string } | null)?.shortTitle || "(untitled)";

  const header = (stage?: React.ReactNode) => (
    <PageHeader
      crumbs={<>
        <a href="/office">Office queues</a> · <a href={`/office/solicitations/${id}`}>{sol.number ?? "Solicitation"}</a>
        {" · "}<a href={`/office/solicitations/${id}/bids`}>Bids</a>
      </>}
      title={`Bid review: ${title}`}
      actions={stage}
    />
  );

  if (ctx.orgKind !== "office") {
    return <Page width="full">{header()}<Notice tone="info">Only office staff can review bids.</Notice></Page>;
  }
  if (sol.state !== "published" || !sol.bid_due_at) {
    return <Page width="full">{header()}<Notice tone="info">This solicitation is not published, so it has no bids.</Notice></Page>;
  }

  const settings = await supabase.from("settings").select("timezone").eq("id", 1).single();
  if (settings.error) throw new Error(settings.error.message);
  const tz = settings.data.timezone;

  // review_bids first: it creates the evaluation row at close, so the stage read below always finds it.
  const review = await supabase.rpc("review_bids", { p_solicitation_id: id });
  if (review.error) {
    if (review.error.message === "sealed") {
      return (
        <Page width="full">
          {header()}
          <Notice tone="warning" data-testid="sealed">
            <strong>Bids are sealed until {formatInstant(sol.bid_due_at, tz)}.</strong>
          </Notice>
        </Page>
      );
    }
    throw new Error(review.error.message);
  }

  const [evaluation, claims] = await Promise.all([
    // Only the stage columns are readable through the API; never select('*') here.
    supabase.from("evaluations").select("solicitation_id, stage, flags_released_at, updated_at")
      .eq("solicitation_id", id).maybeSingle(),
    supabase.rpc("resident_claims", { p_solicitation_id: id }),
  ]);
  if (evaluation.error) throw new Error(evaluation.error.message);
  if (claims.error) throw new Error(claims.error.message);

  const stage = evaluation.data?.stage ?? "bid_review";
  const rows = review.data;
  // "Awaiting agency" is displayed, not stored: flags were released and a bid is still flagged.
  const releasedAt = evaluation.data?.flags_released_at ?? null;
  const awaitingAgency = stage === "bid_review" && !!releasedAt
    && rows.some((r) => r.status === "flagged");
  const names = new Map(rows.map((r) => [r.bid_id, r.bidder_name]));

  const view: ReviewRowView[] = rows.map((r) => {
    const reason = r.status_reason ?? null;
    const editable = outcomeEditable(stage, r.status, reason);
    return {
      bidId: r.bid_id,
      outcomeId: r.outcome_id ?? null,
      reference: r.reference,
      version: r.version,
      missingAddenda: r.missing_addenda ?? [],
      bidderName: r.bidder_name,
      baseTotalCents: r.base_total_cents,
      apprentice: r.apprentice_commitment ?? null,
      status: r.status,
      statusReason: reason,
      cure: cureView(r.cure_status ?? null, r.cure_due_at ?? null),
      outcome: r.outcome ?? null,
      ground: r.ground ?? null,
      note: r.note ?? null,
      editable,
      formNote: outcomeFormNote(stage, r.status, editable),
    };
  });
  const [recap, award] = await Promise.all([loadRecap(supabase, id, stage), loadAward(supabase, id, stage)]);
  const { checks, links } = await loadChecks(supabase, rows);
  const aiEnabled = aiCheckConfig().enabled;

  const claimView: ClaimView[] = claims.data.map((c) => ({
    bidId: c.bid_id,
    reference: c.reference,
    bidderName: names.get(c.bid_id) ?? "",
    certificate: c.certificate ?? "",
    verified: c.verified ?? null,
    note: c.note ?? null,
    verifiedAt: c.verified_at ?? null,
  }));

  return (
    <Page width="full">
      {header(<StatusBadge status={{ kind: "evaluation", stage, awaitingAgency }} data-testid="stage" />)}
      <p>
        Bid due: {formatInstant(sol.bid_due_at, tz)}. Every change to an outcome is kept. Statuses for a missing
        signed original or a bid bond not received by the cure deadline are set automatically.
      </p>
      <ReviewTable
        rows={view}
        claims={claimView}
        tz={tz}
        canVerify={stage === "bid_review"}
        sendFlags={{
          solicitationId: id,
          enabled: sendFlagsEnabled(stage, releasedAt, rows.map((r) => r.status)),
          note: releasedAt
            ? `Flagged bids were sent to the agency on ${formatInstant(releasedAt, tz)}. A bid flagged later reaches the agency at once.`
            : stage !== "bid_review"
              ? "The review has moved on, so flagged bids can no longer be sent."
              : !rows.some((r) => r.status === "flagged")
                ? "No bid is flagged for the agency."
                : "The agency sees only each flagged bid's reference, your note and its base total. Every bid needs an outcome first, and no bid bond cure may be pending.",
        }}
      />
      <RecapPanel solicitationId={id} stage={stage} tz={tz} {...recap} />
      {award ? <AwardPanel solicitationId={id} stage={stage} tz={tz} {...award} /> : null}
      <h2>Document checks</h2>
      {checks.map((c) => (
        <DocumentCheckPanel key={c.bidId} solicitationId={id} bidId={c.bidId} reference={c.reference}
          bidderName={c.bidderName} enabled={aiEnabled} check={c.check} links={links} />
      ))}
    </Page>
  );
}

type Client = Awaited<ReturnType<typeof createServerClient>>;

/**
 * Each opened bid's latest document check (office only, after close) and short-lived signed links to the documents
 * it checked, so the reviewer can open the page an excerpt came from.
 */
async function loadChecks(
  supabase: Client, rows: { bid_id: string; reference: string; bidder_name: string }[],
): Promise<{ checks: { bidId: string; reference: string; bidderName: string; check: CheckView }[]; links: Record<string, string> }> {
  const checks = await Promise.all(rows.map(async (r) => {
    const res = await supabase.rpc("bid_ai_check", { p_bid_id: r.bid_id });
    if (res.error) throw new Error(res.error.message);
    return { bidId: r.bid_id, reference: r.reference, bidderName: r.bidder_name, check: parseCheck(res.data) };
  }));
  const paths = [...new Set(checks.flatMap((c) => c.check.items.map((i) => i.documentPath))
    .filter((p): p is string => p !== null))];
  const links: Record<string, string> = {};
  if (paths.length > 0) {
    const signed = await supabase.storage.from("bid-files").createSignedUrls(paths, 600);
    for (const s of signed.data ?? []) if (s.path && s.signedUrl && !s.error) links[s.path] = s.signedUrl;
  }
  return { checks, links };
}
type RecapData = Pick<RecapPanelProps, "preview" | "returned" | "draft" | "posted">;

/**
 * What the recap panel needs for the stage: the live preview (bid_review), the frozen draft through the office-only
 * public.recap_draft (recap_check; recap_draft has no API grant), or the public posted row. A snapshot that does not
 * parse is a contract break with app.build_recap, so it throws rather than showing a partial recap.
 */
async function loadRecap(supabase: Client, id: string, stage: string): Promise<RecapData> {
  const none: RecapData = { preview: null, returned: null, draft: null, posted: null };
  const parsed = (raw: unknown) => {
    const r = parseRecap(raw);
    if (!r) throw new Error("recap snapshot did not parse");
    return r;
  };

  if (stage === "bid_review") {
    const [pv, audit] = await Promise.all([
      supabase.rpc("preview_recap", { p_solicitation_id: id }),
      // The latest send or disagreement: a disagreement after the last send is the checker's comment.
      supabase.from("bid_audit_log").select("action, detail, created_at").eq("solicitation_id", id)
        .in("action", ["send_recap_to_check", "disagree_recap"])
        .order("id", { ascending: false }).limit(1).maybeSingle(),
    ]);
    if (pv.error) throw new Error(pv.error.message);
    if (audit.error) throw new Error(audit.error.message);
    const p = pv.data as { recap: unknown; blockers: string[] };
    const detail = audit.data?.detail as { comment?: unknown } | null | undefined;
    return {
      ...none,
      preview: { recap: parsed(p.recap), blockers: p.blockers },
      returned: audit.data?.action === "disagree_recap" && typeof detail?.comment === "string"
        ? { comment: detail.comment, at: audit.data.created_at } : null,
    };
  }
  if (stage === "recap_check") {
    const d = await supabase.rpc("recap_draft", { p_solicitation_id: id });
    if (d.error) throw new Error(d.error.message);
    const v = d.data as { recap: unknown; preparedBy: string | null; canCheck: boolean; canRecall: boolean } | null;
    return {
      ...none,
      draft: v ? {
        recap: parsed(v.recap), preparedBy: v.preparedBy, canCheck: v.canCheck === true, canRecall: v.canRecall === true,
      } : null,
    };
  }
  const row = await supabase.from("recaps").select("snapshot, posted_at, single_reviewer")
    .eq("solicitation_id", id).maybeSingle();
  if (row.error) throw new Error(row.error.message);
  if (!row.data) return none;
  return {
    ...none,
    posted: { recap: parsed(row.data.snapshot), postedAt: row.data.posted_at, singleReviewer: row.data.single_reviewer },
  };
}

type AwardData = Pick<AwardPanelProps, "pick" | "check" | "returned" | "award">;

/**
 * What the award panel needs once the recap is posted: the agency's current choice (public.current_award_pick;
 * award_picks has no API grant), who sent it to check, whether this user may check it and whether the agency must
 * pick again after a disagreement (public.award_check_info; those columns have no API grant), the checker's last comment, and the public awards row. Null before the recap is
 * posted and for the "all bids rejected" memo (no award).
 */
async function loadAward(supabase: Client, id: string, stage: string): Promise<AwardData | null> {
  if (stage !== "recap_posted" && stage !== "award_check" && stage !== "awarded") return null;
  const [pick, check, audit, row] = await Promise.all([
    supabase.rpc("current_award_pick", { p_solicitation_id: id }),
    supabase.rpc("award_check_info", { p_solicitation_id: id }),
    supabase.from("bid_audit_log").select("action, detail, created_at").eq("solicitation_id", id)
      .in("action", ["send_award_to_check", "disagree_award"])
      .order("id", { ascending: false }).limit(1).maybeSingle(),
    supabase.from("awards").select("snapshot, posted_at, single_reviewer").eq("solicitation_id", id).maybeSingle(),
  ]);
  if (pick.error) throw new Error(pick.error.message);
  if (check.error) throw new Error(check.error.message);
  if (audit.error) throw new Error(audit.error.message);
  if (row.error) throw new Error(row.error.message);

  let award: AwardData["award"] = null;
  if (row.data) {
    const a = parseAward(row.data.snapshot);
    if (!a) throw new Error("award snapshot did not parse");
    award = { award: a, postedAt: row.data.posted_at, singleReviewer: row.data.single_reviewer };
  }
  const p = pick.data[0];
  const c = check.data[0];
  const detail = audit.data?.detail as { comment?: unknown } | null | undefined;
  return {
    pick: p ? {
      reference: p.reference, reason: p.reason ?? null, pickedAt: p.picked_at, differsFromExpected: p.differs_from_expected,
    } : null,
    check: c ? { preparedBy: c.prepared_by ?? null, canCheck: c.can_check, needsNewPick: c.needs_new_pick } : null,
    returned: stage === "recap_posted" && audit.data?.action === "disagree_award" && typeof detail?.comment === "string"
      ? { comment: detail.comment, at: audit.data.created_at } : null,
    award,
  };
}
