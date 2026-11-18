import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@/lib/supabase/server";
import { toBidFill } from "@/documents/bidFill";
import { SolicitationNotFound } from "@/documents/loadDocContext";
import { loadPublishedDocContext } from "@/documents/loadPublishedDocContext";
import { chromiumRenderer, renderPdf } from "@/documents/pdf";
import { renderBidFormHtml } from "@/documents/renderHtml";
import { toBidDraft } from "@/app/bidder/solicitations/[id]/logic";

export const runtime = "nodejs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const notFound = () => NextResponse.json({ error: "Not found" }, { status: 404, headers: { "Cache-Control": "private, no-store" } });

/**
 * The bidder's pre-filled bid form, generated from their own draft. Every read goes through the caller's own client,
 * so RLS decides what exists: another organization's bid, or a bid with no open draft, is a 404. Nothing is stored.
 */
export async function GET(_request: NextRequest, { params }: { params: Promise<{ bidId: string }> }) {
  const { bidId } = await params;
  const supabase = await createServerClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) {
    return NextResponse.json({ error: "Not signed in" }, { status: 401, headers: { "Cache-Control": "private, no-store" } });
  }
  if (!UUID.test(bidId)) return notFound();

  const bid = await supabase.from("bids").select("id, reference, solicitation_id, bidder_org_id").eq("id", bidId).maybeSingle();
  if (bid.error) throw bid.error;
  if (!bid.data) return notFound();

  const [draft, files, company, org] = await Promise.all([
    supabase.from("bid_drafts").select("version, item_cents, alternate_cents, bid_bond_choice").eq("bid_id", bid.data.id).maybeSingle(),
    supabase.from("bid_draft_files").select("slot, path, file_name").eq("bid_id", bid.data.id),
    supabase.from("bidder_companies").select("*").eq("org_id", bid.data.bidder_org_id).maybeSingle(),
    supabase.from("organizations").select("name").eq("id", bid.data.bidder_org_id).maybeSingle(),
  ]);
  for (const r of [draft, files, company, org]) if (r.error) throw r.error;
  if (!draft.data || !company.data || !org.data) return notFound();

  const fill = toBidFill(company.data, org.data.name, toBidDraft(bid.data, draft.data, files.data ?? []));
  if ("incomplete" in fill) {
    return NextResponse.json(
      { error: "Enter every price before printing the bid form." },
      { status: 409, headers: { "Cache-Control": "private, no-store" } },
    );
  }

  try {
    const ctx = await loadPublishedDocContext(supabase, bid.data.solicitation_id);
    if (fill.itemCents.length !== ctx.data.schedule.items.length || fill.alternateCents.length !== ctx.data.schedule.alternates.length) {
      return NextResponse.json(
        { error: "Enter every price before printing the bid form." },
        { status: 409, headers: { "Cache-Control": "private, no-store" } },
      );
    }
    const pdf = await renderPdf(renderBidFormHtml(ctx, { draft: false, fill }), chromiumRenderer());
    return new Response(Buffer.from(pdf), {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `inline; filename="bid-form-${fill.reference}-v${fill.bidVersion}.pdf"`,
        "Cache-Control": "private, no-store",
      },
    });
  } catch (e) {
    if (e instanceof SolicitationNotFound) return notFound();
    throw e;
  }
}
