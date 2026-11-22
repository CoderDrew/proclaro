// Pure, server-free logic behind the bidder draft actions. Kept out of the "use server" file so it can be
// tested with injected deps and so clients can never pass their own `deps` to a server action.
import { formatMoney, parseMoney, type Cents } from "@/domain/money";
import { MAX_PRICE_CENTS, type BidBondChoice, type BidDraft, type BidIssue, type UploadSlot } from "@/domain/bid/types";
import { validateBidDraft } from "@/domain/bid/validate";
import type { SolicitationData } from "@/domain/solicitation/types";
import { formatInstant } from "@/app/solicitations/status";
import { formatDateTime } from "@/documents/format";
import { toUtc } from "@/domain/time";
import { safeFileName } from "@/app/agency/solicitations/[id]/logic";

export type BidActionResult<T = object> = ({ ok: true } & T) | { ok: false; message: string };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUuid = (s: unknown): s is string => typeof s === "string" && UUID_RE.test(s);

const SLOTS: readonly UploadSlot[] = ["insurance", "qualifications", "references", "current_work", "bid_bond"];
export const isUploadSlot = (s: unknown): s is UploadSlot => SLOTS.includes(s as UploadSlot);

const MSG = {
  closed: "Bidding on this solicitation has closed.",
  notOpen: "This solicitation is not open for bidding.",
  state: "This bid is not in a state that allows that. Reload the page.",
  invalidBid: "The bid is incomplete. Check the problems listed on the page.",
  notFound: "That bid or solicitation was not found.",
  notAuthorized: "You are not allowed to do that.",
  upload: "That upload was not accepted. Try again.",
  pathSubmitted: "That file was already submitted with an earlier version. Choose the file again to upload a fresh copy.",
  storageRefused: "That upload was not accepted. Bidding may have closed. Reload the page.",
  storageExists: "That file was already uploaded. Choose the file again.",
  staleDraft: "An addendum changed the bid schedule. Reload the page and enter your prices again.",
  questionsClosed: "The deadline for questions has passed.",
  invalidQuestion: "Enter a question of 1 to 4,000 characters and a reference of up to 200.",
  generic: "Something went wrong. Try again.",
} as const;
const KNOWN_MESSAGES = new Set<string>(Object.values(MSG));

/**
 * Plain-language text for a bid error code, or for a Storage error (Supabase returns plain objects, not Errors,
 * so read .message / .statusCode). An already-worded message passes through; anything else is hidden.
 */
export function bidMessageFor(e: unknown): string {
  const obj = e && typeof e === "object" ? (e as { message?: unknown; statusCode?: unknown; code?: unknown }) : null;
  const code = obj && "message" in obj ? String(obj.message) : "";
  const status = obj ? String(obj.statusCode ?? "") : "";
  switch (code) {
    case "bids_closed": return MSG.closed;
    case "not_open": return MSG.notOpen;
    case "invalid_state": return MSG.state;
    case "invalid_bid": return MSG.invalidBid;
    case "not_found": return MSG.notFound;
    case "not_authorized": return MSG.notAuthorized;
    case "path_already_submitted": return MSG.pathSubmitted;
    case "stale_draft": return MSG.staleDraft;
    case "questions_closed": return MSG.questionsClosed;
    case "invalid_question": return MSG.invalidQuestion;
    case "invalid_upload_path":
    case "invalid_upload_slot": return MSG.upload;
  }
  if (KNOWN_MESSAGES.has(code)) return code;
  if (/row-level security/i.test(code) || status === "403") return MSG.storageRefused;
  if (/already exists|duplicate/i.test(code) || status === "409") return MSG.storageExists;
  return MSG.generic;
}

/** Runs an action body and turns any thrown error into a typed `{ ok:false, message }`. */
export async function toResult<T extends object = object>(fn: () => Promise<BidActionResult<T>>): Promise<BidActionResult<T>> {
  try {
    return await fn();
  } catch (e) {
    if (!(e instanceof Error) || !/^[a-z_]+$/.test(e.message)) console.error("bid action failed", e);
    return { ok: false, message: bidMessageFor(e) };
  }
}

/**
 * Parses the price inputs (blank becomes null so a draft can be partly filled). `label` names the row in
 * messages: "Item" or "Alternate".
 */
