import { describe, expect, it } from "vitest";
import {
  assertOwnBidPath, bidButtonState, bidMessageFor, bidUploadPath, parsePriceInputs, runAttachFile, runRemoveFile, runSavePrices,
  runSetBondChoice, toBidDraft, toReceipts, type FileDeps,
  afterSubmitNotice, denialFrom, describeReceipt, parseBiddingState, replaceConfirmation, replaceConfirmationFor, runSubmitBid, withdrawConfirmation,
  type SubmitBidDeps,
} from "./logic";
import type { BidDraft } from "@/domain/bid/types";
import type { SolicitationData } from "@/domain/solicitation/types";

const BID = "7d1c8a52-0000-4000-8000-000000000001";
const UPLOAD = "9b0f3e10-0000-4000-8000-0000000000aa";

describe("parsePriceInputs", () => {
  it("parses dollar amounts to cents", () => {
    expect(parsePriceInputs(["$125,000", "2,345.67"], 2)).toEqual({ ok: true, cents: [12_500_000, 234_567] });
  });
  it("turns blank inputs into null", () => {
    expect(parsePriceInputs(["", ""], 2)).toEqual({ ok: true, cents: [null, null] });
    expect(parsePriceInputs(["  ", "5"], 2)).toEqual({ ok: true, cents: [null, 500] });
  });
  it("names the bad input", () => {
    expect(parsePriceInputs(["12.345", ""], 2)).toEqual({
      ok: false, message: "Item 1: enter a dollar amount like 12,500.00",
    });
    expect(parsePriceInputs(["1", "abc"], 2, "Alternate")).toEqual({
      ok: false, message: "Alternate 2: enter a dollar amount like 12,500.00",
    });
  });
  it("refuses a negative amount", () => {
    expect(parsePriceInputs(["-5"], 1).ok).toBe(false);
  });
  it("refuses an amount above the maximum and accepts the maximum", () => {
    expect(parsePriceInputs(["9,999,999,999.99"], 1)).toEqual({ ok: true, cents: [999_999_999_999] });
    expect(parsePriceInputs(["10,000,000,000.00"], 1)).toEqual({
      ok: false, message: "Item 1: the amount is too large (the maximum is $9,999,999,999.99)",
    });
  });
  it("refuses a different number of inputs than the schedule has", () => {
    expect(parsePriceInputs(["1"], 2)).toEqual({ ok: false, message: "Enter one price for each item (2)." });
    expect(parsePriceInputs(["1", "2"], 1, "Alternate")).toEqual({ ok: false, message: "Enter one price for each alternate (1)." });
  });
  it("accepts no inputs for an empty schedule", () => {
    expect(parsePriceInputs([], 0)).toEqual({ ok: true, cents: [] });
  });
});

describe("bidUploadPath and assertOwnBidPath", () => {
  it("builds bids/{bid}/{upload}/{safe file name}", () => {
    expect(bidUploadPath(BID, UPLOAD, "My Insurance (final).pdf")).toBe(`bids/${BID}/${UPLOAD}/My_Insurance_final_.pdf`);
  });
  it("never lets a file name add a directory", () => {
    expect(bidUploadPath(BID, UPLOAD, "../../x.pdf")).toBe(`bids/${BID}/${UPLOAD}/x.pdf`);
  });
  it("accepts a path under the bid", () => {
    expect(() => assertOwnBidPath(BID, `bids/${BID}/${UPLOAD}/x.pdf`)).not.toThrow();
  });
  it("rejects another bid's path", () => {
    expect(() => assertOwnBidPath(BID, `bids/other/${UPLOAD}/x.pdf`)).toThrow("invalid_upload_path");
    expect(() => assertOwnBidPath(BID, `bids/7d1c8a52-0000-4000-8000-000000000002/${UPLOAD}/x.pdf`)).toThrow("invalid_upload_path");
  });
  it("rejects traversal, nesting, a missing upload folder and other buckets", () => {
    for (const p of [
      `bids/${BID}/${UPLOAD}/../x.pdf`, `bids/${BID}/${UPLOAD}/a/b.pdf`, `bids/${BID}/x.pdf`,
      `bids/${BID}/not-a-uuid/x.pdf`, `solicitations/${BID}/${UPLOAD}/x.pdf`, `/bids/${BID}/${UPLOAD}/x.pdf`, "",
    ]) {
      expect(() => assertOwnBidPath(BID, p), p).toThrow("invalid_upload_path");
    }
  });
});

