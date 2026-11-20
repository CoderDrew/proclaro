"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@/lib/supabase/browser";
import { Button, Card, DateTime, Notice } from "@/components/ui";
import { formatInstant } from "@/app/solicitations/status";
import { createCureUploadUrl, submitCureBond } from "./actions";
import { cureMessageFor, cureStatusText, type CureStatus } from "./logic";

const TONE = { pending: "warning", cured: "success", failed: "error" } as const;

/**
 * The bid-bond cure after close: the database's status (my_bid_cure) and deadline, worded for the bidder. While the
 * cure is pending, one file input uploads the bond: browser -> Storage through a signed URL (the Storage policy
 * allows only the caller's own pending bid), then submit_cure_bond records it, re-checking the deadline on the
 * database clock. Nothing else about the bid can be changed here.
 */
export function CurePanel({ bidId, status, dueAt, tz }: { bidId: string; status: CureStatus; dueAt: string | null; tz: string }) {
  const router = useRouter();
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (status !== "pending" && status !== "cured" && status !== "failed") return null;
  const text = cureStatusText(status, dueAt ? formatInstant(dueAt, tz) : "");

  async function pick(file: File) {
    setBusy(true);
    setError(null);
    try {
      const url = await createCureUploadUrl(bidId, file.name);
      if (!url.ok) { setError(url.message); return; }
      const { error: upErr } = await createBrowserClient().storage.from("bid-files").uploadToSignedUrl(url.path, url.token, file);
      if (upErr) { setError(cureMessageFor(upErr)); return; }
      const r = await submitCureBond(bidId, url.path, file.name);
      if (!r.ok) { setError(r.message); return; }
      router.refresh();
    } catch (e) {
      setError(cureMessageFor(e));
    } finally {
      setBusy(false);
      if (input.current) input.current.value = "";
    }
  }

  return (
    <Card title="Bid bond cure" data-testid="cure-panel">
      <Notice tone={TONE[status]} data-testid={`cure-${status}`}>{text}</Notice>
      {dueAt && <p>Cure deadline: <DateTime iso={dueAt} tz={tz} /></p>}
      {status === "pending" && (
        <div className="ui-actions">
          <input
            ref={input} type="file" className="visually-hidden" tabIndex={-1} aria-label="Bid bond file" disabled={busy}
            onChange={(e) => { const f = e.target.files?.[0]; if (f) void pick(f); }}
          />
          <Button type="button" variant="primary" data-testid="cure-upload" disabled={busy} onClick={() => input.current?.click()}>
            Upload bid bond
          </Button>
          {busy && <span> Working...</span>}
        </div>
      )}
      {error && <Notice tone="error" role="alert">{error}</Notice>}
    </Card>
  );
}
