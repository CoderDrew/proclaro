"use client";

import { useRef, useState } from "react";
import { createBrowserClient } from "@/lib/supabase/browser";
import type { AttachmentKind, SolicitationData } from "@/domain/solicitation/types";

type Attachment = SolicitationData["attachments"][number];

/** "Remove <label>", numbered (1-based) when another attachment would get the same name. */
function removeLabel(all: Attachment[], index: number, title: string): string {
  const base = all[index].label || title;
  const clash = all.some((o, i) => i !== index && (o.label || title) === base);
  return `Remove ${base}${clash ? ` (${index + 1})` : ""}`;
}

/**
 * One upload slot per attachment kind. The file goes browser -> Storage through a signed upload URL
 * (never through a server action body), then the attachment is added with its storagePath.
 */
export function AttachmentUploader({
  kind, title, needsIssueDate, attachments, disabled, createUploadUrl, onChange, onUploaded,
}: {
  kind: AttachmentKind;
  title: string;
  needsIssueDate: boolean;
  attachments: Attachment[];
  disabled?: boolean;
  createUploadUrl: (fileName: string) => Promise<{ path: string; token: string }>;
  onChange: (next: Attachment[]) => void;
  /** Receives only the new attachment; the caller appends it to the latest form state. */
  onUploaded: (added: Attachment) => void;
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
        .storage.from("attachments")
        .uploadToSignedUrl(path, token, file);
      if (upErr) throw upErr;
      onUploaded({ kind, label: file.name, storagePath: path, issueDate: null });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setBusy(false);
      if (input.current) input.current.value = "";
    }
  }

  const mine = attachments.map((a, index) => ({ a, index })).filter((x) => x.a.kind === kind);
  const patch = (index: number, p: Partial<Attachment>) =>
    onChange(attachments.map((a, i) => (i === index ? { ...a, ...p } : a)));

  return (
    <div className="attachment-slot">
      <strong>{title}</strong>
      {mine.map(({ a, index }) => (
        <div key={a.storagePath} className="row">
          <input
            aria-label={`${title} label`} value={a.label} disabled={disabled}
            onChange={(e) => patch(index, { label: e.target.value })}
          />
          {needsIssueDate && (
            <label className="sol-inline">Issue date
              <input
                type="date" value={a.issueDate ?? ""} disabled={disabled}
                onChange={(e) => patch(index, { issueDate: e.target.value || null })}
              />
            </label>
          )}
          {!disabled && (
            <button
              type="button" aria-label={removeLabel(attachments, index, title)}
              onClick={() => onChange(attachments.filter((_, i) => i !== index))}
            >Remove</button>
          )}
        </div>
      ))}
      {!disabled && (
        <input
          ref={input} type="file" aria-label={`Upload ${title}`} disabled={busy}
          onChange={(e) => { const f = e.target.files?.[0]; if (f) void pick(f); }}
        />
      )}
      {busy && <span> Uploading...</span>}
      {error && <p role="alert" className="error">{error}</p>}
    </div>
  );
}
