import type { NextRequest } from "next/server";
import { createServerClient } from "@/lib/supabase/server";
import { blankFormResponse } from "@/documents/blankForm";
import { loadPublishedDocContext } from "@/documents/loadPublishedDocContext";
import { chromiumRenderer, renderPdf } from "@/documents/pdf";
import { renderBidFormHtml } from "@/documents/renderHtml";

export const runtime = "nodejs";

/** The blank (unfilled) bid form of a published solicitation. See blankFormResponse for the access rules. */
export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return blankFormResponse(
    {
      supabase: await createServerClient(),
      now: new Date(),
      loadContext: loadPublishedDocContext,
      renderPdf: (ctx) => renderPdf(renderBidFormHtml(ctx, { draft: false }), chromiumRenderer()),
    },
    id,
  );
}