describe("bidMessageFor", () => {
  it("maps the database error codes", () => {
    expect(bidMessageFor(new Error("bids_closed"))).toBe("Bidding on this solicitation has closed.");
    expect(bidMessageFor(new Error("not_open"))).toBe("This solicitation is not open for bidding.");
    expect(bidMessageFor(new Error("invalid_state"))).toBe("This bid is not in a state that allows that. Reload the page.");
    expect(bidMessageFor(new Error("invalid_bid"))).toBe("The bid is incomplete. Check the problems listed on the page.");
    expect(bidMessageFor(new Error("not_found"))).toBe("That bid or solicitation was not found.");
  });
  it("reads the code from a plain error object, as Supabase returns", () => {
    expect(bidMessageFor({ message: "bids_closed", code: "P0001" })).toBe("Bidding on this solicitation has closed.");
  });
  it("hides anything unexpected", () => {
    expect(bidMessageFor(new Error("relation \"bids\" does not exist"))).toBe("Something went wrong. Try again.");
    expect(bidMessageFor("boom")).toBe("Something went wrong. Try again.");
    expect(bidMessageFor(null)).toBe("Something went wrong. Try again.");
  });
});

describe("runSavePrices", () => {
  const schedule = { items: 2, alternates: 1 };
  it("parses both lists against the stored schedule and saves cents", async () => {
    const saved: unknown[] = [];
    const r = await runSavePrices(
      { items: ["125,000", "2,345.67"], alternates: ["15,000"] },
      { schedule: async () => schedule, save: async (i, a) => { saved.push([i, a]); } },
    );
    expect(r).toEqual({ ok: true });
    expect(saved).toEqual([[[12_500_000, 234_567], [1_500_000]]]);
  });
  it("saves blanks as null so the draft can be partly filled", async () => {
    const saved: unknown[] = [];
    await runSavePrices({ items: ["", "5"], alternates: [""] },
      { schedule: async () => schedule, save: async (i, a) => { saved.push([i, a]); } });
    expect(saved).toEqual([[[null, 500], [null]]]);
  });
  it("returns the input error without saving", async () => {
    let called = false;
    const r = await runSavePrices({ items: ["1", "x"], alternates: ["2"] },
      { schedule: async () => schedule, save: async () => { called = true; } });
    expect(r).toEqual({ ok: false, message: "Item 2: enter a dollar amount like 12,500.00" });
    expect(called).toBe(false);
  });
  it("labels alternate errors", async () => {
    const r = await runSavePrices({ items: ["1", "2"], alternates: ["x"] },
      { schedule: async () => schedule, save: async () => {} });
    expect(r).toEqual({ ok: false, message: "Alternate 1: enter a dollar amount like 12,500.00" });
  });
  it("is not_found when the solicitation is not visible", async () => {
    await expect(runSavePrices({ items: [], alternates: [] }, { schedule: async () => null, save: async () => {} }))
      .rejects.toThrow("not_found");
  });
});

function fileDeps(existing: string | null) {
  const calls: string[] = [];
  const deps: FileDeps = {
    existingPath: async () => existing,
    removeObject: async (p) => { calls.push(`removeObject ${p}`); },
    deleteRow: async (_b, slot) => { calls.push(`deleteRow ${slot}`); },
    insertRow: async (_b, slot, path, name) => { calls.push(`insertRow ${slot} ${path} ${name}`); },
  };
  return { calls, deps };
}

