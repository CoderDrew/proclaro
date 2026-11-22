import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/database.types";

/**
 * The addendum numbers the caller's own bid has acknowledged, for the "Addenda acknowledged" line (spec §5).
 * bid_acknowledgments has no API grant (0031): the bidder reads it only through my_bid_acknowledgments, which lists
 * every published addendum with acknowledged_at null when not acknowledged.
 */
export async function loadAcknowledgedAddenda(
  supabase: Pick<SupabaseClient<Database>, "rpc">,
  bidId: string,
): Promise<number[]> {
  const { data, error } = await supabase.rpc("my_bid_acknowledgments", { p_bid_id: bidId });
  if (error) throw error;
  return (data ?? [])
    .filter((r) => r.acknowledged_at !== null)
    .map((r) => r.addendum_number);
}
