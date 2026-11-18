"use client";

import { useRef, useState } from "react";
import { createBrowserClient } from "@/lib/supabase/browser";
import type { UploadSlot } from "@/domain/bid/types";
import { bidMessageFor } from "@/app/bidder/solicitations/[id]/logic";

export interface UploadedBidFile { slot: UploadSlot; path: string; fileName: string }

/**
 * One upload slot of a bid. Like AttachmentUploader, the file goes browser -> Storage through a signed upload URL
 * (never through a server action body), and the caller is told only about the new file: it records it and
 * appends to the *latest* state, so two slots uploading at once cannot drop each other.
 */
export function BidFileUploader({
  slot, title, current, disabled, createUploadUrl, onUploaded, onRemove,
}: {
  slot: UploadSlot;
  title: string;
  /** The file currently in this slot, if any. */
  current: { fileName: string } | null;
  disabled?: boolean;
  createUploadUrl: (fileName: string) => Promise<{ path: string; token: string }>;
  /** Called once the object is in Storage. Resolves with an error message when the file could not be recorded. */
  onUploaded: (added: UploadedBidFile) => Promise<string | null>;
  onRemove: () => Promise<string | null>;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);

  async function pick(file: File) {
    setBusy(true);
    setError(null);
    try {
      const { path, token } = await createUploadUrl(file.name);
      const { error: upErr } = await createBrowserClient()
        .storage.from("bid-files")
        .uploadToSignedUrl(path, token, file);
      if (upErr) { setError(bidMessageFor(upErr)); return; }
      const problem = await onUploaded({ slot, path, fileName: file.name });
      if (problem) setError(problem);
    } catch (e) {
      setError(bidMessageFor(e));
    } finally {
      setBusy(false);
      if (input.current) input.current.value = "";
    }
  }

  async function remove() {
    setBusy(true);
    setError(null);
    try {
      const problem = await onRemove();
      if (problem) setError(problem);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="attachment-slot" data-slot={slot}>
      <strong>{title}</strong>
      {current && (
        <div className="row">
          <span data-testid={`file-${slot}`}>{current.fileName}</span>
          {!disabled && <button type="button" disabled={busy} onClick={() => void remove()}>Remove</button>}
        </div>
      )}
      {!disabled && (
        <input
          ref={input} type="file" aria-label={`Upload ${title}`} disabled={busy}
          onChange={(e) => { const f = e.target.files?.[0]; if (f) void pick(f); }}
        />
      )}
      {busy && <span> Working...</span>}
      {error && <p role="alert" className="error">{error}</p>}
    </div>
  );
}
