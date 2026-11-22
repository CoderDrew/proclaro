"use client";

// One bid's advisory document check: run it (one server action per document), read each item's result with its page
// and excerpt, and confirm or override each item. Nothing here sets an outcome.
import { startTransition, useId, useState } from "react";
import { useRouter } from "next/navigation";
import { Button, Card, ConfirmAction, Field, Notice, StatusBadge } from "@/components/ui";
import { checkAiDocument, finishAiCheck, reviewAiCheckItem, startAiCheck } from "./actions";
import { groupItems, runLabel, summary, type CheckItemView, type CheckView } from "./view";
import type { DocumentKind } from "@/domain/aicheck/checklist";

export const ADVISORY = "Advisory only. The reviewer decides every outcome.";

export function DocumentCheckPanel(props: {
  solicitationId: string;
  bidId: string;
  reference: string;
  bidderName: string;
  enabled: boolean;
  check: CheckView;
  /** Signed links to the checked documents, by storage path. */
  links: Record<string, string>;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const hintId = useId();
  const { check } = props;
  const groups = groupItems(check.items);
  const capReason = check.runsLeft <= 0
    ? "This bid has used all its check runs."
    : check.callsLeftUser <= 0 || check.callsLeftTotal <= 0
      ? "Today's check limit has been reached." : null;

  type Doc = { kind: DocumentKind; path: string | null };
  /** A live run whose failed documents can be checked again before it is finished. */
  const [pending, setPending] = useState<{ runId: string; failed: Doc[] } | null>(null);

  /** Checks documents one at a time. Returns the ones whose model call failed, or a message that stops the run. */
  async function checkAll(runId: string, docs: Doc[]): Promise<{ failed: Doc[]; stop: string | null }> {
    const failed: Doc[] = [];
    for (const [i, doc] of docs.entries()) {
      setProgress(`Checking ${i + 1} of ${docs.length}…`);
      const r = await checkAiDocument({ runId, kind: doc.kind, path: doc.path });
      if (!r.ok) return { failed, stop: r.message };
      if (r.callFailed) failed.push(doc);
    }
    return { failed, stop: null };
  }

  async function settle(runId: string, result: { failed: Doc[]; stop: string | null }) {
    if (result.stop === null && result.failed.length > 0) {
      setPending({ runId, failed: result.failed });
      setError(`${result.failed.length} document${result.failed.length === 1 ? "" : "s"} could not be checked. Check them again, or finish the run.`);
    } else {
      setPending(null);
      await finishAiCheck(runId, result.stop ? "failed" : "done");
      if (result.stop) setError(result.stop);
      else setDone("The check finished.");
    }
    startTransition(() => router.refresh());
  }

  async function guard(work: () => Promise<void>) {
    setBusy(true);
    setError(null);
    setDone(null);
    try {
      await work();
    } catch {
      setError("Something went wrong. Reload the page and try again.");
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  const run = () => guard(async () => {
    const started = await startAiCheck(props.bidId);
    if (!started.ok) { setError(started.message); return; }
    await settle(started.runId, await checkAll(started.runId, started.documents));
  });

  const retry = () => guard(async () => {
    if (!pending) return;
    await settle(pending.runId, await checkAll(pending.runId, pending.failed));
  });

  const finish = () => guard(async () => {
    if (!pending) return;
    await settle(pending.runId, { failed: [], stop: null });
  });

  return (
    <Card as="section" title={`Document check: ${props.reference} · ${props.bidderName}`}
      data-testid={`aicheck-${props.reference}`}>
      <p className="muted">{ADVISORY}</p>
      <p>
        <strong>{runLabel(check.run)}</strong>
        {check.items.length > 0 && <> · {summary(check.items)}</>}
      </p>

      {props.enabled ? (
        <form onSubmit={(e) => { e.preventDefault(); void run(); }}>
          <p id={hintId} className="muted">
            {capReason ?? `Runs left for this bid: ${check.runsLeft}. Document checks left today: ${Math.min(check.callsLeftUser, check.callsLeftTotal)}.`}
          </p>
          <ConfirmAction label="Run check" confirmLabel={`Confirm: run the AI check on ${props.reference}`}
            warning="This sends the bid's documents to the AI service and counts against today's limit."
            busy={busy} busyLabel={progress ?? "Checking…"} disabled={busy || capReason !== null || pending !== null}
            describedBy={hintId} />
        </form>
      ) : (
        <Notice tone="info">Document checks are turned off.</Notice>
      )}
      {pending && (
        <span className="ui-inline-actions">
          <Button type="button" disabled={busy} onClick={() => void retry()}>Check failed documents again</Button>
          <Button type="button" variant="secondary" disabled={busy} onClick={() => void finish()}>Finish this run</Button>
        </span>
      )}
      <div role="status" aria-live="polite">{progress ?? done}</div>
      {error && <Notice tone="error" role="alert">{error}</Notice>}

      {groups.map((g) => (
        <section key={g.kind} aria-label={g.label}>
          <h3>
            {g.label}{" "}
            {g.path && props.links[g.path] && <a href={props.links[g.path]} target="_blank" rel="noreferrer">Open</a>}
          </h3>
          <ul className="ui-aicheck-items">
            {g.items.map((item) => (
              <CheckItemRow key={item.id} item={item} link={g.path ? props.links[g.path] : undefined}
                reference={props.reference} />
            ))}
          </ul>
        </section>
      ))}
    </Card>
  );
}

function CheckItemRow(props: { item: CheckItemView; link?: string; reference: string }) {
  const router = useRouter();
  const { item } = props;
  const [overriding, setOverriding] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const name = `${item.label} (${props.reference})`;

  async function review(decision: "confirm" | "override") {
    setBusy(true);
    setError(null);
    const r = await reviewAiCheckItem(item.id, decision, reason);
    setBusy(false);
    if (!r.ok) { setError(r.message); return; }
    setOverriding(false);
    setReason("");
    startTransition(() => router.refresh());
  }

  return (
    <li data-testid={`item-${item.code}`}>
      <StatusBadge status={{ kind: "aiCheck", result: item.result }} />{" "}
      <strong>{item.label}</strong>{" "}
      <span className="muted">{item.method === "ai" ? "AI" : "Rule"}</span>
      {item.page !== null && (
        <> · {props.link ? <a href={`${props.link}#page=${item.page}`} target="_blank" rel="noreferrer">page {item.page}</a>
          : <>page {item.page}</>}</>
      )}
      {item.excerpt && <blockquote>{item.excerpt}</blockquote>}
      {item.extracted && item.method === "rule" && <div className="muted">Read as: {item.extracted}</div>}
      {item.detail && <div>{item.detail}</div>}
      {item.review && (
        <div className="muted">
          {item.review.decision === "confirm" ? "Confirmed" : `Overridden: ${item.review.reason ?? ""}`}
          {item.review.reviewedBy ? ` by ${item.review.reviewedBy}` : ""}
        </div>
      )}
      {!overriding && (
        <span className="ui-inline-actions">
          <Button type="button" variant="secondary" disabled={busy} aria-label={`Confirm: ${name}`}
            onClick={() => void review("confirm")}>Confirm</Button>
          <Button type="button" variant="secondary" disabled={busy} aria-label={`Override: ${name}`}
            onClick={() => setOverriding(true)}>Override</Button>
        </span>
      )}
      {overriding && (
        <form onSubmit={(e) => { e.preventDefault(); void review("override"); }}>
          <Field label={`Reason for overriding ${item.label}`}>
            <input value={reason} onChange={(e) => setReason(e.target.value)} required />
          </Field>
          <span className="ui-inline-actions">
            <Button type="submit" disabled={busy || reason.trim() === ""}>Save override</Button>
            <Button type="button" variant="secondary" disabled={busy} onClick={() => setOverriding(false)}>Cancel</Button>
          </span>
        </form>
      )}
      {error && <Notice tone="error" role="alert">{error}</Notice>}
    </li>
  );
}