export function parsePriceInputs(
  inputs: string[], expected: number, label: "Item" | "Alternate" = "Item",
): { ok: true; cents: (Cents | null)[] } | { ok: false; message: string } {
  if (!Array.isArray(inputs) || inputs.length !== expected) {
    return { ok: false, message: `Enter one price for each ${label.toLowerCase()} (${expected}).` };
  }
  const cents: (Cents | null)[] = [];
  for (let i = 0; i < inputs.length; i++) {
    const text = String(inputs[i] ?? "").trim();
    if (text === "") { cents.push(null); continue; }
    const c = parseMoney(text);
    if (c === null) return { ok: false, message: `${label} ${i + 1}: enter a dollar amount like 12,500.00` };
    if (c > MAX_PRICE_CENTS) {
      return { ok: false, message: `${label} ${i + 1}: the amount is too large (the maximum is ${formatMoney(MAX_PRICE_CENTS)})` };
    }
    cents.push(c);
  }
  return { ok: true, cents };
}

/** bids/{bid_id}/{upload_id}/{safe file name}: the layout app.path_bid_id and the storage policies read. */
export function bidUploadPath(bidId: string, uploadId: string, fileName: string): string {
  return `bids/${bidId}/${uploadId}/${safeFileName(fileName)}`;
}

/** Throws invalid_upload_path unless `path` is `bids/{bidId}/{uuid}/{one file name}`. */
export function assertOwnBidPath(bidId: string, path: string): void {
  const parts = typeof path === "string" ? path.split("/") : [];
  const ok =
    parts.length === 4 && parts[0] === "bids" &&
    parts[1].toLowerCase() === String(bidId).toLowerCase() &&
    isUuid(parts[2]) && parts[3] !== "" && parts[3] !== ".." && parts[3] !== "." &&
    !path.includes("..") && !path.includes("\\");
  if (!ok) throw new Error("invalid_upload_path");
}

/** The name shown for an uploaded file: no directories, trimmed, bounded. */
function displayFileName(name: string): string {
  const base = String(name).split(/[\\/]/).pop() ?? "";
  const cleaned = base.replace(/[\u0000-\u001f]/g, "").trim();
  return cleaned === "" ? "file" : cleaned.slice(-200);
}

// ---------------------------------------------------------------------------
// Prices
// ---------------------------------------------------------------------------
export interface PriceDeps {
  /** The draft's current solicitation_version, or null when there is no draft row the caller can see. */
  draftVersion(): Promise<number | null>;
  /** The number of items and alternates in the solicitation's published schedule, or null when invisible. */
  schedule(): Promise<{ items: number; alternates: number } | null>;
  /** Writes the parsed prices to the draft (RLS and the open-time policy do the enforcing). */
  save(items: (Cents | null)[], alternates: (Cents | null)[]): Promise<void>;
}

/** A price save refused because the page was loaded before a schedule change reset the draft (R13). */
export type SavePricesResult = BidActionResult | { ok: false; stale: true; message: string };

/**
 * Validates against the stored schedule (never client counts), then saves. `solicitationVersion` is the draft's
 * version the page loaded: if the draft has moved on (an addendum changed the schedule and publish reset it), the
 * save is refused without writing, so prices typed against the old schedule never land in the reset draft. A
 * publish between this read and the write can still slip through (accepted TOCTOU window; submit_bid's
 * stale_draft guard still holds).
 */
