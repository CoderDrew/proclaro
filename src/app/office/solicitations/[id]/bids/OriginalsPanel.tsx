"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { logOriginal, voidOriginal } from "./actions";
import { ITEM_LABELS, ORIGINAL_ITEMS } from "./logic";
import type { ActionResult } from "../logic";

export interface IndexRow { reference: string; version: number; status: string }
export interface EntryView {
  id: string;
  logged: string;
  by: string;
  reference: string;
  version: number;
  item: string;
  /** Receipts only. */
  received: string | null;
  /** Void rows: the entry they void. */
  voidsEntryId: string | null;
  reason: string | null;
  /** Receipts only: the void's reason when this receipt has been voided. */
  voidedReason: string | null;
  afterDue: boolean;
}

/**
 * The office's view of a solicitation's bids: reference, version and status only (office_bid_index), the log form
 * for mailed originals, and the append-only log with voids.
 */
export function OriginalsPanel(props: {
  solicitationId: string;
  index: IndexRow[];
  entries: EntryView[];
  canWork: boolean;
}) {
  const router = useRouter();
  const [reference, setReference] = useState("");
  const [version, setVersion] = useState("");
  const [item, setItem] = useState<string>("signed_form");
  const [receivedAt, setReceivedAt] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [voiding, setVoiding] = useState<string | null>(null);
  const [voidReason, setVoidReason] = useState("");

  async function act(fn: () => Promise<ActionResult>, onOk: () => void) {
    setBusy(true);
    setMessage(null);
    try {
      const r = await fn();
      if (r.ok) {
        onOk();
        router.refresh();
      } else {
        setMessage(r.message);
      }
    } catch {
      setMessage("Something went wrong. Reload the page and try again.");
    } finally {
      setBusy(false);
    }
  }

  const shortId = (id: string) => id.slice(0, 8);

  return (
    <div style={{ display: "grid", gap: 16 }}>
      <section>
        <h2>Submitted bids</h2>
        {props.index.length === 0 ? (
          <p>No bids have been submitted.</p>
        ) : (
          <table className="list" data-testid="bid-index">
            <thead><tr><th>Reference</th><th>Version</th><th>Status</th></tr></thead>
            <tbody>
              {props.index.map((r) => (
                <tr key={`${r.reference}-${r.version}`}><td>{r.reference}</td><td>{r.version}</td><td>{r.status}</td></tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      {props.canWork && (
        <section>
          <h2>Log a mailed original</h2>
          <form
            className="sol-form"
            onSubmit={(e) => {
              e.preventDefault();
              void act(() => logOriginal(props.solicitationId, { reference, version, item, receivedAt }), () => {
                setReference("");
                setVersion("");
                setReceivedAt("");
              });
            }}
          >
            <div className="row">
              <label>Bid reference <input value={reference} onChange={(e) => setReference(e.target.value)} placeholder="XXXX-XXXX" /></label>
              <label>Version <input type="number" min={1} step={1} value={version} onChange={(e) => setVersion(e.target.value)} style={{ width: 80 }} /></label>
              <label>Item
                <select value={item} onChange={(e) => setItem(e.target.value)}>
                  {ORIGINAL_ITEMS.map((i) => <option key={i} value={i}>{ITEM_LABELS[i]}</option>)}
                </select>
              </label>
              <label>Received at <input type="datetime-local" value={receivedAt} onChange={(e) => setReceivedAt(e.target.value)} /></label>
              <button type="submit" disabled={busy}>Log</button>
            </div>
            <p style={{ margin: "4px 0 0", fontSize: 12 }}>
              Times are in the configured time zone. Leave &ldquo;Received at&rdquo; blank to use the current time.
            </p>
          </form>
        </section>
      )}

      {message && <p role="alert" className="error">{message}</p>}

      <section>
        <h2>Originals log</h2>
        {props.entries.length === 0 ? (
          <p>Nothing has been logged.</p>
        ) : (
          <table className="list" data-testid="originals-log">
            <thead>
              <tr><th>Entry</th><th>Logged</th><th>Reference</th><th>Version</th><th>Item</th><th>Received at</th><th>By</th><th /></tr>
            </thead>
            <tbody>
              {props.entries.map((e) => {
                const struck = e.voidedReason !== null;
                const cell = struck ? { textDecoration: "line-through" } : undefined;
                return (
                  <tr key={e.id} data-testid={`entry-${e.id}`}>
                    <td>{shortId(e.id)}</td>
                    <td style={cell}>{e.logged}{e.afterDue && " (after the bid due time)"}</td>
                    <td style={cell}>{e.reference}</td>
                    <td style={cell}>{e.version}</td>
                    <td style={cell}>{e.item}</td>
                    <td>
                      {e.voidsEntryId ? (
                        <>Void of entry {shortId(e.voidsEntryId)}. Reason: {e.reason}</>
                      ) : (
                        <span style={cell}>{e.received}</span>
                      )}
                      {struck && <div>Voided. Reason: {e.voidedReason}</div>}
                    </td>
                    <td>{e.by}</td>
                    <td>
                      {props.canWork && !e.voidsEntryId && !struck && voiding !== e.id && (
                        <button type="button" disabled={busy} onClick={() => { setVoiding(e.id); setVoidReason(""); }}>Void</button>
                      )}
                      {voiding === e.id && (
                        <div role="alertdialog" aria-label="Confirm void">
                          <label>Reason <input value={voidReason} onChange={(ev) => setVoidReason(ev.target.value)} /></label>{" "}
                          <button type="button" disabled={busy}
                            onClick={() => void act(() => voidOriginal(e.id, voidReason), () => setVoiding(null))}>Confirm void</button>{" "}
                          <button type="button" disabled={busy} onClick={() => setVoiding(null)}>Cancel</button>
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </section>
    </div>
  );
}
