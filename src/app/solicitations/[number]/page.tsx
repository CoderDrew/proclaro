import Link from "next/link";
import { notFound } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { formatDate, formatDateTime, formatTimeWithZone } from "@/documents/format";
import { parseStoredData } from "@/domain/solicitation/schema";
import { todayIn } from "@/domain/time";
import { Card, Page, PageHeader, StatusBadge, Table, Td, Th } from "@/components/ui";
import { bidStatus, formatInstant, onlyPublic } from "../status";

export const dynamic = "force-dynamic";

const NUMBER = /^\d{2}-\d{4}$/;
const LINK_SECONDS = 300;

/**
 * Public detail page: published and released only, whoever is signed in (a 404 otherwise). RLS hides the rest from
 * anon; office staff can read every row, so the release filter is applied here too.
 */
export default async function SolicitationPage({ params }: { params: Promise<{ number: string }> }) {
  const { number } = await params;
  if (!NUMBER.test(number)) notFound();

  const supabase = await createServerClient();
  const settings = await supabase.from("settings").select("timezone").eq("id", 1).single();
  if (settings.error) throw new Error(settings.error.message);
  const tz = settings.data.timezone;

  const { data: row, error } = await onlyPublic(
    supabase.from("solicitations")
      .select("number, data, agency_id, bid_due_at, release_date, rfb_path, bid_form_path, published_snapshot"),
    todayIn(tz, new Date()),
  )
    .eq("number", number)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!row || !row.rfb_path || !row.bid_form_path) notFound();

  const org = await supabase.from("organizations").select("name").eq("id", row.agency_id).single();
  if (org.error) throw new Error(org.error.message);

  const data = parseStoredData(row.data);
  if (data === null) notFound();
  // The snapshot records where publish copied each attachment; the closed attachments bucket is never used here.
  const snap = (row.published_snapshot ?? {}) as { data?: { attachments?: { label: string; storagePath: string }[] } };
  const attachments = snap.data?.attachments ?? [];

  // Short-lived signed URLs, created with the caller's own client (anon may read released files).
  async function link(path: string, filename: string): Promise<string | null> {
    const { data: signed } = await supabase.storage.from("published").createSignedUrl(path, LINK_SECONDS, { download: filename });
    return signed?.signedUrl ?? null;
  }
  const rfbUrl = await link(row.rfb_path, `RFB-${number}.pdf`);
  const bidFormUrl = await link(row.bid_form_path, `Bid-Form-${number}.pdf`);
  const attachmentLinks = await Promise.all(attachments.map(async (a) => ({
    label: a.label,
    url: await link(a.storagePath, a.storagePath.split("/").pop() ?? "attachment"),
  })));

  const status = bidStatus(row.bid_due_at, new Date());
  const dates: [string, string][] = [
    ["Release date", formatDate(data.releaseDate)],
    ["Questions due", formatDateTime(data.questionsDue, tz)],
    ["Answers and addenda due", formatDateTime(data.answersDue, tz)],
    ["Bid due", row.bid_due_at ? formatInstant(row.bid_due_at, tz) : "To be determined"],
  ];
  if (data.preBid.kind !== "none" && data.preBid.date && data.preBid.time) {
    dates.push([
      `Pre-bid meeting (${data.preBid.kind})`,
      `${formatDate(data.preBid.date)}, ${formatTimeWithZone(data.preBid.date, data.preBid.time, tz)}`,
    ]);
  }

  return (
    <Page width="full">
      <PageHeader
        crumbs={<Link href="/solicitations">All solicitations</Link>}
        eyebrow={`${number} · ${org.data.name}`}
        title={data.longTitle}
        actions={<StatusBadge status={{ kind: "bidding", status }} />}
      />

      <Card title="Summary">
        <p>{data.summary}</p>
        <p>{data.location.address}, {data.location.city}, {data.location.county}</p>
      </Card>

      <Card title="Key dates">
        <Table>
          <tbody>
            {dates.map(([k, v]) => <tr key={k}><Th scope="row">{k}</Th><Td>{v}</Td></tr>)}
          </tbody>
        </Table>
      </Card>

      <Card title="Documents">
        <ul>
          <li>{rfbUrl ? <a href={rfbUrl}>Request for Bids (PDF)</a> : "Request for Bids (unavailable)"}</li>
          <li>{bidFormUrl ? <a href={bidFormUrl}>Bid form (PDF)</a> : "Bid form (unavailable)"}</li>
          {attachmentLinks.map((a, i) => (
            <li key={i}>{a.url ? <a href={a.url}>{a.label}</a> : `${a.label} (unavailable)`}</li>
          ))}
        </ul>
      </Card>
    </Page>
  );
}
