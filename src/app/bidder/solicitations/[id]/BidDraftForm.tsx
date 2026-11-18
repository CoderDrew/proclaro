"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { BidFileUploader, type UploadedBidFile } from "@/components/BidFileUploader";
import { formatMoney, parseMoney, type Cents } from "@/domain/money";
import { UPLOAD_SLOT_LABELS, type BidBondChoice, type BidDraft, type UploadSlot } from "@/domain/bid/types";
import { baseTotalCents, requiredUploadSlots, validateBidDraft, type BidRules } from "@/domain/bid/validate";
import { deriveRequirements } from "@/domain/solicitation/valueBands";
import {
  attachBidFile, createBidUploadUrl, removeBidFile, saveBidPrices, setBidBondChoice, startBid, submitBid,
} from "./actions";

const toInput = (c: Cents | null) => (c === null ? "" : formatMoney(c).slice(1));

/** Starts the bid, then reloads the page so the server renders the new draft. */
export function StartBidButton({ solicitationId }: { solicitationId: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function start() {
    setBusy(true);
    setError(null);
    const r = await startBid(solicitationId);
    setBusy(false);
    if (!r.ok) setError(r.message);
    else router.refresh();
  }
  return (
    <div>
      <button type="button" disabled={busy} onClick={() => void start()}>Start a bid</button>
      {error && <p role="alert" className="error">{error}</p>}
    </div>
  );
}

export function BidDraftForm({
  bidId, reference, version, due, readOnly, rules, initial,
}: {
  bidId: string;
  reference: string;
  /** The version this draft becomes when submitted. */
  version: number;
  /** The bid due time, already formatted in the configured zone. */
  due: string;
  readOnly: boolean;
  rules: BidRules;
  initial: Pick<BidDraft, "itemCents" | "alternateCents" | "bidBondChoice" | "files">;
}) {
  const router = useRouter();
  const nItems = rules.schedule.items.length;
  const nAlts = rules.schedule.alternates.length;
  const [items, setItems] = useState<string[]>(() => Array.from({ length: nItems }, (_, i) => toInput(initial.itemCents[i] ?? null)));
  const [alts, setAlts] = useState<string[]>(() => Array.from({ length: nAlts }, (_, i) => toInput(initial.alternateCents[i] ?? null)));
  const [saved, setSaved] = useState({ items: items.join("|"), alts: alts.join("|") });
  const [choice, setChoice] = useState<BidBondChoice | null>(initial.bidBondChoice);
  const [files, setFiles] = useState<BidDraft["files"]>(initial.files);
  const [message, setMessage] = useState<{ kind: "ok" | "error"; text: string } | null>(null);
  const [saving, setSaving] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const bonds = deriveRequirements(rules.estimateCents ?? 0, false, rules.optionalSections).bonds;
  const parse = (s: string): Cents | null => (s.trim() === "" ? null : parseMoney(s));
  const draft: BidDraft = useMemo(() => ({
    bidId, reference, version,
    itemCents: items.map(parse), alternateCents: alts.map(parse),
    bidBondChoice: choice, files,
  }), [bidId, reference, version, items, alts, choice, files]);
  const issues = useMemo(() => validateBidDraft(draft, rules), [draft, rules]);
  const total = baseTotalCents(draft.itemCents.filter((c): c is Cents => c !== null));
  const allItemsEntered = draft.itemCents.every((c) => c !== null);
  const dirty = items.join("|") !== saved.items || alts.join("|") !== saved.alts;
  const slots = requiredUploadSlots(rules, choice);

  async function savePrices() {
    setSaving(true);
    setMessage(null);
    const r = await saveBidPrices(bidId, { items, alternates: alts });
    setSaving(false);
    if (!r.ok) { setMessage({ kind: "error", text: r.message }); return; }
    setSaved({ items: items.join("|"), alts: alts.join("|") });
    setMessage({ kind: "ok", text: "Prices saved." });
    router.refresh();
  }

  async function chooseBond(next: BidBondChoice) {
    const previous = choice;
    setChoice(next);
    setMessage(null);
    const r = await setBidBondChoice(bidId, next);
    if (!r.ok) { setChoice(previous); setMessage({ kind: "error", text: r.message }); return; }
    // A bond file only belongs with the electronic choice; the server dropped it for the other one.
    if (next !== "electronic") setFiles((prev) => prev.filter((f) => f.slot !== "bid_bond"));
    router.refresh();
  }

  /** Records an uploaded file, appending to the latest state so concurrent uploads never drop each other. */
  async function uploaded(added: UploadedBidFile): Promise<string | null> {
    const r = await attachBidFile(bidId, added.slot, added.path, added.fileName);
    if (!r.ok) return r.message;
    setFiles((prev) => [...prev.filter((f) => f.slot !== added.slot), added]);
    router.refresh();
    return null;
  }

  async function removed(slot: UploadSlot): Promise<string | null> {
    const r = await removeBidFile(bidId, slot);
    if (!r.ok) return r.message;
    setFiles((prev) => prev.filter((f) => f.slot !== slot));
    router.refresh();
    return null;
  }

  async function submit() {
    setSubmitting(true);
    setMessage(null);
    const r = await submitBid(bidId);
    setSubmitting(false);
    setConfirming(false);
    if (!r.ok) {
      const more = "issues" in r ? r.issues.map((i) => i.message).join(" ") : "";
      setMessage({ kind: "error", text: more ? `${r.message} ${more}` : r.message });
    }
    router.refresh();
  }

  const bad = (s: string) => s.trim() !== "" && parseMoney(s) === null;

  return (
    <div className="bid-draft">
      <p>
        Bid reference: <strong data-testid="bid-reference">{reference}</strong>
      </p>
      <p data-testid="draft-version">This draft will be submitted as version {version}.</p>
      <p>
        {dirty ? (
          // The form prints the saved draft, so unsaved prices would not appear on it.
          <><span aria-disabled="true" data-testid="print-form-disabled">Print bid form (version {version})</span>
            {" "}Save your prices first: the printed form shows saved prices only.</>
        ) : (
          <a href={`/api/bids/${bidId}/form`} target="_blank" rel="noreferrer" data-testid="print-form">Print bid form (version {version})</a>
        )}
      </p>
      <p>Bids are due {due}.{readOnly && " Bidding has closed, so this draft can no longer be changed."}</p>

      <h2>Prices</h2>
      <table className="list">
        <thead><tr><th>Line</th><th>Description</th><th>Amount</th></tr></thead>
        <tbody>
          {rules.schedule.items.map((it, i) => (
            <tr key={`i${i}`}>
              <td>Item {i + 1}</td>
              <td>{it.name}{it.description ? `: ${it.description}` : ""}</td>
              <td>
                $<input
                  aria-label={`Item ${i + 1} amount`} inputMode="decimal" value={items[i]} disabled={readOnly}
                  onChange={(e) => setItems((p) => p.map((v, k) => (k === i ? e.target.value : v)))}
                  aria-invalid={bad(items[i])}
                />
                {bad(items[i]) && <span className="error"> Enter a dollar amount like 12,500.00</span>}
              </td>
            </tr>
          ))}
          {rules.schedule.alternates.map((a, i) => (
            <tr key={`a${i}`}>
              <td>Alternate {i + 1} ({a.kind === "additive" ? "add" : "deduct"})</td>
              <td>{a.description}</td>
              <td>
                $<input
                  aria-label={`Alternate ${i + 1} amount`} inputMode="decimal" value={alts[i]} disabled={readOnly}
                  onChange={(e) => setAlts((p) => p.map((v, k) => (k === i ? e.target.value : v)))}
                  aria-invalid={bad(alts[i])}
                />
                {bad(alts[i]) && <span className="error"> Enter a dollar amount like 12,500.00</span>}
              </td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <th colSpan={2}>Base total{allItemsEntered ? "" : " (items entered so far)"}</th>
            <td data-testid="base-total">{formatMoney(total)}</td>
          </tr>
        </tfoot>
      </table>
      {!readOnly && (
        <p>
          <button type="button" disabled={saving || !dirty} onClick={() => void savePrices()}>Save prices</button>
          {dirty && <span> You have unsaved prices.</span>}
        </p>
      )}

      {bonds && (
        <fieldset>
          <legend>Bid bond</legend>
          <p>This solicitation requires a bid bond.</p>
          <label className="inline">
            <input type="radio" name="bond" checked={choice === "electronic"} disabled={readOnly}
              onChange={() => void chooseBond("electronic")} />
            {" "}Electronic surety bond (upload it below)
          </label>
          <label className="inline">
            <input type="radio" name="bond" checked={choice === "paper"} disabled={readOnly}
              onChange={() => void chooseBond("paper")} />
            {" "}Paper original mailed
          </label>
        </fieldset>
      )}

      <h2>Required uploads</h2>
      {slots.map((slot) => (
        <BidFileUploader
          key={slot}
          slot={slot}
          title={UPLOAD_SLOT_LABELS[slot]}
          current={files.find((f) => f.slot === slot) ?? null}
          disabled={readOnly}
          createUploadUrl={(name) => createBidUploadUrl(bidId, slot, name)}
          onUploaded={uploaded}
          onRemove={() => removed(slot)}
        />
      ))}

      {message && <p role={message.kind === "error" ? "alert" : "status"} className={message.kind === "error" ? "error" : undefined}>{message.text}</p>}

      {!readOnly && (
        <>
        <h2>Before you can submit</h2>
        {issues.length === 0 ? (
          <p data-testid="bid-ready">Nothing is missing from this draft.{dirty && " Save your prices first."}</p>
        ) : (
          <ul data-testid="bid-issues">
            {issues.map((i) => <li key={`${i.code}:${i.field}`} data-code={i.code}>{i.message}</li>)}
          </ul>
        )}
        {!confirming ? (
          <p>
            <button type="button" data-testid="submit-bid" disabled={issues.length > 0 || dirty || saving}
              onClick={() => setConfirming(true)}>Submit bid (version {version})</button>
          </p>
        ) : (
          <div role="alertdialog" aria-label="Confirm submit" data-testid="submit-confirm">
            <p><strong>Submit version {version}?</strong></p>
            <p>Once you submit, you cannot see your prices or files again.</p>
            <p>Print the bid form for version {version} first: it is not available after you submit. The signed form for this
              version must be received by {due}.</p>
            <button type="button" disabled={submitting} onClick={() => void submit()}>Yes, submit version {version}</button>
            {" "}
            <button type="button" disabled={submitting} onClick={() => setConfirming(false)}>Cancel</button>
          </div>
        )}
        </>
      )}
    </div>
  );
}
