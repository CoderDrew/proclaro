import { notFound } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { formatInstant } from "@/app/solicitations/status";
import { requireOfficePage } from "../../../guard";
import { formatMoney } from "@/domain/money";
import { UPLOAD_SLOT_LABELS } from "@/domain/bid/types";
import type { SolicitationData } from "@/domain/solicitation/types";
import { ITEM_LABELS, type OriginalItem } from "./logic";
import { OriginalsPanel, type EntryView } from "./OriginalsPanel";
import { toTabulation, type OpenedBid, type OpenedFile } from "./tabulation";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LINK_SECONDS = 300;

/**
 * Before close the office sees only what office_bid_index returns (reference, version, status) plus its own log.
 * After close (the database decides: opened_bids raises `sealed` until now() >= bid_due_at) it also sees the
 * tabulation, each bid's full submitted prices and its files. There is no open button.
 */
export default async function OfficeBidsPage({ params }: { params: Promise<{ id: string }> }) {
  const ctx = await requireOfficePage();
  const { id } = await params;
  if (!UUID.test(id)) notFound();

  const supabase = await createServerClient();
  const { data: sol, error } = await supabase
    .from("solicitations")
    .select("id, number, state, data, bid_due_at, published_snapshot")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!sol) notFound();
  const title = (sol.data as { shortTitle?: string } | null)?.shortTitle || "(untitled)";

  const header = (
    <>
      <p style={{ margin: "0 0 8px" }}>
        <a href="/office">Office queues</a> · <a href={`/office/solicitations/${id}`}>{sol.number ?? "Solicitation"}</a>
      </p>
      <h1>Bids: {title}</h1>
    </>
  );

  if (ctx.orgKind !== "office") {
    return <main>{header}<p>Only office staff can view bids and log originals.</p></main>;
  }
  if (sol.state !== "published" || !sol.bid_due_at) {
    return <main>{header}<p>This solicitation is not published, so it has no bids.</p></main>;
  }

  const [settings, index, log, officeOrgs] = await Promise.all([
    supabase.from("settings").select("timezone").eq("id", 1).single(),
    supabase.rpc("office_bid_index", { p_solicitation_id: id }),
    supabase.from("bid_original_log")
      .select("id, reference, version, item, received_at, voids_entry_id, reason, logged_by, logged_at")
      .eq("solicitation_id", id)
      .order("logged_at", { ascending: false })
      .order("id", { ascending: false }),
    supabase.from("organizations").select("id").eq("kind", "office"),
  ]);
  for (const r of [settings, index, log, officeOrgs]) if (r.error) throw new Error(r.error.message);
  const staff = await supabase.from("profiles").select("user_id, display_name")
    .in("org_id", officeOrgs.data!.map((o) => o.id));
  if (staff.error) throw new Error(staff.error.message);
  const names = new Map(staff.data.map((p) => [p.user_id, p.display_name]));

  const tz = settings.data!.timezone;
  const opening = await openingSection(supabase, id, sol.published_snapshot, sol.data, formatInstant(sol.bid_due_at, tz));
  const due = new Date(sol.bid_due_at).getTime();
  const voidOf = new Map(log.data!.filter((e) => e.voids_entry_id).map((e) => [e.voids_entry_id!, e.reason ?? ""]));
  const entries: EntryView[] = log.data!.map((e) => ({
    id: e.id,
    logged: formatInstant(e.logged_at, tz),
    by: names.get(e.logged_by) ?? "Office staff",
    reference: e.reference,
    version: e.version,
    item: ITEM_LABELS[e.item as OriginalItem] ?? e.item,
    received: e.received_at ? formatInstant(e.received_at, tz) : null,
    voidsEntryId: e.voids_entry_id,
    reason: e.reason,
    voidedReason: voidOf.get(e.id) ?? null,
    afterDue: e.received_at !== null
      && (new Date(e.logged_at).getTime() > due || new Date(e.received_at).getTime() > due),
  }));

  return (
    <main>
      {header}
      <p>Bid due: {formatInstant(sol.bid_due_at, tz)}. A signed original counts only if it was received and logged by then.</p>
      {opening}
      <OriginalsPanel
        solicitationId={id}
        index={index.data!.map((r) => ({ reference: r.reference, version: r.version, status: r.status }))}
        entries={entries}
        canWork={ctx.orgKind === "office"}
      />
    </main>
  );
}

type ServerClient = Awaited<ReturnType<typeof createServerClient>>;

