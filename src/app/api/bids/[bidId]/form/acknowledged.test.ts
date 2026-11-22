import { describe, expect, it, vi } from "vitest";
import { loadAcknowledgedAddenda } from "./acknowledged";

const BID = "44444444-4444-4444-8444-444444444444";

function client(result: { data: unknown; error: unknown }) {
  const rpc = vi.fn(async () => result);
  return { supabase: { rpc } as unknown as Parameters<typeof loadAcknowledgedAddenda>[0], rpc };
}

describe("loadAcknowledgedAddenda", () => {
  it("reads through my_bid_acknowledgments (bid_acknowledgments has no API grant) and keeps acknowledged rows", async () => {
    const { supabase, rpc } = client({
      data: [
        { addendum_number: 1, published_at: "2026-08-10T18:00:00Z", acknowledged_at: "2026-08-11T18:00:00Z" },
        { addendum_number: 2, published_at: "2026-08-15T18:00:00Z", acknowledged_at: null },
        { addendum_number: 3, published_at: "2026-08-18T18:00:00Z", acknowledged_at: "2026-08-19T18:00:00Z" },
      ],
      error: null,
    });
    expect(await loadAcknowledgedAddenda(supabase, BID)).toEqual([1, 3]);
    expect(rpc).toHaveBeenCalledWith("my_bid_acknowledgments", { p_bid_id: BID });
  });

  it("returns an empty list when the solicitation has no published addenda", async () => {
    const { supabase } = client({ data: [], error: null });
    expect(await loadAcknowledgedAddenda(supabase, BID)).toEqual([]);
  });

  it("throws the database error", async () => {
    const err = { message: "not_found" };
    const { supabase } = client({ data: null, error: err });
    await expect(loadAcknowledgedAddenda(supabase, BID)).rejects.toBe(err);
  });
});
