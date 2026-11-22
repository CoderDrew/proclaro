import Link from "next/link";
import { notFound } from "next/navigation";
import { parseStoredData } from "@/domain/solicitation/schema";
import { memoReason, parseRecap } from "@/domain/recap/snapshot";
import { todayIn } from "@/domain/time";
import { createServerClient } from "@/lib/supabase/server";
import { formatInstant, onlyPublic } from "@/app/solicitations/status";
import { missingAcknowledgments } from "@/domain/addendum/ack";
import { Notice, Page, PageHeader } from "@/components/ui";
import { requireBidderPage } from "../../guard";
import { BidDraftForm, PrintBlankFormButton, StartBidButton } from "./BidDraftForm";
import { AddendaPanel, type AddendumAckView } from "./AddendaPanel";
import { CurePanel } from "./CurePanel";
import { OutcomePanel } from "./OutcomePanel";
import { QuestionsPanel } from "./QuestionsPanel";
import { ReceiptPanel } from "./ReceiptPanel";
import {
  addendaBanners, describeReceipt, isUuid, parseBiddingState, parseCureStatus, pricesClearedFor, questionsClosedText, questionsOpen,
  toAcks, toAddendaStatus, toBidDraft, toMyQuestions, toReceipts,
} from "./logic";

export const dynamic = "force-dynamic";

const LINK_SECONDS = 300;

