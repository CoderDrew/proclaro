import Link from "next/link";
import { todayIn } from "@/domain/time";
import { createServerClient } from "@/lib/supabase/server";
import { formatInstant, onlyPublic } from "@/app/solicitations/status";
import { signOut } from "@/app/login/actions";
import { Button, Card, EmptyState, Page, PageHeader, StatusBadge, Table, Td, Th, receiptKey } from "@/components/ui";
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
      latest: latest ? { ...describeReceipt(latest, tz), key: receiptKey({ withdrawn: latest.withdrawnAt !== null, isCurrent: latest.isCurrent }) } : null };
  }));

  return (
    <Page width="full">
      <PageHeader title="Open solicitations" />
      <p className="muted">Signed in as {ctx.displayName}.</p>
      <Card>
        {rows.data.length === 0 ? (
          <EmptyState>No solicitations are open for bidding right now.</EmptyState>
        ) : (
          <Table>
            <thead>
              <tr><Th>Number</Th><Th>Title</Th><Th>Bid due</Th><Th>Bid</Th></tr>
            </thead>
            <tbody>
              {rows.data.map((r) => {
                const title = (r.data as { longTitle?: string } | null)?.longTitle || "(untitled)";
                return (
                  <tr key={r.id}>
                    <Td>{r.number}</Td>
                    <Td>{title}</Td>
                    <Td>{r.bid_due_at ? formatInstant(r.bid_due_at, tz) : "-"}</Td>
                    <Td><Link href={`/bidder/solicitations/${r.id}`} aria-label={`Prepare a bid for ${r.number} ${title}`}>Prepare a bid</Link></Td>
                  </tr>
                );
              })}
            </tbody>
          </Table>
        )}
      </Card>
      <Card title="My bids" titleId="my-bids">
        {mine.length === 0 ? (
          <EmptyState>You have not started a bid.</EmptyState>
        ) : (
          <Table data-testid="my-bids">
            <thead><tr><Th>Solicitation</Th><Th>Reference</Th><Th>Latest receipt</Th></tr></thead>
            <tbody>
              {mine.map((m) => (
                <tr key={m.bid.id}>
                  <Td><Link href={`/bidder/solicitations/${m.bid.solicitation_id}`}>{m.number}: {m.title}</Link></Td>
                  <Td>{m.bid.reference}</Td>
                  <Td>
                    {m.latest ? (
                      <>{m.latest.line} <StatusBadge status={{ kind: "bidVersion", status: m.latest.key }} label={m.latest.status} wrap /></>
                    ) : "Draft, not yet submitted"}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
      <form action={signOut} className="ui-signout">
        <Button type="submit">Sign out</Button>
      </form>
    </Page>
  );
}
