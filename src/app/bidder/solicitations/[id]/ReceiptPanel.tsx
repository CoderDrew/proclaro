"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { replaceBid, withdrawBid } from "./actions";
import { afterSubmitNotice, replaceConfirmationFor, withdrawConfirmation } from "./logic";

export interface ReceiptView { version: number; line: string; status: string; isCurrent: boolean; withdrawn: boolean }

/**
 * Every submitted version: time, reference, version and status. Never prices (the bidder cannot read them).
 * Withdraw and replace sit here, each behind a confirmation; they are hidden unless the database says bidding is
 * open (it refuses regardless).
 */
export function ReceiptPanel({
  bidId, receipts, due, open, hasDraft,
}: { bidId: string; receipts: ReceiptView[]; due: string; open: boolean; hasDraft: boolean }) {
  const router = useRouter();
  const [confirm, setConfirm] = useState<"withdraw" | "replace" | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const latest = receipts.length ? receipts[receipts.length - 1] : null;
  const current = receipts.find((r) => r.isCurrent) ?? null;

  async function run(kind: "withdraw" | "replace") {
    setBusy(true);
    setError(null);
    const r = kind === "withdraw" ? await withdrawBid(bidId) : await replaceBid(bidId);
    setBusy(false);
    setConfirm(null);
    if (!r.ok) setError(r.message);
    router.refresh();
  }

  if (!latest) return null;
  return (
    <section data-testid="receipts">
      <h2>Receipts</h2>
      <ul>
        {receipts.map((r) => (
          <li key={r.version} data-testid={`receipt-${r.version}`}>{r.line} <strong>({r.status})</strong></li>
        ))}
      </ul>
      {current && <p data-testid="mail-notice">{afterSubmitNotice(current.version, due)}</p>}
      {!current && <p>Your latest version is withdrawn, so you have no bid on file.</p>}
      {open && !confirm && (
        <p>
          {current && <button type="button" data-testid="withdraw-bid" onClick={() => setConfirm("withdraw")}>Withdraw version {current.version}</button>}
          {" "}
          {!hasDraft && (
            <button type="button" data-testid="replace-bid" onClick={() => setConfirm("replace")}>
              {current ? "Replace with a new version" : "Start a new version"}
            </button>
          )}
        </p>
      )}
      {open && confirm && (
        <div role="alertdialog" aria-label={confirm === "withdraw" ? "Confirm withdraw" : "Confirm replace"} data-testid="receipt-confirm">
          <p>{confirm === "withdraw" ? withdrawConfirmation(latest.version, due) : replaceConfirmationFor(receipts)}</p>
          <button type="button" disabled={busy} onClick={() => void run(confirm)}>
            {confirm === "withdraw" ? "Yes, withdraw" : "Yes, start a new draft"}
          </button>
          {" "}
          <button type="button" disabled={busy} onClick={() => setConfirm(null)}>Cancel</button>
        </div>
      )}
      {error && <p role="alert" className="error">{error}</p>}
    </section>
  );
}
