import Link from "next/link";
import { notFound } from "next/navigation";
import { parseStoredData } from "@/domain/solicitation/schema";
import { todayIn } from "@/domain/time";
import { createServerClient } from "@/lib/supabase/server";
import { formatInstant, onlyPublic } from "@/app/solicitations/status";
import { requireBidderPage } from "../../guard";
import { BidDraftForm, StartBidButton } from "./BidDraftForm";
import { ReceiptPanel } from "./ReceiptPanel";
import { describeReceipt, isUuid, parseBiddingState, toBidDraft, toReceipts } from "./logic";

export const dynamic = "force-dynamic";

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
      <main>
        <p style={{ margin: "0 0 8px" }}><Link href="/bidder">Open solicitations</Link></p>
        <p role="alert" className="error">This solicitation&apos;s data could not be read, so a bid cannot be prepared.</p>
      </main>
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

  // RLS limits every bid read to the caller's own organization.
  const bid = await supabase.from("bids").select("id, reference").eq("solicitation_id", id).maybeSingle();
  if (bid.error) throw new Error(bid.error.message);

  const heading = (
    <>
      <p style={{ margin: "0 0 8px" }}><Link href="/bidder">Open solicitations</Link></p>
      <h1>{sol.data.number}: {data.longTitle || data.shortTitle || "Solicitation"}</h1>
    </>
  );

  if (!bid.data) {
    return (
      <main>
        {heading}
        <p>Bids are due {due}.</p>
        {closed ? <p>Bidding on this solicitation has closed.</p> : open ? <StartBidButton solicitationId={id} /> : <p>This solicitation is not open for bidding.</p>}
      </main>
    );
  }

  const [draft, files, receipts] = await Promise.all([
    supabase.from("bid_drafts").select("version, item_cents, alternate_cents, bid_bond_choice").eq("bid_id", bid.data.id).maybeSingle(),
    supabase.from("bid_draft_files").select("slot, path, file_name").eq("bid_id", bid.data.id),
    supabase.rpc("my_bid_receipts", { p_bid_id: bid.data.id }),
  ]);
  for (const r of [draft, files, receipts]) if (r.error) throw new Error(r.error.message);

  const rows = toReceipts(receipts.data ?? []);
  const panel = (
    <ReceiptPanel
      bidId={bid.data.id}
      due={due}
      open={open}
      hasDraft={!!draft.data}
      receipts={rows.map((r) => ({ ...describeReceipt(r, tz), version: r.version, isCurrent: r.isCurrent, withdrawn: r.withdrawnAt !== null }))}
    />
  );

  if (!draft.data) {
    return (
      <main>
        {heading}
        <p>Bid reference: <strong>{bid.data.reference}</strong></p>
        <p>Bids are due {due}.{closed && " Bidding on this solicitation has closed."}</p>
        {rows.length === 0 ? <p>This bid has no submitted version.</p> : panel}
      </main>
    );
  }

  const bidDraft = toBidDraft(bid.data, draft.data, files.data ?? []);
  return (
    <main>
      {heading}
      {panel}
      <BidDraftForm
        bidId={bidDraft.bidId}
        reference={bidDraft.reference}
        version={bidDraft.version}
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
          files: bidDraft.files,
        }}
      />
    </main>
  );
}
