"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { logOriginal, voidOriginal } from "./actions";
import { ITEM_LABELS, ORIGINAL_ITEMS } from "./logic";
import type { ActionResult } from "../logic";
import { ScanAttach } from "./ScanAttach";
import { Button, Card, EmptyState, Field, FieldGrid, Notice, StatusBadge, Table, Td, Th } from "@/components/ui";

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
  bidId: string;
  /** After close, receipts that aren't voided can take a scan (for the AI document check). */
  scannable: boolean;
  /** A signed link to the entry's current scan, when there is one. */
  scanUrl: string | null;
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
    <div className="ui-stack">
      <Card as="section" title="Submitted bids">
        {props.index.length === 0 ? (
          <EmptyState>No bids have been submitted.</EmptyState>
        ) : (
          <Table data-testid="bid-index">
            <thead><tr><Th>Reference</Th><Th>Version</Th><Th>Status</Th></tr></thead>
            <tbody>
              {props.index.map((r) => (
                <tr key={`${r.reference}-${r.version}`}>
                  <Td>{r.reference}</Td><Td>{r.version}</Td>
                  <Td><StatusBadge status={{ kind: "bidVersion", status: r.status }} /></Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>

      {props.canWork && (
        <Card as="section" title="Log a mailed original">
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
            <FieldGrid>
              <Field label="Bid reference">
                <input value={reference} onChange={(e) => setReference(e.target.value)} placeholder="XXXX-XXXX" />
              </Field>
              <Field label="Version">
                <input type="number" min={1} step={1} value={version} onChange={(e) => setVersion(e.target.value)} className="ui-input-narrow" />
              </Field>
              <Field label="Item">
                <select value={item} onChange={(e) => setItem(e.target.value)}>
                  {ORIGINAL_ITEMS.map((i) => <option key={i} value={i}>{ITEM_LABELS[i]}</option>)}
                </select>
              </Field>
              <Field label="Received at">
                <input type="datetime-local" value={receivedAt} onChange={(e) => setReceivedAt(e.target.value)} />
              </Field>
            </FieldGrid>
            <p className="ui-actions">
              <Button type="submit" variant="primary" disabled={busy}>Log</Button>
            </p>
            <p className="muted ui-office-note">
              Times are in the configured time zone. Leave &ldquo;Received at&rdquo; blank to use the current time.
            </p>
          </form>
        </Card>
      )}

      {message && <Notice tone="error" role="alert">{message}</Notice>}

      <Card as="section" title="Originals log">
        {props.entries.length === 0 ? (
          <EmptyState>Nothing has been logged.</EmptyState>
        ) : (
          <Table data-testid="originals-log">
            <thead>
              <tr><Th>Entry</Th><Th>Logged</Th><Th>Reference</Th><Th>Version</Th><Th>Item</Th><Th>Received at</Th><Th>By</Th><Th /></tr>
            </thead>
            <tbody>
              {props.entries.map((e) => {
                const struck = e.voidedReason !== null;
                const cell = struck ? "is-voided" : undefined;
                return (
                  <tr key={e.id} data-testid={`entry-${e.id}`}>
                    <Td>{shortId(e.id)}</Td>
                    <Td className={cell}>
                      {e.logged}{e.afterDue && <> <StatusBadge status={{ kind: "logEntry", flag: "afterDue" }} /></>}
                    </Td>
                    <Td className={cell}>{e.reference}</Td>
                    <Td className={cell}>{e.version}</Td>
                    <Td className={cell}>{e.item}</Td>
                    <Td>
                      {e.voidsEntryId ? (
                        <>Void of entry {shortId(e.voidsEntryId)}. Reason: {e.reason}</>
                      ) : (
                        <span className={cell}>{e.received}</span>
                      )}
                      {struck && <div>Voided. Reason: {e.voidedReason}</div>}
                    </Td>
                    <Td>{e.by}</Td>
                    <Td>
                      {props.canWork && e.scannable && !struck && (
                        <ScanAttach bidId={e.bidId} entryId={e.id}
                          entryLabel={`entry ${shortId(e.id)} (${e.reference})`} scanUrl={e.scanUrl} />
                      )}
                      {props.canWork && !e.voidsEntryId && !struck && voiding !== e.id && (
                        <Button type="button" variant="danger" disabled={busy} aria-label={`Void entry ${shortId(e.id)}`}
                          onClick={() => { setVoiding(e.id); setVoidReason(""); }}>Void</Button>
                      )}
                      {voiding === e.id && (
                        <Notice tone="warning" role="alertdialog" aria-label="Confirm void" className="ui-void-confirm">
                          <Field label="Reason">
                            <input value={voidReason} onChange={(ev) => setVoidReason(ev.target.value)} />
                          </Field>
                          <span className="ui-inline-actions">
                            <Button type="button" variant="danger" disabled={busy}
                              onClick={() => void act(() => voidOriginal(e.id, voidReason), () => setVoiding(null))}>Confirm void</Button>
                            <Button type="button" variant="secondary" disabled={busy} onClick={() => setVoiding(null)}>Cancel</Button>
                          </span>
                        </Notice>
                      )}
                    </Td>
                  </tr>
                );
              })}
            </tbody>
          </Table>
        )}
      </Card>
    </div>
  );
}
