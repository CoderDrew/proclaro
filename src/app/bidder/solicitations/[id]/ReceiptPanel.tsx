"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button, Card, Notice, StatusBadge, receiptKey } from "@/components/ui";
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
    <Card title="Receipts" data-testid="receipts">
      <ul className="ui-receipts">
        {receipts.map((r) => (
          <li key={r.version} data-testid={`receipt-${r.version}`}>
            {r.line} <StatusBadge status={{ kind: "bidVersion", status: receiptKey(r) }} label={r.status} wrap />
          </li>
        ))}
      </ul>
      {current && <Notice tone="info" data-testid="mail-notice">{afterSubmitNotice(current.version, due)}</Notice>}
      {!current && <Notice tone="warning">Your latest version is withdrawn, so you have no bid on file.</Notice>}
      {open && !confirm && (
        <div className="ui-actions">
          {current && <Button type="button" variant="danger" data-testid="withdraw-bid" onClick={() => setConfirm("withdraw")}>Withdraw version {current.version}</Button>}
          {!hasDraft && (
            <Button type="button" variant="secondary" data-testid="replace-bid" onClick={() => setConfirm("replace")}>
              {current ? "Replace with a new version" : "Start a new version"}
            </Button>
          )}
        </div>
      )}
      {open && confirm && (
        <Notice tone="warning" role="alertdialog" aria-label={confirm === "withdraw" ? "Confirm withdraw" : "Confirm replace"} data-testid="receipt-confirm">
          <p>{confirm === "withdraw" ? withdrawConfirmation(latest.version, due) : replaceConfirmationFor(receipts)}</p>
          <div className="ui-actions">
            <Button type="button" variant={confirm === "withdraw" ? "danger" : "primary"} disabled={busy} onClick={() => void run(confirm)}>
              {confirm === "withdraw" ? "Yes, withdraw" : "Yes, start a new draft"}
            </Button>
            <Button type="button" variant="secondary" disabled={busy} onClick={() => setConfirm(null)}>Cancel</Button>
          </div>
        </Notice>
      )}
      {error && <Notice tone="error" role="alert">{error}</Notice>}
    </Card>
  );
}