/** The sealed notice, or (after close) the tabulation, submitted prices and files. */
async function openingSection(
  supabase: ServerClient, id: string, snapshot: unknown, data: unknown, dueLocal: string,
) {
  const opened = await supabase.rpc("opened_bids", { p_solicitation_id: id });
  if (opened.error) {
    if (opened.error.message === "sealed") {
      return <p data-testid="sealed"><strong>Bids are sealed until {dueLocal}.</strong></p>;
    }
    throw new Error(opened.error.message);
  }
  const files = await supabase.rpc("opened_bid_files", { p_solicitation_id: id });
  if (files.error) throw new Error(files.error.message);

  const sd = ((snapshot as { data?: SolicitationData } | null)?.data ?? data) as SolicitationData;
  const items = sd.schedule?.items ?? [];
  const alternates = sd.schedule?.alternates ?? [];
  const bids = opened.data as OpenedBid[];
  const fileRows = files.data as OpenedFile[];
  const tab = toTabulation(bids, alternates, fileRows);

  // Signed links from the office user's own client: storage RLS allows only opened files.
  const present = fileRows.filter((f) => f.file_status !== "missing").map((f) => f.path);
  const links = new Map<string, string>();
  if (present.length > 0) {
    const signed = await supabase.storage.from("bid-files").createSignedUrls(present, LINK_SECONDS);
    if (signed.error) throw new Error(signed.error.message);
    for (const s of signed.data) if (s.path && s.signedUrl) links.set(s.path, s.signedUrl);
  }

  return (
    <>
      <section>
        <h2>Tabulation (internal)</h2>
        <p style={{ margin: "0 0 6px", fontSize: 13 }}>
          Computed from the submitted prices. Ordered by base total. Not for posting.
        </p>
        {tab.rows.length === 0 ? (
          <p>No bids were opened.</p>
        ) : (
          <table className="list" data-testid="tabulation">
            <thead>
              <tr>
                <th>Bidder</th><th>Reference</th><th>Version</th><th>Base total</th>
                {tab.headers.map((h) => <th key={h}>{h}</th>)}
                <th>Signed original</th><th>Bid bond</th><th>Files</th>
              </tr>
            </thead>
            <tbody>
              {tab.rows.map((r) => (
                <tr key={r.bidId} data-testid={`tab-${r.reference}`} style={r.reason ? { background: "#fdecea" } : undefined}>
                  <td>{r.bidderName}</td>
                  <td>{r.reference}</td>
                  <td>{r.version}</td>
                  <td style={{ textAlign: "right" }}>{r.baseTotal}</td>
                  {r.alternates.map((a, i) => <td key={i} style={{ textAlign: "right" }}>{a}</td>)}
                  <td>
                    {r.reason ? <><strong>Non-responsive</strong>: {r.reason}</> : "Received"}
                  </td>
                  <td>{r.bond}</td>
                  <td>
                    {r.fileFlags.length === 0 ? "Unaltered" : (
                      <strong role="alert">{r.fileFlags.join("; ")}</strong>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      {bids.map((b) => (
        <section key={b.bid_id} data-testid={`opened-${b.reference}`}>
          <h3>{b.bidder_name}: bid {b.reference}, version {b.version}</h3>
          <table className="list">
            <thead><tr><th>Line</th><th>Description</th><th>Price</th></tr></thead>
            <tbody>
              {b.item_cents.map((c, i) => (
                <tr key={`i${i}`}>
                  <td>{items[i]?.name ?? `Item ${i + 1}`}</td><td>{items[i]?.description ?? ""}</td>
                  <td style={{ textAlign: "right" }}>{formatMoney(c)}</td>
                </tr>
              ))}
              <tr><td colSpan={2}><strong>Base total</strong></td><td style={{ textAlign: "right" }}><strong>{formatMoney(b.base_total_cents)}</strong></td></tr>
              {b.alternate_cents.map((c, i) => (
                <tr key={`a${i}`}>
                  <td>{tab.headers[i] ?? `Alternate ${i + 1}`}</td><td>{alternates[i]?.description ?? ""}</td>
                  <td style={{ textAlign: "right" }}>{formatMoney(c)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <ul>
            {fileRows.filter((f) => f.bid_id === b.bid_id).map((f) => (
              <li key={f.path}>
                {UPLOAD_SLOT_LABELS[f.slot] ?? f.slot}:{" "}
                {links.has(f.path) ? <a href={links.get(f.path)}>{f.file_name}</a> : f.file_name}
                {f.file_status !== "ok" && <strong> ({f.file_status} since submission)</strong>}
              </li>
            ))}
          </ul>
        </section>
      ))}
    </>
  );
}