describe("runAttachFile", () => {
  const path = `bids/${BID}/${UPLOAD}/ins.pdf`;
  it("inserts the slot row for a new file", async () => {
    const { calls, deps } = fileDeps(null);
    expect(await runAttachFile(BID, "insurance", path, "ins.pdf", deps)).toEqual({ ok: true });
    expect(calls).toEqual([`insertRow insurance ${path} ins.pdf`]);
  });
  it("removes the old object while its row still exists, then the row, then inserts", async () => {
    // Storage deletes need the SELECT policy to see the row (verified over HTTP): object first, then row.
    const old = `bids/${BID}/${"1".repeat(8)}-0000-4000-8000-000000000001/old.pdf`;
    const { calls, deps } = fileDeps(old);
    await runAttachFile(BID, "insurance", path, "ins.pdf", deps);
    expect(calls).toEqual([`removeObject ${old}`, "deleteRow insurance", `insertRow insurance ${path} ins.pdf`]);
  });
  it("keeps going when removing the old object fails", async () => {
    const { calls, deps } = fileDeps("bids/x");
    deps.removeObject = async () => { throw new Error("storage down"); };
    expect(await runAttachFile(BID, "insurance", path, "ins.pdf", deps)).toEqual({ ok: true });
    expect(calls).toEqual(["deleteRow insurance", `insertRow insurance ${path} ins.pdf`]);
  });
  it("refuses a path outside the bid before touching anything", async () => {
    const { calls, deps } = fileDeps(null);
    await expect(runAttachFile(BID, "insurance", `bids/other/${UPLOAD}/x.pdf`, "x.pdf", deps)).rejects.toThrow("invalid_upload_path");
    expect(calls).toEqual([]);
  });
  it("refuses an unknown slot", async () => {
    const { deps } = fileDeps(null);
    await expect(runAttachFile(BID, "nope", path, "x.pdf", deps)).rejects.toThrow("invalid_upload_slot");
  });
  it("stores a safe display name", async () => {
    const { calls, deps } = fileDeps(null);
    await runAttachFile(BID, "insurance", path, "  C:\\docs\\Ins Certificate.pdf ", deps);
    expect(calls).toEqual([`insertRow insurance ${path} Ins Certificate.pdf`]);
  });
});

describe("runRemoveFile", () => {
  it("removes the object then the row", async () => {
    const { calls, deps } = fileDeps("bids/p");
    expect(await runRemoveFile(BID, "references", deps)).toEqual({ ok: true });
    expect(calls).toEqual(["removeObject bids/p", "deleteRow references"]);
  });
  it("does nothing when the slot is empty", async () => {
    const { calls, deps } = fileDeps(null);
    expect(await runRemoveFile(BID, "references", deps)).toEqual({ ok: true });
    expect(calls).toEqual([]);
  });
});

describe("runSetBondChoice", () => {
  it("drops a leftover bond file when the choice is not electronic", async () => {
    const { calls, deps } = fileDeps("bids/bond");
    const sets: unknown[] = [];
    const r = await runSetBondChoice(BID, "paper", { ...deps, setChoice: async (_b, c) => { sets.push(c); } });
    expect(r).toEqual({ ok: true });
    expect(sets).toEqual(["paper"]);
    expect(calls).toEqual(["removeObject bids/bond", "deleteRow bid_bond"]);
  });
  it("keeps the bond file for electronic", async () => {
    const { calls, deps } = fileDeps("bids/bond");
    await runSetBondChoice(BID, "electronic", { ...deps, setChoice: async () => {} });
    expect(calls).toEqual([]);
  });
  it("clears the choice with null and refuses a bad value", async () => {
    const { deps } = fileDeps(null);
    const sets: unknown[] = [];
    await runSetBondChoice(BID, null, { ...deps, setChoice: async (_b, c) => { sets.push(c); } });
    expect(sets).toEqual([null]);
    await expect(runSetBondChoice(BID, "cash" as never, { ...deps, setChoice: async () => {} })).rejects.toThrow("invalid_bid");
  });
});

describe("data mapping", () => {
  it("builds a BidDraft with cents and a version, keeping nulls", () => {
    const d = toBidDraft(
      { id: BID, reference: "K7QM-2XV0" },
      { version: 2, item_cents: [100, null] as unknown as number[], alternate_cents: [], bid_bond_choice: "paper" },
      [{ slot: "insurance", path: "p", file_name: "ins.pdf" }],
    );
    expect(d).toEqual({
      bidId: BID, reference: "K7QM-2XV0", version: 2, itemCents: [100, null], alternateCents: [],
      bidBondChoice: "paper", files: [{ slot: "insurance", path: "p", fileName: "ins.pdf" }],
    });
  });
  it("types withdrawn_at as string | null (the generated type says string)", () => {
    const rows = [
      { reference: "K7QM-2XV0", version: 1, submitted_at: "2026-11-20T10:00:00Z", withdrawn_at: null as unknown as string, is_current: false },
      { reference: "K7QM-2XV0", version: 2, submitted_at: "2026-11-21T10:00:00Z", withdrawn_at: "2026-11-22T10:00:00Z", is_current: false },
    ];
    const r = toReceipts(rows);
    const w: (string | null)[] = r.map((x) => x.withdrawnAt);
    expect(w).toEqual([null, "2026-11-22T10:00:00Z"]);
    expect(r[0]).toEqual({ reference: "K7QM-2XV0", version: 1, submittedAt: "2026-11-20T10:00:00Z", withdrawnAt: null, isCurrent: false });
  });
});

