import Link from "next/link";
import { notFound } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { formatDate, formatDateTime, formatTimeWithZone } from "@/documents/format";
import { parseStoredData } from "@/domain/solicitation/schema";
import { todayIn } from "@/domain/time";
import { parseAward, parseRecap, memoText } from "@/domain/recap/snapshot";
import { RecapTable } from "@/components/RecapTable";
import { Card, DateTime, Money, Page, PageHeader, StatusBadge, Table, Td, Th } from "@/components/ui";
import { bidStatus, formatInstant, onlyPublic } from "../status";
import { addendumHeading, groupAnswers, versionLabel } from "../qa";

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
      .select("id, number, data, agency_id, bid_due_at, release_date, rfb_path, bid_form_path, published_snapshot"),
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

  // Every published version (old ones stay viewable) and the published answers; neither carries any identity.
  const [versionsRes, answersRes] = await Promise.all([
    supabase.rpc("solicitation_version_list", { p_solicitation_id: row.id }),
    supabase.rpc("published_answers", { p_solicitation_id: row.id }),
  ]);
  if (versionsRes.error) throw new Error(versionsRes.error.message);
  if (answersRes.error) throw new Error(answersRes.error.message);
  const versions = await Promise.all([...versionsRes.data].sort((a, b) => b.version - a.version).map(async (v) => ({
    version: v.version,
    current: v.is_current,
    publishedAt: v.published_at,
    rfb: v.rfb_path ? await link(v.rfb_path, `RFB-${number}-v${v.version}.pdf`) : null,
    bidForm: v.bid_form_path ? await link(v.bid_form_path, `Bid-Form-${number}-v${v.version}.pdf`) : null,
    addendum: v.addendum_path ? await link(v.addendum_path, `Addendum-${number}-${v.version - 1}.pdf`) : null,
  })));
  const answerGroups = groupAnswers(answersRes.data);

  // The posted recap or memo and the award are the only public disclosure of bids. Only kind, snapshot and posted_at are
  // read (the rows also carry user ids), and nothing about bids is read before posting.
  const [recapRes, awardRes] = await Promise.all([
    supabase.from("recaps").select("kind, snapshot, posted_at").eq("solicitation_id", row.id).maybeSingle(),
    supabase.from("awards").select("snapshot, posted_at").eq("solicitation_id", row.id).maybeSingle(),
  ]);
  if (recapRes.error) throw new Error(recapRes.error.message);
  if (awardRes.error) throw new Error(awardRes.error.message);
  const recap = recapRes.data ? parseRecap(recapRes.data.snapshot) : null;
  const award = awardRes.data ? parseAward(awardRes.data.snapshot) : null;

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
        actions={(
          <>
            <StatusBadge status={{ kind: "bidding", status }} />
            {award ? <StatusBadge status={{ kind: "evaluation", stage: "awarded", awaitingAgency: false }} /> : null}
          </>
        )}
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

      {versions.length > 1 ? (
        <Card title="Versions" data-testid="public-versions">
          <ul>
            {versions.map((v) => (
              <li key={v.version}>
                <strong>{versionLabel(v.version, v.current)}</strong>, published <DateTime iso={v.publishedAt} tz={tz} />:{" "}
                {v.rfb ? <a href={v.rfb}>Request for Bids (PDF)</a> : "Request for Bids (unavailable)"}
                {", "}
                {v.bidForm ? <a href={v.bidForm}>Bid form (PDF)</a> : "Bid form (unavailable)"}
                {v.version > 1 ? (
                  <>{", "}{v.addendum ? <a href={v.addendum}>{addendumHeading(v.version - 1)} (PDF)</a> : `${addendumHeading(v.version - 1)} (unavailable)`}</>
                ) : null}
              </li>
            ))}
          </ul>
        </Card>
      ) : null}

      {answerGroups.length > 0 ? (
        <Card title="Questions and answers" data-testid="public-qa">
          {answerGroups.map((g) => (
            <section key={g.addendum} aria-labelledby={`qa-addendum-${g.addendum}`}>
              <h3 id={`qa-addendum-${g.addendum}`}>{addendumHeading(g.addendum)}</h3>
              <dl>
                {g.items.map((it, i) => (
                  <div key={i}>
                    <dt>Question: {it.question}</dt>
                    <dd>Answer: {it.answer}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ))}
        </Card>
      ) : null}

      {recap && recapRes.data && recap.kind === "recap" ? (
        <Card title="Bid recap" data-testid="public-recap">
          <RecapTable recap={recap} />
          <p>Posted <DateTime iso={recapRes.data.posted_at} tz={tz} />.</p>
        </Card>
      ) : null}

      {recap && recapRes.data && recap.kind === "all_rejected" ? (
        <Card title="All bids rejected" data-testid="public-memo">
          <p>{memoText(recap)}</p>
          <p>Posted <DateTime iso={recapRes.data.posted_at} tz={tz} />.</p>
        </Card>
      ) : null}

      {award && awardRes.data ? (
        <Card title="Award" data-testid="public-award">
          <p><strong>{award.bidderName}</strong> for <Money cents={award.amountCents} />.</p>
          {award.selectedAlternates.length === 0 ? (
            <p>Base bid only.</p>
          ) : (
            <ul>
              {award.selectedAlternates.map((n) => (
                <li key={n}>Alternate {n}: {award.alternates[n - 1]?.description ?? "Description unavailable"}</li>
              ))}
            </ul>
          )}
          <p>Posted <DateTime iso={awardRes.data.posted_at} tz={tz} />.</p>
        </Card>
      ) : null}
    </Page>
  );
}
