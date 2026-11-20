import { notFound } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { formatInstant } from "@/app/solicitations/status";
import { Notice, Page, PageHeader } from "@/components/ui";
import { requireAgencyPage } from "../../../guard";
import { canDecide, canPick } from "./logic";
import { FlaggedPanel, type FlaggedBidView } from "./FlaggedPanel";
import { AwardPickPanel, type AwardPickPanelProps } from "./AwardPickPanel";
import { memoText, parseAward, parseRecap } from "@/domain/recap/snapshot";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The owning agency's bids page after close. Before the recap is posted the agency sees only the bids the office
 * flagged for it (public.agency_flagged_bids: reference, the reviewer's note, the base total and its decision), and
 * accepts or rejects each one with a reason. The database decides sealing (agency_flagged_bids raises `sealed` before
 * close) and returns nothing until the office sends the flagged bids.
 */
export default async function AgencyBidsPage({ params }: { params: Promise<{ id: string }> }) {
  const ctx = await requireAgencyPage();
  const { id } = await params;
  if (!UUID.test(id)) notFound();

  const supabase = await createServerClient();
  // RLS hides other agencies' rows; the explicit agency check is a second line of defense.
  const { data: sol, error } = await supabase
    .from("solicitations")
    .select("id, agency_id, state, number, data, bid_due_at")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!sol || sol.agency_id !== ctx.orgId) notFound();
  const title = (sol.data as { shortTitle?: string } | null)?.shortTitle || "(untitled)";

  const header = (
    <PageHeader
      crumbs={<><a href="/agency">My solicitations</a> · <a href={`/agency/solicitations/${id}`}>{sol.number ?? "Solicitation"}</a></>}
      title={`Bids and award: ${title}`}
    />
  );

  if (sol.state !== "published" || !sol.bid_due_at) {
    return <Page width="full">{header}<Notice tone="info">This solicitation is not published, so it has no bids.</Notice></Page>;
  }

  const settings = await supabase.from("settings").select("timezone").eq("id", 1).single();
  if (settings.error) throw new Error(settings.error.message);
  const tz = settings.data.timezone;

  const flagged = await supabase.rpc("agency_flagged_bids", { p_solicitation_id: id });
  if (flagged.error) {
    if (flagged.error.message === "sealed") {
      return (
        <Page width="full">
          {header}
          <Notice tone="warning" data-testid="sealed">
            <strong>Bids are sealed until {formatInstant(sol.bid_due_at, tz)}.</strong> Nothing about the bids is shown
            before then.
          </Notice>
        </Page>
      );
    }
    throw new Error(flagged.error.message);
  }

  // Only the stage columns are readable through the API; never select('*') here.
  const evaluation = await supabase.from("evaluations").select("solicitation_id, stage, flags_released_at")
    .eq("solicitation_id", id).maybeSingle();
  if (evaluation.error) throw new Error(evaluation.error.message);
  const stage = evaluation.data?.stage ?? null;
  const releasedAt = evaluation.data?.flags_released_at ?? null;
  const decidable = canDecide(stage, releasedAt);

  const bids: FlaggedBidView[] = flagged.data.map((r) => ({
    outcomeId: r.outcome_id,
    reference: r.reference,
    note: r.note,
    baseTotalCents: r.base_total_cents,
    decision: r.decision ?? null,
    decisionReason: r.decision_reason ?? null,
    decidedAt: r.decided_at ?? null,
  }));

  const award = await loadAward(supabase, id, stage);

  return (
    <Page width="full">
      {header}
      <p>
        Bid due: {formatInstant(sol.bid_due_at, tz)}. The procurement office reviews every bid. It sends you only the
        bids it accepted with a flag, so you can accept or reject each one with a reason. The bid recap is posted
        after the review.
      </p>
      {releasedAt ? (
        <p className="muted" data-testid="released">
          The office sent the flagged bids on {formatInstant(releasedAt, tz)}.
        </p>
      ) : (
        <Notice tone="info" data-testid="not-released">The office has not sent any flagged bids yet.</Notice>
      )}
      <FlaggedPanel
        bids={bids}
        tz={tz}
        canDecide={decidable}
        closedNote={!decidable && releasedAt ? "The review has moved on, so decisions can no longer be changed." : null}
      />
      {award.memo ? (
        <Notice tone="info" data-testid="award-memo"><strong>{award.memo}</strong> There is no award.</Notice>
      ) : null}
      {award.panel ? <AwardPickPanel solicitationId={id} tz={tz} {...award.panel} /> : null}
    </Page>
  );
}

type Client = Awaited<ReturnType<typeof createServerClient>>;

/**
 * The award section once a recap or memo is posted (public.recaps, readable by everyone). The agency's current choice
 * comes from public.current_award_pick (award_picks has no API grant), and the posted award from public.awards. A
 * snapshot that does not parse is a contract break with the database, so it throws.
 */
async function loadAward(supabase: Client, id: string, stage: string | null): Promise<{
  memo: string | null;
  panel: Omit<AwardPickPanelProps, "solicitationId" | "tz"> | null;
}> {
  const none = { memo: null, panel: null };
  if (stage !== "recap_posted" && stage !== "award_check" && stage !== "awarded" && stage !== "all_rejected") return none;
  const posted = await supabase.from("recaps").select("snapshot").eq("solicitation_id", id).maybeSingle();
  if (posted.error) throw new Error(posted.error.message);
  if (!posted.data) return none;
  const recap = parseRecap(posted.data.snapshot);
  if (!recap) throw new Error("recap snapshot did not parse");
  if (recap.kind === "all_rejected") return { memo: memoText(recap), panel: null };

  const [pick, awardRow] = await Promise.all([
    supabase.rpc("current_award_pick", { p_solicitation_id: id }),
    supabase.from("awards").select("snapshot, posted_at, single_reviewer").eq("solicitation_id", id).maybeSingle(),
  ]);
  if (pick.error) throw new Error(pick.error.message);
  if (awardRow.error) throw new Error(awardRow.error.message);
  let award: AwardPickPanelProps["award"] = null;
  if (awardRow.data) {
    const a = parseAward(awardRow.data.snapshot);
    if (!a) throw new Error("award snapshot did not parse");
    award = { award: a, postedAt: awardRow.data.posted_at, singleReviewer: awardRow.data.single_reviewer };
  }
  const p = pick.data[0];
  const pickable = canPick(stage);
  return {
    memo: null,
    panel: {
      recap,
      canPick: pickable,
      closedNote: pickable ? null
        : stage === "award_check" ? "The procurement office is checking the award, so the choice cannot be changed now."
          : "The award is posted, so the choice cannot be changed.",
      pick: p ? {
        bidId: p.bid_id, reference: p.reference, reason: p.reason ?? null, pickedAt: p.picked_at,
        differsFromExpected: p.differs_from_expected,
      } : null,
      award,
    },
  };
}
