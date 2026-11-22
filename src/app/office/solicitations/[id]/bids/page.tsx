import { notFound } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { formatInstant } from "@/app/solicitations/status";
import { requireOfficePage } from "../../../guard";
import { UPLOAD_SLOT_LABELS } from "@/domain/bid/types";
import type { SolicitationData } from "@/domain/solicitation/types";
import { ITEM_LABELS, type OriginalItem } from "./logic";
import { OriginalsPanel, type EntryView } from "./OriginalsPanel";
import { ButtonLink, Card, Money, Notice, Page, PageHeader, StatusBadge, Table, Td, Th, EmptyState } from "@/components/ui";
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
    <PageHeader
      crumbs={<><a href="/office">Office queues</a> · <a href={`/office/solicitations/${id}`}>{sol.number ?? "Solicitation"}</a></>}
      title={`Bids: ${title}`}
    />
  );

  if (ctx.orgKind !== "office") {
    return <Page width="full">{header}<Notice tone="info">Only office staff can view bids and log originals.</Notice></Page>;
  }
  if (sol.state !== "published" || !sol.bid_due_at) {
    return <Page width="full">{header}<Notice tone="info">This solicitation is not published, so it has no bids.</Notice></Page>;
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
    <Page width="full">
      {header}
      <p>Bid due: {formatInstant(sol.bid_due_at, tz)}. A signed original counts only if it was received and logged by then.</p>
      {opening}
      <OriginalsPanel
        solicitationId={id}
        index={index.data!.map((r) => ({ reference: r.reference, version: r.version, status: r.status }))}
        entries={entries}
        canWork={ctx.orgKind === "office"}
      />
    </Page>
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
      return <Notice tone="warning" data-testid="sealed"><strong>Bids are sealed until {dueLocal}.</strong></Notice>;
    }
    throw new Error(opened.error.message);
  }
  const [files, review, stale] = await Promise.all([
    supabase.rpc("opened_bid_files", { p_solicitation_id: id }),
    // Only for each bid's bond cure status, so the bond label does not contradict a cure made after close.
    supabase.rpc("review_bids", { p_solicitation_id: id }),
    // Bids priced against an older schedule are not counted; no prices are shown here.
    supabase.rpc("stale_bids", { p_solicitation_id: id }),
  ]);
  if (stale.error) throw new Error(stale.error.message);
  if (files.error) throw new Error(files.error.message);
  if (review.error) throw new Error(review.error.message);
  const cures = Object.fromEntries(review.data.map((r) => [r.bid_id, r.cure_status]));

  const sd = ((snapshot as { data?: SolicitationData } | null)?.data ?? data) as SolicitationData;
  const items = sd.schedule?.items ?? [];
  const alternates = sd.schedule?.alternates ?? [];
  const bids = opened.data as OpenedBid[];
  const fileRows = files.data as OpenedFile[];
  const tab = toTabulation(bids, alternates, fileRows, cures);

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
      <div className="ui-inline-actions">
        <ButtonLink variant="primary" href={`/office/solicitations/${id}/review`} data-testid="review-link">
          Review bids
        </ButtonLink>
      </div>
      {stale.data.length > 0 ? (
        <Card as="section" title="Not counted: resubmit required" data-testid="stale-bids">
          <p className="muted ui-office-note">
            These bids were priced against an earlier bid schedule and are not opened or counted.
          </p>
          <Table>
            <thead><tr><Th>Reference</Th><Th>Bidder</Th><Th>Priced against version</Th></tr></thead>
            <tbody>
              {stale.data.map((b) => (
                <tr key={b.bid_id} data-testid={`stale-${b.reference}`}>
                  <Td>{b.reference}</Td><Td>{b.bidder_legal_name}</Td><Td>{b.solicitation_version}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        </Card>
      ) : null}
      <Card as="section" title="Tabulation (internal)">
        <p className="muted ui-office-note">
          Computed from the submitted prices. Ordered by base total. Not for posting.
        </p>
        {tab.rows.length === 0 ? (
          <EmptyState>No bids were opened.</EmptyState>
        ) : (
          <Table data-testid="tabulation">
            <thead>
              <tr>
                <Th>Bidder</Th><Th>Reference</Th><Th>Version</Th><Th numeric>Base total</Th>
                {tab.headers.map((h) => <Th key={h} numeric>{h}</Th>)}
                <Th>Signed original</Th><Th>Bid bond</Th><Th>Files</Th>
              </tr>
            </thead>
            <tbody>
              {tab.rows.map((r) => (
                  <tr key={r.bidId} data-testid={`tab-${r.reference}`} className={r.reason ? "is-danger" : undefined}>
                    <Td>{r.bidderName}</Td>
                    <Td>{r.reference}</Td>
                    <Td>{r.version}</Td>
                    <Td numeric>{r.baseTotal}</Td>
                    {r.alternates.map((a, i) => <Td key={i} numeric>{a}</Td>)}
                    <Td>
                      <StatusBadge status={{ kind: "original", received: !r.reason }} />
                      {r.reason ? <>: {r.reason}</> : null}
                    </Td>
                    <Td>{r.bond}</Td>
                    <Td>
                      <StatusBadge status={{ kind: "files", flags: r.fileFlags }} role={r.fileFlags.length ? "alert" : undefined} />
                    </Td>
                  </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>

      {bids.map((b) => (
        <Card as="section" key={b.bid_id} data-testid={`opened-${b.reference}`}
          title={`${b.bidder_name}: bid ${b.reference}, version ${b.version}`}>
          <Table>
            <thead><tr><Th>Line</Th><Th>Description</Th><Th numeric>Price</Th></tr></thead>
            <tbody>
              {b.item_cents.map((c, i) => (
                <tr key={`i${i}`}>
                  <Td>{items[i]?.name ?? `Item ${i + 1}`}</Td><Td>{items[i]?.description ?? ""}</Td>
                  <Td numeric><Money cents={c} /></Td>
                </tr>
              ))}
              <tr><Td colSpan={2}><strong>Base total</strong></Td><Td numeric><strong><Money cents={b.base_total_cents} /></strong></Td></tr>
              {b.alternate_cents.map((c, i) => (
                <tr key={`a${i}`}>
                  <Td>{tab.headers[i] ?? `Alternate ${i + 1}`}</Td><Td>{alternates[i]?.description ?? ""}</Td>
                  <Td numeric><Money cents={c} /></Td>
                </tr>
              ))}
            </tbody>
          </Table>
          <ul className="ui-plain-list">
            {fileRows.filter((f) => f.bid_id === b.bid_id).map((f) => (
              <li key={f.path}>
                {UPLOAD_SLOT_LABELS[f.slot] ?? f.slot}:{" "}
                {links.has(f.path) ? <a href={links.get(f.path)}>{f.file_name}</a> : f.file_name}
                {f.file_status !== "ok" && <> <StatusBadge status={{ kind: "file", status: f.file_status }} /></>}
              </li>
            ))}
          </ul>
        </Card>
      ))}
    </>
  );
}
