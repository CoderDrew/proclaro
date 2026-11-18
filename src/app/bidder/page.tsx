import Link from "next/link";
import { todayIn } from "@/domain/time";
import { createServerClient } from "@/lib/supabase/server";
import { formatInstant, onlyPublic } from "@/app/solicitations/status";
import { signOut } from "@/app/login/actions";
import { requireBidderPage } from "./guard";
import { describeReceipt, toReceipts } from "./solicitations/[id]/logic";

export const dynamic = "force-dynamic";

export default async function BidderHome() {
  const ctx = await requireBidderPage();
  const supabase = await createServerClient();
  const settings = await supabase.from("settings").select("timezone").eq("id", 1).single();
  if (settings.error) throw new Error(settings.error.message);
  const tz = settings.data.timezone;
  const now = new Date();
  const rows = await onlyPublic(
    supabase.from("solicitations").select("id, number, data, bid_due_at"),
    todayIn(tz, now),
  )
    .gt("bid_due_at", now.toISOString())
    .order("bid_due_at", { ascending: true });
  if (rows.error) throw new Error(rows.error.message);

  // My bids: RLS limits `bids` to the caller's organization. Receipts show time, reference and version only.
  const myBids = await supabase.from("bids").select("id, reference, solicitation_id").order("created_at", { ascending: false });
  if (myBids.error) throw new Error(myBids.error.message);
  const mine = await Promise.all((myBids.data ?? []).map(async (b) => {
    const [sol, rec] = await Promise.all([
      supabase.from("solicitations").select("number, data").eq("id", b.solicitation_id).maybeSingle(),
      supabase.rpc("my_bid_receipts", { p_bid_id: b.id }),
    ]);
    if (sol.error) throw new Error(sol.error.message);
    if (rec.error) throw new Error(rec.error.message);
    const receipts = toReceipts(rec.data ?? []);
    const latest = receipts.length ? receipts[receipts.length - 1] : null;
    return { bid: b, number: sol.data?.number ?? "", title: (sol.data?.data as { longTitle?: string } | null)?.longTitle || "(untitled)",
      latest: latest ? describeReceipt(latest, tz) : null };
  }));

  return (
    <main>
      <h1>Open solicitations</h1>
      <p>Signed in as {ctx.displayName}.</p>
      {rows.data.length === 0 ? (
        <p>No solicitations are open for bidding right now.</p>
      ) : (
        <table className="list">
          <thead>
            <tr><th>Number</th><th>Title</th><th>Bid due</th><th>Bid</th></tr>
          </thead>
          <tbody>
            {rows.data.map((r) => {
              const title = (r.data as { longTitle?: string } | null)?.longTitle || "(untitled)";
              return (
                <tr key={r.id}>
                  <td>{r.number}</td>
                  <td>{title}</td>
                  <td>{r.bid_due_at ? formatInstant(r.bid_due_at, tz) : "-"}</td>
                  <td><Link href={`/bidder/solicitations/${r.id}`}>Prepare a bid</Link></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
      <h2>My bids</h2>
      {mine.length === 0 ? (
        <p>You have not started a bid.</p>
      ) : (
        <table className="list" data-testid="my-bids">
          <thead><tr><th>Solicitation</th><th>Reference</th><th>Latest receipt</th></tr></thead>
          <tbody>
            {mine.map((m) => (
              <tr key={m.bid.id}>
                <td><Link href={`/bidder/solicitations/${m.bid.solicitation_id}`}>{m.number}: {m.title}</Link></td>
                <td>{m.bid.reference}</td>
                <td>{m.latest ? `${m.latest.line} (${m.latest.status})` : "Draft, not yet submitted"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <form action={signOut} style={{ marginTop: 16 }}>
        <button type="submit">Sign out</button>
      </form>
    </main>
  );
}