export async function runSavePrices(
  input: { items: string[]; alternates: string[]; solicitationVersion: number }, deps: PriceDeps,
): Promise<SavePricesResult> {
  if (!Number.isInteger(input.solicitationVersion)) throw new Error("invalid_state");
  const current = await deps.draftVersion();
  if (current !== null && current !== input.solicitationVersion) {
    if (current < 2) throw new Error("invalid_state");
    return { ok: false, stale: true, message: pricesClearedNotice(current - 1) };
  }
  const schedule = await deps.schedule();
  if (!schedule) throw new Error("not_found");
  const items = parsePriceInputs(input.items, schedule.items, "Item");
  if (!items.ok) return items;
  const alternates = parsePriceInputs(input.alternates, schedule.alternates, "Alternate");
  if (!alternates.ok) return alternates;
  await deps.save(items.cents, alternates.cents);
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------
export interface FileDeps {
  /** The draft's current path for the slot, or null. */
  existingPath(bidId: string, slot: UploadSlot): Promise<string | null>;
  /** Deletes the Storage object. It only takes effect while the slot row still exists (see runAttachFile). */
  removeObject(path: string): Promise<void>;
  deleteRow(bidId: string, slot: UploadSlot): Promise<void>;
  insertRow(bidId: string, slot: UploadSlot, path: string, fileName: string): Promise<void>;
}

/**
 * Replaces the slot's file. Storage deletes run `delete ... returning`, which needs the SELECT policy, and that
 * policy needs the draft's slot row: with the row gone the delete silently removes nothing (verified over HTTP).
 * So the old object goes first, then its row, then the new row. A failed object delete is not fatal.
 */
export async function runAttachFile(
  bidId: string, slot: string, path: string, fileName: string, deps: FileDeps,
): Promise<BidActionResult> {
  if (!isUploadSlot(slot)) throw new Error("invalid_upload_slot");
  assertOwnBidPath(bidId, path);
  const existing = await deps.existingPath(bidId, slot);
  if (existing !== null) {
    try {
      await deps.removeObject(existing);
    } catch (e) {
      console.error("old bid file could not be removed from storage", e);
    }
    await deps.deleteRow(bidId, slot);
  }
  await deps.insertRow(bidId, slot, path, displayFileName(fileName));
  return { ok: true };
}

export async function runRemoveFile(bidId: string, slot: string, deps: FileDeps): Promise<BidActionResult> {
  if (!isUploadSlot(slot)) throw new Error("invalid_upload_slot");
  const existing = await deps.existingPath(bidId, slot);
  if (existing === null) return { ok: true };
  try {
    await deps.removeObject(existing);
  } catch (e) {
    console.error("bid file could not be removed from storage", e);
  }
  await deps.deleteRow(bidId, slot);
  return { ok: true };
}

/** Sets the bond choice. A leftover bond file is dropped unless the choice is electronic (it would be sealed too). */
export async function runSetBondChoice(
  bidId: string, choice: BidBondChoice | null,
  deps: FileDeps & { setChoice(bidId: string, choice: BidBondChoice | null): Promise<void> },
): Promise<BidActionResult> {
  if (choice !== null && choice !== "electronic" && choice !== "paper") throw new Error("invalid_bid");
  await deps.setChoice(bidId, choice);
  if (choice !== "electronic") await runRemoveFile(bidId, "bid_bond", deps);
  return { ok: true };
}

/**
 * Sets (or clears, with null) the apprentice commitment answer on the draft. The update policy (own bid, bidding
 * open) does the enforcing; the validator and app.bid_draft_problems decide whether the solicitation asks for it.
 */
export async function runSetApprenticeCommitment(
  bidId: string, value: boolean | null,
  deps: { update(bidId: string, patch: { apprentice_commitment: boolean | null }): Promise<void> },
): Promise<BidActionResult> {
  if (!isUuid(bidId)) throw new Error("not_found");
  if (value !== null && value !== true && value !== false) throw new Error("invalid_bid");
  await deps.update(bidId, { apprentice_commitment: value });
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Data layer
// ---------------------------------------------------------------------------
/** Rows as the generated types describe them. item_cents can hold nulls even though it is typed number[]. */
export function toBidDraft(
  bid: { id: string; reference: string },
  draft: {
    version: number; item_cents: number[]; alternate_cents: number[]; bid_bond_choice: BidBondChoice | null;
    apprentice_commitment: boolean | null;
  },
  files: { slot: UploadSlot; path: string; file_name: string }[],
): BidDraft {
  return {
    bidId: bid.id, reference: bid.reference, version: draft.version,
    itemCents: [...draft.item_cents] as (Cents | null)[],
    alternateCents: [...draft.alternate_cents] as (Cents | null)[],
    bidBondChoice: draft.bid_bond_choice,
    apprenticeCommitment: draft.apprentice_commitment,
    files: files.map((f) => ({ slot: f.slot, path: f.path, fileName: f.file_name })),
  };
}

export interface BidReceipt {
  reference: string; version: number; submittedAt: string; withdrawnAt: string | null; isCurrent: boolean;
}

/** my_bid_receipts rows. The generated type says withdrawn_at is a string, but it is null until withdrawn. */
export function toReceipts(
  rows: { reference: string; version: number; submitted_at: string; withdrawn_at: string; is_current: boolean }[],
): BidReceipt[] {
  return rows.map((r) => ({
    reference: r.reference, version: r.version, submittedAt: r.submitted_at,
    withdrawnAt: (r.withdrawn_at as string | null) ?? null, isCurrent: r.is_current,
  }));
}

// ---------------------------------------------------------------------------
// Submit, receipts and closed state
// ---------------------------------------------------------------------------
export type BiddingState = "open" | "closed" | "not_open";

/** The database's bidding_state answer; anything unexpected fails safe to not_open. */
export function parseBiddingState(v: unknown): BiddingState {
  return v === "open" || v === "closed" ? v : "not_open";
}

/**
 * Words a write the caller's RLS refused, from what the database says (never the web server's clock): an
 * invisible bid is not_found; otherwise the database's bidding_state decides closed or not open; with bidding
 * open, a missing draft is invalid_state.
 */
export function denialFrom(seen: { bidVisible: boolean; state: BiddingState; hasDraft: boolean }): string {
  if (!seen.bidVisible) return "not_found";
  if (seen.state === "closed") return "bids_closed";
  if (seen.state === "not_open") return "not_open";
  return seen.hasDraft ? "not_open" : "invalid_state";
}

export interface SubmitBidDeps {
  loadDraft(bidId: string): Promise<{ draft: BidDraft; data: SolicitationData } | null>;
  submit(bidId: string): Promise<BidReceipt>;
}

/**
 * Re-validates the stored draft (never client data), then asks the database to submit. The database re-checks
 * everything and the clock; this only avoids a round trip that is certain to fail and words the refusal.
 */
export async function runSubmitBid(
  bidId: string, deps: SubmitBidDeps,
): Promise<BidActionResult<{ receipt: BidReceipt }> | { ok: false; message: string; issues: BidIssue[] }> {
  const loaded = await deps.loadDraft(bidId);
  if (!loaded) return { ok: false, message: MSG.notFound };
  const issues = validateBidDraft(loaded.draft, loaded.data);
  if (issues.length > 0) return { ok: false, message: MSG.invalidBid, issues };
  try {
    return { ok: true, receipt: await deps.submit(bidId) };
  } catch (e) {
    if (e instanceof Error && e.message === "invalid_bid") {
      return { ok: false, message: "The bid is incomplete. Reload the page and check every item." };
    }
    return { ok: false, message: bidMessageFor(e) };
  }
}

/** One receipt row: its line (time, reference, version; never prices) and its status. */
export function describeReceipt(r: BidReceipt, tz: string, notCounted = false): { line: string; status: string } {
  return {
    line: `Version ${r.version} · submitted ${formatInstant(r.submittedAt, tz)} · reference ${r.reference}`,
    status: r.withdrawnAt ? `withdrawn ${formatInstant(r.withdrawnAt, tz)}`
      : r.isCurrent ? (notCounted ? "Not counted" : "current") : "superseded",
  };
}

export const afterSubmitNotice = (version: number, due: string) =>
  `Mail the signed bid form showing bid version ${version}. It must be received by ${due}.`;
/** `current` is the version on file (latest, not withdrawn), or null when the latest version is withdrawn. */
export const replaceConfirmation = (current: number | null) =>
  current === null
    ? "You have no bid on file. The new version needs its own signed form, received by the bid due time."
    : `Replacing starts a new, empty draft. Version ${current} still counts until you submit the replacement, which needs its own signed form.`;
/** The replace confirmation for these receipts: worded by whether a version is on file (not by the latest one). */
export const replaceConfirmationFor = (receipts: { version: number; isCurrent: boolean }[]) =>
  replaceConfirmation(receipts.find((r) => r.isCurrent)?.version ?? null);
export const withdrawConfirmation = (version: number, due: string) =>
  `Withdraw version ${version}? It will not be opened. You can still submit a new version before ${due}.`;

/**
 * Which bid-page buttons are enabled. Presentation only: the server actions and the form route still validate.
 * The filled form prints the SAVED draft, so it needs every amount (items and alternates) entered and saved and,
 * because the signed original must match what will be sealed (Ruling 6), the bond choice when bonds are required
 * and the apprentice answer on a $1M+ solicitation. Submit also needs a draft with no validation issues. Unsaved
 * amounts disable both.
 */
export function bidButtonState(s: {
  readOnly: boolean;
  /** The amount inputs differ from what was last saved. */
  dirty: boolean;
  saving: boolean;
  /** Every item and alternate amount is filled in and a valid amount. */
  allAmountsEntered: boolean;
  /** At least one item exists on the schedule. */
  hasItems: boolean;
  issueCount: number;
  /** Bonds are required and no bond choice is saved. */
  bondChoiceMissing: boolean;
  /** The solicitation asks for the apprentice commitment and no answer is saved. */
  apprenticeAnswerMissing: boolean;
}): { canPrintForSignature: boolean; canSubmit: boolean } {
  const saved = !s.dirty && !s.saving;
  return {
    canPrintForSignature: saved && s.hasItems && s.allAmountsEntered && !s.bondChoiceMissing && !s.apprenticeAnswerMissing,
    canSubmit: !s.readOnly && saved && s.issueCount === 0,
  };
}

// ---------------------------------------------------------------------------
// Bid-bond cure (after close)
// ---------------------------------------------------------------------------
export type CureStatus = "not_required" | "ok" | "cured" | "pending" | "failed";
const CURE_STATUSES: readonly CureStatus[] = ["not_required", "ok", "cured", "pending", "failed"];

/** The database's my_bid_cure status; anything unexpected fails safe to not_required (nothing shown). */
export function parseCureStatus(v: unknown): CureStatus {
  return CURE_STATUSES.includes(v as CureStatus) ? (v as CureStatus) : "not_required";
}

/** The bidder-facing sentence for a cure status, or null when there is nothing to say. `due` is formatted. */
export function cureStatusText(status: CureStatus, due: string): string | null {
  switch (status) {
    case "pending": return `Your bid bond was not received. Upload it by ${due} or the bid will be disqualified.`;
    case "cured": return "Bid bond received during the cure period.";
    case "failed": return "Bid bond not received by the cure deadline. The bid is non-responsive.";
    default: return null;
  }
}

/** Plain-language text for a cure upload error. */
export function cureMessageFor(e: unknown): string {
  const code = e && typeof e === "object" && "message" in e ? String((e as { message: unknown }).message) : "";
  switch (code) {
    case "cure_closed": return "The cure deadline has passed.";
    case "invalid_state": return "This bid has no bond to cure.";
    case "invalid_data":
    case "invalid_bid": return MSG.upload;
  }
  return bidMessageFor(e);
}

/** Records the uploaded bond: the path must be under the caller's own bid; the database does every other check. */
export async function runSubmitCureBond(
  bidId: string, path: string, fileName: string,
  deps: { submit(bidId: string, path: string, fileName: string): Promise<string> },
): Promise<BidActionResult<{ uploadedAt: string }>> {
  assertOwnBidPath(bidId, path);
  return { ok: true, uploadedAt: await deps.submit(bidId, path, displayFileName(fileName)) };
}

// ---------------------------------------------------------------------------
// Addenda, acknowledgments and resubmit required (slice 2c)
// ---------------------------------------------------------------------------
export const resubmitBanner = (n: number) => `Resubmit required: Addendum ${n} changed the bid schedule.`;
export const acknowledgeBanner = (n: number) => `Addendum ${n} published. Acknowledge it before bids close.`;
export const pricesClearedNotice = (n: number) =>
  `Addendum ${n} changed the bid schedule, so your prices were cleared. Enter them again.`;
export const SUBMIT_ACK_WARNING = "Bids that don't acknowledge every addendum are flagged for the agency at close.";

/** One published addendum and whether this bid acknowledged it (my_bid_acknowledgments). */
export interface AckRow { addendumNumber: number; publishedAt: string | null; acknowledgedAt: string | null }
/** my_bid_status_addenda's row. */
export interface AddendaStatus { resubmitRequired: boolean; scheduleChangedIn: number | null; draftClearedBy: number | null }
export interface Banner { kind: "resubmit" | "acknowledge"; addendum: number; text: string }

/** my_bid_acknowledgments rows. The generated type says the timestamps are strings; acknowledged_at is null until acknowledged. */
export function toAcks(rows: { addendum_number: number; published_at: string; acknowledged_at: string }[]): AckRow[] {
  return rows.map((r) => ({
    addendumNumber: r.addendum_number,
    publishedAt: (r.published_at as string | null) ?? null,
    acknowledgedAt: (r.acknowledged_at as string | null) ?? null,
  }));
}

/** my_bid_status_addenda's single row (its ints are null when nothing applies), or null when none came back. */
export function toAddendaStatus(
  rows: { resubmit_required: boolean; schedule_changed_in: number; draft_cleared_by: number }[] | null,
): AddendaStatus | null {
  const r = rows?.[0];
  if (!r) return null;
  return {
    resubmitRequired: r.resubmit_required === true,
    scheduleChangedIn: (r.schedule_changed_in as number | null) ?? null,
    draftClearedBy: (r.draft_cleared_by as number | null) ?? null,
  };
}

/**
 * The banners above the bid while bidding is open: resubmit required first (keyed on resubmit_required only:
 * schedule_changed_in is also set for a withdrawn stale version), then one per unacknowledged addendum. None
 * after close, when neither can be acted on.
 */
export function addendaBanners(acks: AckRow[], status: AddendaStatus | null, open: boolean): Banner[] {
  if (!open) return [];
  const out: Banner[] = [];
  if (status?.resubmitRequired && status.scheduleChangedIn !== null) {
    out.push({ kind: "resubmit", addendum: status.scheduleChangedIn, text: resubmitBanner(status.scheduleChangedIn) });
  }
  for (const a of acks) {
    if (a.acknowledgedAt === null) {
      out.push({ kind: "acknowledge", addendum: a.addendumNumber, text: acknowledgeBanner(a.addendumNumber) });
    }
  }
  return out;
}

/** The prices-cleared notice above the price inputs, while they can still be entered. */
export function pricesClearedFor(status: AddendaStatus | null, open: boolean): string | null {
  return open && status?.draftClearedBy != null ? pricesClearedNotice(status.draftClearedBy) : null;
}

/** Acknowledges a published addendum; the database checks the bid, the addendum and the clock. */
export async function runAcknowledge(
  bidId: string, addendumNumber: number, deps: { acknowledge(bidId: string, n: number): Promise<void> },
): Promise<BidActionResult> {
  if (!isUuid(bidId) || !Number.isInteger(addendumNumber) || addendumNumber < 1) throw new Error("not_found");
  await deps.acknowledge(bidId, addendumNumber);
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Questions (slice 2c)
// ---------------------------------------------------------------------------
export const QUESTION_MAX = 4000;
export const REFERENCE_MAX = 200;

/** One row of public.my_questions: the caller's organization's own questions. */
export interface MyQuestion {
  id: string; body: string; reference: string; askedAt: string; status: string;
  answeredInNumber: number | null; closeReason: string | null;
}

export function toMyQuestions(rows: {
  id: string; body: string; reference: string; asked_at: string; status: string; answered_in_number: number; close_reason: string;
}[]): MyQuestion[] {
  return rows.map((r) => ({
    id: r.id, body: r.body, reference: r.reference, askedAt: r.asked_at, status: r.status,
    answeredInNumber: (r.answered_in_number as number | null) ?? null,
    closeReason: (r.close_reason as string | null) ?? null,
  }));
}

const CLOSE_REASONS: Record<string, string> = { duplicate: "duplicate", out_of_scope: "out of scope" };

/** The status badge text for one of the bidder's questions. */
export function bidderQuestionStatus(q: Pick<MyQuestion, "status" | "answeredInNumber" | "closeReason">): string {
  if (q.status === "answered") return q.answeredInNumber ? `Answered in Addendum ${q.answeredInNumber}` : "Answered";
  if (q.status === "closed") return q.closeReason ? `Closed: ${CLOSE_REASONS[q.closeReason] ?? q.closeReason}` : "Closed";
  return "Open";
}

/**
 * Whether to show the ask form: before questionsDue (in the configured zone) and before bidding closes. This only
 * chooses what to show; ask_question judges the deadline on the database clock and refuses with questions_closed.
 */
export function questionsOpen(
  due: { date: string; time: string } | null, tz: string, now: Date, state: BiddingState,
): boolean {
  if (!due || state === "closed") return false;
  return now.getTime() < toUtc(due.date, due.time, tz).getTime();
}

export function questionsClosedText(due: { date: string; time: string } | null, tz: string): string {
  return due ? `Questions closed ${formatDateTime(due, tz)}` : "Questions closed";
}

/** Trims and bounds the question (1 to 4,000 characters) and reference (up to 200), then asks the database. */
export async function runAskQuestion(
  solicitationId: string, input: { body: string; reference: string },
  deps: { ask(solicitationId: string, body: string, reference: string): Promise<string> },
): Promise<BidActionResult> {
  if (!isUuid(solicitationId)) throw new Error("not_found");
  const body = String(input?.body ?? "").trim();
  const reference = String(input?.reference ?? "").trim();
  if (body.length < 1 || body.length > QUESTION_MAX || reference.length > REFERENCE_MAX) {
    return { ok: false, message: MSG.invalidQuestion };
  }
  await deps.ask(solicitationId, body, reference);
  return { ok: true };
}
