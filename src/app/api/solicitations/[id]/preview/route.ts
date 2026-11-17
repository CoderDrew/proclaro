import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@/lib/supabase/server";
import { loadDocContext, SolicitationNotFound } from "@/documents/loadDocContext";
import { renderBidFormHtml, renderRfbHtml } from "@/documents/renderHtml";
import { chromiumRenderer, renderPdf } from "@/documents/pdf";

export const runtime = "nodejs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Draft preview PDF. Access is decided by RLS on the caller's own client; an invisible row is a 404. */
export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const doc = request.nextUrl.searchParams.get("doc");
  if (doc !== "rfb" && doc !== "bid-form") {
    return NextResponse.json({ error: "doc must be rfb or bid-form" }, { status: 400 });
  }

  const supabase = await createServerClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  if (!UUID.test(id)) return NextResponse.json({ error: "Not found" }, { status: 404 });

  try {
    // Locks apply once the reviewer has sent the solicitation to check, so the preview shows the text that will be
    // published. A draft has no lock rows and gets the latest text (loadDocContext falls back per key).
    const ctx = await loadDocContext(supabase, id, { useLocks: true });
    // A preview is always a draft: no number or version on the page, whatever the row holds.
    const draftCtx = { ...ctx, number: null, version: null };
    const html = doc === "rfb" ? renderRfbHtml(draftCtx, { draft: true }) : renderBidFormHtml(draftCtx, { draft: true });
    const pdf = await renderPdf(html, chromiumRenderer());
    return new Response(Buffer.from(pdf), {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `inline; filename="draft-${doc}.pdf"`,
        "Cache-Control": "private, no-store",
      },
    });
  } catch (e) {
    if (e instanceof SolicitationNotFound) return NextResponse.json({ error: "Not found" }, { status: 404 });
    throw e;
  }
}