describe("bidMessageFor: upload errors", () => {
  it("words a path that was already submitted (23505)", () => {
    const m = bidMessageFor({ message: "path_already_submitted", code: "23505" });
    expect(m).toBe("That file was already submitted with an earlier version. Choose the file again to upload a fresh copy.");
  });
  it("words a Storage refusal and a Storage duplicate instead of showing the raw text", () => {
    expect(bidMessageFor({ message: "new row violates row-level security policy", statusCode: "403" }))
      .toBe("That upload was not accepted. Bidding may have closed. Reload the page.");
    expect(bidMessageFor({ message: "The resource already exists", statusCode: "409" }))
      .toBe("That file was already uploaded. Choose the file again.");
  });
  it("passes an already-worded message through unchanged", () => {
    expect(bidMessageFor(new Error("Bidding on this solicitation has closed."))).toBe("Bidding on this solicitation has closed.");
  });
});

describe("denialFrom", () => {
  it("words a refused write from the database's answer, not a clock", () => {
    expect(denialFrom({ bidVisible: false, state: "open", hasDraft: true })).toBe("not_found");
    expect(denialFrom({ bidVisible: true, state: "closed", hasDraft: true })).toBe("bids_closed");
    expect(denialFrom({ bidVisible: true, state: "closed", hasDraft: false })).toBe("bids_closed");
    expect(denialFrom({ bidVisible: true, state: "not_open", hasDraft: true })).toBe("not_open");
    expect(denialFrom({ bidVisible: true, state: "open", hasDraft: false })).toBe("invalid_state");
    expect(denialFrom({ bidVisible: true, state: "open", hasDraft: true })).toBe("not_open");
  });
});

describe("parseBiddingState", () => {
  it("accepts the three states and fails safe to not_open", () => {
    expect(parseBiddingState("open")).toBe("open");
    expect(parseBiddingState("closed")).toBe("closed");
    expect(parseBiddingState("not_open")).toBe("not_open");
    expect(parseBiddingState(null)).toBe("not_open");
    expect(parseBiddingState("whatever")).toBe("not_open");
  });
});

const DATA = {
  estimateCents: 15_000_000, optionalSections: ["references"],
  schedule: { items: [{ name: "Base", description: "" }, { name: "Two", description: "" }], alternates: [] },
} as unknown as SolicitationData;
const DRAFT: BidDraft = {
  bidId: BID, reference: "K7QM-2XV0", version: 1, itemCents: [100, 200], alternateCents: [], bidBondChoice: "paper",
  files: [{ slot: "insurance", path: "p1", fileName: "i.pdf" }, { slot: "references", path: "p2", fileName: "r.pdf" }],
};
const RECEIPT = { reference: "K7QM-2XV0", version: 1, submittedAt: "2026-11-20T17:00:00Z", withdrawnAt: null, isCurrent: true };

function submitDeps(draft: BidDraft | null, submit?: () => Promise<typeof RECEIPT>) {
  const calls = { submit: 0 };
  const deps: SubmitBidDeps = {
    async loadDraft() { return draft ? { draft, data: DATA } : null; },
    async submit() { calls.submit++; return submit ? submit() : RECEIPT; },
  };
  return { deps, calls };
}