export default async function BidderSolicitationPage({ params }: { params: Promise<{ id: string }> }) {
  await requireBidderPage();
  const { id } = await params;
  if (!isUuid(id)) notFound();

  const supabase = await createServerClient();
  const settings = await supabase.from("settings").select("timezone").eq("id", 1).single();
  if (settings.error) throw new Error(settings.error.message);
  const tz = settings.data.timezone;
  const now = new Date();

  // Only published, released solicitations are visible to a bidder (the same filter the public pages use).
  const sol = await onlyPublic(
    supabase.from("solicitations").select("id, number, bid_due_at, published_snapshot").eq("id", id),
    todayIn(tz, now),
  ).maybeSingle();
  if (sol.error) throw new Error(sol.error.message);
  if (!sol.data || !sol.data.bid_due_at) notFound();
  // The bid rules read the published snapshot, as the database does.
  const data = parseStoredData((sol.data.published_snapshot as { data?: unknown } | null)?.data);
  if (!data) {
    return (
      <Page width="full">
        <p className="ui-crumbs"><Link href="/bidder">Open solicitations</Link></p>
        <Notice tone="error" role="alert">This solicitation&apos;s data could not be read, so a bid cannot be prepared.</Notice>
      </Page>
    );
  }
  const dueAt = sol.data.bid_due_at;
  const due = formatInstant(dueAt, tz);
  // The database decides open/closed (its clock, its rules); the web server's clock is never consulted.
  const state = await supabase.rpc("bidding_state", { p_solicitation_id: id });
  if (state.error) throw new Error(state.error.message);
  const biddingState = parseBiddingState(state.data);
  const closed = biddingState === "closed";
  const open = biddingState === "open";

  // RLS limits every bid read to the caller's own organization. Questions are read only through my_questions
  // (the questions table would also show same-organization colleagues' asked_by).
  const [bid, myQuestions] = await Promise.all([
    supabase.from("bids").select("id, reference").eq("solicitation_id", id).maybeSingle(),
    supabase.rpc("my_questions", { p_solicitation_id: id }),
  ]);
  if (bid.error) throw new Error(bid.error.message);
  if (myQuestions.error) throw new Error(myQuestions.error.message);
  // Shown or hidden by questionsDue in the configured zone; ask_question judges it on the database clock.
  const questions = (
    <QuestionsPanel
      solicitationId={id}
      questions={toMyQuestions(myQuestions.data ?? [])}
      tz={tz}
      canAsk={questionsOpen(data.questionsDue, tz, now, biddingState)}
      closedText={questionsClosedText(data.questionsDue, tz)}
    />
  );

  const heading = (
    <PageHeader
      crumbs={<Link href="/bidder">Open solicitations</Link>}
      title={`${sol.data.number}: ${data.longTitle || data.shortTitle || "Solicitation"}`}
      actions={open ? <PrintBlankFormButton solicitationId={id} /> : undefined}
    />
  );

  if (!bid.data) {
    return (
      <Page width="full">
        {heading}
        <p>Bids are due {due}.</p>
        {closed ? <p>Bidding on this solicitation has closed.</p> : open ? <StartBidButton solicitationId={id} /> : <p>This solicitation is not open for bidding.</p>}
        {questions}
      </Page>
    );
  }

  const [draft, files, receipts, ackRes, statusRes] = await Promise.all([
    supabase.from("bid_drafts")
      .select("version, item_cents, alternate_cents, bid_bond_choice, apprentice_commitment, solicitation_version")
      .eq("bid_id", bid.data.id).maybeSingle(),
    supabase.from("bid_draft_files").select("slot, path, file_name").eq("bid_id", bid.data.id),
    supabase.rpc("my_bid_receipts", { p_bid_id: bid.data.id }),
    supabase.rpc("my_bid_acknowledgments", { p_bid_id: bid.data.id }),
    supabase.rpc("my_bid_status_addenda", { p_bid_id: bid.data.id }),
  ]);
  for (const r of [draft, files, receipts, ackRes, statusRes]) if (r.error) throw new Error(r.error.message);

  const acks = toAcks(ackRes.data ?? []);
  const addendaStatus = toAddendaStatus(statusRes.data ?? null);
  const resubmitRequired = addendaStatus?.resubmitRequired === true;
  const missing = missingAcknowledgments(
    acks.map((a) => a.addendumNumber),
    acks.filter((a) => a.acknowledgedAt !== null).map((a) => a.addendumNumber),
  );
  // Each addendum's PDF is its version's addendum_path (version = number + 1), as a short-lived signed link.
  const number = sol.data.number;
  let addendumRows: AddendumAckView[] = [];
  if (acks.length > 0) {
    const versions = await supabase.rpc("solicitation_version_list", { p_solicitation_id: id });
    if (versions.error) throw new Error(versions.error.message);
    const pathFor = new Map((versions.data ?? []).map((v) => [v.version, (v.addendum_path as string | null) ?? null]));
    addendumRows = await Promise.all(acks.map(async (a) => {
      const path = pathFor.get(a.addendumNumber + 1) ?? null;
      const signed = path
        ? await supabase.storage.from("published")
          .createSignedUrl(path, LINK_SECONDS, { download: `Addendum-${a.addendumNumber}-${number}.pdf` })
        : null;
      return {
        number: a.addendumNumber, publishedAt: a.publishedAt, acknowledgedAt: a.acknowledgedAt,
        pdfUrl: signed?.data?.signedUrl ?? null,
      };
    }));
  }
  const banners = addendaBanners(acks, addendaStatus, open);
  const addenda = (
    <>
      {banners.map((b) => (
        <Notice key={`${b.kind}-${b.addendum}`} tone="warning" data-testid={`banner-${b.kind}-${b.addendum}`}>{b.text}</Notice>
      ))}
      <AddendaPanel bidId={bid.data.id} rows={addendumRows} tz={tz} open={open} />
    </>
  );

  const rows = toReceipts(receipts.data ?? []);
  // After close, the database's cure status for the bid's latest version (before close it says not_required).
  let cure = null;
  if (closed && rows.length > 0) {
    const c = await supabase.rpc("my_bid_cure", { p_bid_id: bid.data.id });
    if (c.error) throw new Error(c.error.message);
    const row = c.data?.[0];
    cure = <CurePanel bidId={bid.data.id} status={parseCureStatus(row?.status)} dueAt={(row?.due_at as string | null) ?? null} tz={tz} />;
  }
  // The bid's outcome, which the database returns only once the recap or memo is posted.
  let outcome = null;
  if (closed) {
    const o = await supabase.rpc("my_bid_outcome", { p_bid_id: bid.data.id });
    if (o.error) throw new Error(o.error.message);
    const orow = o.data?.[0];
    if (orow) {
      // Under the all-rejected memo the memo's reason replaces "Accepted" (read from the public posted row).
      let memoReasonText: string | null = null;
      if (orow.recap_kind === "all_rejected") {
        const r = await supabase.from("recaps").select("snapshot").eq("solicitation_id", sol.data.id).single();
        if (r.error) throw new Error(r.error.message);
        const memo = parseRecap(r.data.snapshot);
        if (!memo || memo.kind !== "all_rejected") throw new Error("memo snapshot did not parse");
        memoReasonText = memoReason(memo);
      }
      outcome = (
        <OutcomePanel status={orow.status} reason={orow.reason} number={sol.data.number} memoReason={memoReasonText} />
      );
    }
  }
  const panel = (
    <ReceiptPanel
      bidId={bid.data.id}
      due={due}
      open={open}
      hasDraft={!!draft.data}
      notCounted={resubmitRequired}
      receipts={rows.map((r) => ({
        ...describeReceipt(r, tz, resubmitRequired), version: r.version, isCurrent: r.isCurrent, withdrawn: r.withdrawnAt !== null,
      }))}
    />
  );

  if (!draft.data) {
    return (
      <Page width="full">
        {heading}
        <p>Bid reference: <strong>{bid.data.reference}</strong></p>
        <p>Bids are due {due}.{closed && " Bidding on this solicitation has closed."}</p>
        {addenda}
        {cure}
        {outcome}
        {rows.length === 0 ? <p>This bid has no submitted version.</p> : panel}
        {questions}
      </Page>
    );
  }

  const bidDraft = toBidDraft(bid.data, draft.data, files.data ?? []);
  return (
    <Page width="full">
      {heading}
      {addenda}
      {cure}
      {outcome}
      {panel}
      <BidDraftForm
        // A new key after a schedule change remounts the form, so its inputs follow the new schedule.
        key={`${bidDraft.version}:${draft.data.solicitation_version}`}
        bidId={bidDraft.bidId}
        reference={bidDraft.reference}
        version={bidDraft.version}
        solicitationVersion={draft.data.solicitation_version}
        pricesCleared={pricesClearedFor(addendaStatus, open)}
        missingAcknowledgments={missing}
        due={due}
        readOnly={!open}
        rules={{
          estimateCents: data.estimateCents,
          optionalSections: data.optionalSections,
          schedule: data.schedule,
        }}
        initial={{
          itemCents: bidDraft.itemCents,
          alternateCents: bidDraft.alternateCents,
          bidBondChoice: bidDraft.bidBondChoice,
          apprenticeCommitment: bidDraft.apprenticeCommitment,
          files: bidDraft.files,
        }}
      />
      {questions}
    </Page>
  );
}
