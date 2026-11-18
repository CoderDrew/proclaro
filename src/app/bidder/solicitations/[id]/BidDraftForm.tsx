"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Button, Card, Choice, Money, MoneyInput, Notice, Table, Td, Th } from "@/components/ui";
import { BidFileUploader, type UploadedBidFile } from "@/components/BidFileUploader";
import { formatMoney, parseMoney, type Cents } from "@/domain/money";
import { UPLOAD_SLOT_LABELS, type BidBondChoice, type BidDraft, type UploadSlot } from "@/domain/bid/types";
import { baseTotalCents, requiredUploadSlots, validateBidDraft, type BidRules } from "@/domain/bid/validate";
import { deriveRequirements } from "@/domain/solicitation/valueBands";
import {
  attachBidFile, createBidUploadUrl, removeBidFile, saveBidPrices, setBidBondChoice, startBid, submitBid,
} from "./actions";
import { bidButtonState } from "./logic";

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
      <Button type="button" variant="primary" disabled={busy} onClick={() => void start()}>Start a bid</Button>
      {error && <Notice tone="error" role="alert">{error}</Notice>}
    </div>
  );
}

/** Opens the solicitation's unfilled bid form (for filling in by hand) in a new tab. */
export function PrintBlankFormButton({ solicitationId }: { solicitationId: string }) {
  return (
    <Button type="button" variant="secondary" data-testid="print-blank-form"
      onClick={() => window.open(`/api/solicitations/${solicitationId}/blank-form`, "_blank", "noopener")}>
      Print Blank Bid Form
    </Button>
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
  const { canPrintForSignature, canSubmit } = bidButtonState({
    readOnly, dirty, saving,
    allAmountsEntered: draft.itemCents.every((c) => c !== null) && draft.alternateCents.every((c) => c !== null),
    hasItems: nItems > 0,
    issueCount: issues.length,
  });

  // The browser warns before the bidder leaves the page (close, reload, typed URL) with unsaved amounts.
  useEffect(() => {
    if (!dirty) return;
    const warn = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = ""; };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  async function savePrices() {
    setSaving(true);
    setMessage(null);
    const r = await saveBidPrices(bidId, { items, alternates: alts });
    setSaving(false);
    if (!r.ok) { setMessage({ kind: "error", text: r.message }); return; }
    setSaved({ items: items.join("|"), alts: alts.join("|") });
    setMessage({ kind: "ok", text: "Amounts saved." });
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
      <p>Bids are due {due}.{readOnly && " Bidding has closed, so this draft can no longer be changed."}</p>

      <Card title="Amounts">
        <Table>
          <thead><tr><Th>Line</Th><Th>Description</Th><Th numeric>Amount</Th></tr></thead>
          <tbody>
            {rules.schedule.items.map((it, i) => (
              <tr key={`i${i}`}>
                <Td>Item {i + 1}</Td>
                <Td>{it.name}{it.description ? `: ${it.description}` : ""}</Td>
                <Td numeric>
                  <MoneyInput
                    aria-label={`Item ${i + 1} amount`} value={items[i]} disabled={readOnly}
                    onChange={(e) => setItems((p) => p.map((v, k) => (k === i ? e.target.value : v)))}
                    aria-invalid={bad(items[i])}
                  />
                  {bad(items[i]) && <span className="error"> Enter a dollar amount like 12,500.00</span>}
                </Td>
              </tr>
            ))}
            {rules.schedule.alternates.map((a, i) => (
              <tr key={`a${i}`}>
                <Td>Alternate {i + 1} ({a.kind === "additive" ? "add" : "deduct"})</Td>
                <Td>{a.description}</Td>
                <Td numeric>
                  <MoneyInput
                    aria-label={`Alternate ${i + 1} amount`} value={alts[i]} disabled={readOnly}
                    onChange={(e) => setAlts((p) => p.map((v, k) => (k === i ? e.target.value : v)))}
                    aria-invalid={bad(alts[i])}
                  />
                  {bad(alts[i]) && <span className="error"> Enter a dollar amount like 12,500.00</span>}
                </Td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr>
              <Th colSpan={2}>Base total{allItemsEntered ? "" : " (items entered so far)"}</Th>
              <Td numeric data-testid="base-total"><Money cents={total} /></Td>
            </tr>
          </tfoot>
        </Table>
        {!readOnly && (
          <div className="ui-actions">
            <Button type="button" variant="primary" disabled={saving || !dirty} onClick={() => void savePrices()}>Save Amounts</Button>
            {dirty && <span data-testid="unsaved-notice" role="status" className="ui-badge ui-badge--warning"> Unsaved changes</span>}
          </div>
        )}
      </Card>

      {bonds && (
        <Card title="Bid bond">
          <fieldset className="ui-fieldset">
            <legend className="visually-hidden">Bid bond</legend>
            <p>This solicitation requires a bid bond.</p>
            <Choice label="Electronic surety bond (upload it below)">
              <input type="radio" name="bond" checked={choice === "electronic"} disabled={readOnly}
                onChange={() => void chooseBond("electronic")} />
            </Choice>
            <Choice label="Paper original mailed">
              <input type="radio" name="bond" checked={choice === "paper"} disabled={readOnly}
                onChange={() => void chooseBond("paper")} />
            </Choice>
          </fieldset>
        </Card>
      )}

      <Card title="Required uploads">
        <p>One file per item. Uploading again replaces the current file.</p>
        <div className="ui-upload-list">
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
        </div>
      </Card>

      {message && (
        <Notice tone={message.kind === "error" ? "error" : "success"} role={message.kind === "error" ? "alert" : "status"}>{message.text}</Notice>
      )}

      <Card title="Print for signature">
        <div className="ui-actions">
          <Button type="button" variant="secondary" data-testid="print-form" disabled={!canPrintForSignature}
            onClick={() => window.open(`/api/bids/${bidId}/form`, "_blank", "noopener")}>
            Print Bid Form for Signature
          </Button>
          {dirty && <span> Unsaved changes: save your amounts first.</span>}
          {!dirty && !canPrintForSignature && !readOnly && <span> Enter and save every amount to print the form.</span>}
        </div>
      </Card>

      {!readOnly && (
        <Card title="Before you can submit">
          {issues.length === 0 ? (
            <Notice tone="success" data-testid="bid-ready">Nothing is missing from this draft.{dirty && " Save your amounts first."}</Notice>
          ) : (
            <Notice tone="warning">
              <ul data-testid="bid-issues">
                {issues.map((i) => <li key={`${i.code}:${i.field}`} data-code={i.code}>{i.message}</li>)}
              </ul>
            </Notice>
          )}
          {!confirming ? (
            <div className="ui-actions">
              <Button type="button" variant="primary" data-testid="submit-bid" disabled={!canSubmit}
                onClick={() => setConfirming(true)}>Submit bid (version {version})</Button>
            </div>
          ) : (
            <Notice tone="warning" role="alertdialog" aria-label="Confirm submit" data-testid="submit-confirm">
              <p><strong>Submit version {version}?</strong></p>
              <p>Once you submit, you cannot see your prices or files again.</p>
              <p>Print the bid form for version {version} first: it is not available after you submit. The signed form for this
                version must be received by {due}.</p>
              <div className="ui-actions">
                <Button type="button" variant="primary" disabled={submitting} onClick={() => void submit()}>Yes, submit version {version}</Button>
                <Button type="button" variant="secondary" disabled={submitting} onClick={() => setConfirming(false)}>Cancel</Button>
              </div>
            </Notice>
          )}
        </Card>
      )}
    </div>
  );
}