describe("runSubmitBid", () => {
  it("returns the issues and never submits when a price is missing", async () => {
    const { deps, calls } = submitDeps({ ...DRAFT, itemCents: [100, null] });
    const r = await runSubmitBid(BID, deps);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r).toHaveProperty("issues");
    expect((r as { issues: { code: string }[] }).issues.map((i) => i.code)).toContain("price_missing");
    expect(calls.submit).toBe(0);
  });
  it("submits a clean draft once and returns the receipt", async () => {
    const { deps, calls } = submitDeps(DRAFT);
    expect(await runSubmitBid(BID, deps)).toEqual({ ok: true, receipt: RECEIPT });
    expect(calls.submit).toBe(1);
  });
  it("words bids_closed", async () => {
    const { deps } = submitDeps(DRAFT, async () => { throw new Error("bids_closed"); });
    expect(await runSubmitBid(BID, deps)).toEqual({ ok: false, message: "Bidding on this solicitation has closed." });
  });
  it("words invalid_bid", async () => {
    const { deps } = submitDeps(DRAFT, async () => { throw new Error("invalid_bid"); });
    expect(await runSubmitBid(BID, deps)).toEqual({
      ok: false, message: "The bid is incomplete. Reload the page and check every item.",
    });
  });
  it("is not_found when there is no draft", async () => {
    const { deps, calls } = submitDeps(null);
    expect(await runSubmitBid(BID, deps)).toEqual({ ok: false, message: "That bid or solicitation was not found." });
    expect(calls.submit).toBe(0);
  });
});

describe("receipt wording", () => {
  const tz = "America/Denver";
  it("describes a current, a superseded and a withdrawn version with no prices", () => {
    expect(describeReceipt(RECEIPT, tz)).toEqual({
      line: "Version 1 · submitted Nov 20, 2026, 10:00 AM MST · reference K7QM-2XV0", status: "current",
    });
    expect(describeReceipt({ ...RECEIPT, isCurrent: false }, tz).status).toBe("superseded");
    expect(describeReceipt({ ...RECEIPT, isCurrent: false, withdrawnAt: "2026-11-21T17:00:00Z" }, tz).status)
      .toBe("withdrawn Nov 21, 2026, 10:00 AM MST");
  });
  it("words the post-submit notice and the two confirmations", () => {
    expect(afterSubmitNotice(2, "Nov 30, 2026, 1:00 PM MST"))
      .toBe("Mail the signed bid form showing bid version 2. It must be received by Nov 30, 2026, 1:00 PM MST.");
    expect(replaceConfirmation(1))
      .toBe("Replacing starts a new, empty draft. Version 1 still counts until you submit the replacement, which needs its own signed form.");
    // After a withdrawal there is no current version: nothing "still counts".
    expect(replaceConfirmation(null))
      .toBe("You have no bid on file. The new version needs its own signed form, received by the bid due time.");
    // The panel's choice: v1 superseded by v2, v2 withdrawn -> no bid on file (the bug said "Version 2 still counts").
    expect(replaceConfirmationFor([{ version: 1, isCurrent: false }, { version: 2, isCurrent: false }]))
      .toBe("You have no bid on file. The new version needs its own signed form, received by the bid due time.");
    expect(replaceConfirmationFor([{ version: 1, isCurrent: false }, { version: 2, isCurrent: true }]))
      .toMatch(/^Replacing starts a new, empty draft\. Version 2 still counts/);
    expect(withdrawConfirmation(2, "Nov 30, 2026, 1:00 PM MST"))
      .toBe("Withdraw version 2? It will not be opened. You can still submit a new version before Nov 30, 2026, 1:00 PM MST.");
  });
});

describe("bidButtonState", () => {
  const base = { readOnly: false, dirty: false, saving: false, allAmountsEntered: true, hasItems: true, issueCount: 0 };
  it("enables both when everything is entered and saved", () => {
    expect(bidButtonState(base)).toEqual({ canPrintForSignature: true, canSubmit: true });
  });
  it("disables both while amounts are unsaved or saving", () => {
    expect(bidButtonState({ ...base, dirty: true })).toEqual({ canPrintForSignature: false, canSubmit: false });
    expect(bidButtonState({ ...base, saving: true })).toEqual({ canPrintForSignature: false, canSubmit: false });
  });
  it("disables both when an amount is missing", () => {
    expect(bidButtonState({ ...base, allAmountsEntered: false, issueCount: 1 })).toEqual({ canPrintForSignature: false, canSubmit: false });
  });
  it("lets a complete saved draft print while other issues (uploads) block submit", () => {
    expect(bidButtonState({ ...base, issueCount: 2 })).toEqual({ canPrintForSignature: true, canSubmit: false });
  });
  it("after close, a saved complete draft can still be printed but not submitted", () => {
    expect(bidButtonState({ ...base, readOnly: true })).toEqual({ canPrintForSignature: true, canSubmit: false });
  });
  it("needs at least one item", () => {
    expect(bidButtonState({ ...base, hasItems: false }).canPrintForSignature).toBe(false);
  });
});
