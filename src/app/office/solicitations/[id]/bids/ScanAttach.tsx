"use client";

// Attach a scan of a mailed original after close (for the AI document check). The browser checks the file (PDF, at
// most 20 MB and 30 pages) before upload; the database checks the office, the timing, the entry and the size again.
import { startTransition, useId, useState } from "react";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@/lib/supabase/browser";
import { Button, Notice } from "@/components/ui";
import { attachScan, createScanUploadUrl } from "../review/aicheck/actions";
import { scanProblem } from "../review/aicheck/logic";

export function ScanAttach(props: { bidId: string; entryId: string; entryLabel: string; scanUrl: string | null }) {
  const router = useRouter();
  const inputId = useId();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  async function onFile(file: File) {
    setBusy(true);
    setError(null);
    setDone(null);
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      const problem = await scanProblem(file.name, file.type, bytes);
      if (problem) { setError(problem); return; }
      const url = await createScanUploadUrl(props.bidId, props.entryId);
      if (!url.ok) { setError(url.message); return; }
      const { error: upErr } = await createBrowserClient().storage.from("bid-files")
        .uploadToSignedUrl(url.path, url.token, file, { contentType: "application/pdf" });
      if (upErr) { setError("The upload failed. Try again."); return; }
      const r = await attachScan(props.entryId, url.path);
      if (!r.ok) { setError(r.message); return; }
      setDone("Scan attached.");
      startTransition(() => router.refresh());
    } catch {
      setError("Something went wrong. Reload the page and try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      {props.scanUrl && <a href={props.scanUrl} target="_blank" rel="noreferrer">Open scan</a>}{" "}
      <input id={inputId} aria-label={`Scan for ${props.entryLabel}`} type="file" accept="application/pdf,.pdf" hidden disabled={busy}
        onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) void onFile(f); }} />
      <Button type="button" variant="secondary" disabled={busy} aria-label={`Attach scan for ${props.entryLabel}`}
        onClick={() => (document.getElementById(inputId) as HTMLInputElement | null)?.click()}>
        {busy ? "Attaching…" : props.scanUrl ? "Replace scan" : "Attach scan"}
      </Button>
      <span role="status" aria-live="polite">{done}</span>
      {error && <Notice tone="error" role="alert">{error}</Notice>}
    </div>
  );
}
