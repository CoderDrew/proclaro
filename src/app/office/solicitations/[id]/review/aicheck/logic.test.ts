import { describe, expect, it, vi } from "vitest";
import { PDFDocument } from "pdf-lib";
import {
  AI_CHECK_MESSAGES, checkOne, NOT_CONFIGURED, pageCount, scanProblem, startCheck, TURNED_OFF, type AiCheckDeps,
} from "./logic";
import type { Facts } from "@/domain/aicheck/evaluate";

const FACTS: Facts = {
  legalName: "Basalt Works Inc", baseTotalCents: 100000, publishedAddenda: [], submittedFormVersion: 1,
  residentCertificate: null, agencyName: "Calder Department of Corrections", dueLocalDate: "2026-12-04",
};
const BID = "00000000-0000-4000-8000-000000000001";
const RUN = "00000000-0000-4000-8000-000000000002";

function deps(over: Partial<AiCheckDeps> = {}): AiCheckDeps & { rpc: ReturnType<typeof vi.fn>; check: ReturnType<typeof vi.fn> } {
  return {
    config: () => ({ enabled: true, configured: true, model: "m" }),
    rpc: vi.fn().mockResolvedValue(null),
    download: vi.fn().mockResolvedValue(new Uint8Array([1])),
    check: vi.fn().mockResolvedValue({ raw: { items: [] }, failed: false }),
    facts: vi.fn().mockResolvedValue(FACTS),
    ...over,
  } as never;
}

describe("startCheck", () => {
  it("refuses when checks are turned off, without calling anything", async () => {
    const d = deps({ config: () => ({ enabled: false, configured: true, model: "m" }) });
    expect(await startCheck(BID, d)).toEqual({ ok: false, message: TURNED_OFF });
    expect(d.rpc).not.toHaveBeenCalled();
  });

  it("refuses when no key is configured, without a network call (Review Focus 5)", async () => {
    const d = deps({ config: () => ({ enabled: true, configured: false, model: "m" }) });
    expect(await startCheck(BID, d)).toEqual({ ok: false, message: NOT_CONFIGURED });
    expect(NOT_CONFIGURED).toBe("The AI check is not configured.");
    expect(d.rpc).not.toHaveBeenCalled();
    expect(d.check).not.toHaveBeenCalled();
  });

  it("starts a run and returns its documents", async () => {
    const d = deps();
    d.rpc.mockImplementation(async (fn: string) =>
      fn === "start_ai_check" ? RUN : [{ document_kind: "signed_form", path: null }, { document_kind: "insurance", path: "p" }]);
    expect(await startCheck(BID, d)).toEqual({ ok: true, runId: RUN,
      documents: [{ kind: "signed_form", path: null }, { kind: "insurance", path: "p" }] });
    expect(d.rpc).toHaveBeenCalledWith("start_ai_check", { p_bid_id: BID, p_model: "m" });
  });

  it("maps every database error code to its message", async () => {
    for (const code of Object.keys(AI_CHECK_MESSAGES)) {
      const d = deps({ rpc: vi.fn().mockRejectedValue(new Error(code)) as never });
      expect(await startCheck(BID, d)).toEqual({ ok: false, message: AI_CHECK_MESSAGES[code] });
    }
    expect(AI_CHECK_MESSAGES.ai_check_running).toBe("A check is already running for this bid.");
    expect(AI_CHECK_MESSAGES.ai_cap_reached).toBe("The check limit has been reached. Try again tomorrow.");
  });
});

describe("checkOne", () => {
  const SOL = "00000000-0000-4000-8000-000000000003";
  /** rpc: begin returns the run's own bid and solicitation; record resolves. */
  function rpcFor(begin: () => Promise<unknown> = async () => [{ bid_id: BID, solicitation_id: SOL }]) {
    return vi.fn().mockImplementation(async (fn: string) => (fn === "begin_ai_check_document" ? begin() : null));
  }
  const recorded = (d: { rpc: ReturnType<typeof vi.fn> }) =>
    d.rpc.mock.calls.find(([fn]) => fn === "record_ai_check_document")![1].p_items as Record<string, unknown>[];

  it("refuses when checks are turned off or not configured, before any database or model call (Critical #1)", async () => {
    for (const config of [{ enabled: false, configured: true, model: "m" }, { enabled: true, configured: false, model: "m" }]) {
      const d = deps({ config: () => config, rpc: rpcFor() as never });
      const r = await checkOne({ runId: RUN, kind: "insurance", path: "p" }, d);
      expect(r.ok).toBe(false);
      expect(d.rpc).not.toHaveBeenCalled();
      expect(d.download).not.toHaveBeenCalled();
      expect(d.check).not.toHaveBeenCalled();
    }
  });

  it("reserves the document before downloading or calling the model", async () => {
    const order: string[] = [];
    const d = deps({
      rpc: vi.fn().mockImplementation(async (fn: string) => {
        order.push(fn);
        return fn === "begin_ai_check_document" ? [{ bid_id: BID, solicitation_id: SOL }] : null;
      }) as never,
      download: vi.fn().mockImplementation(async () => { order.push("download"); return new Uint8Array([1]); }) as never,
      check: vi.fn().mockImplementation(async () => { order.push("check"); return { raw: { items: [] }, failed: false }; }) as never,
    });
    await checkOne({ runId: RUN, kind: "insurance", path: "p" }, d);
    expect(order).toEqual(["begin_ai_check_document", "download", "check", "record_ai_check_document"]);
    expect(d.rpc.mock.calls[0][1]).toEqual({ p_run_id: RUN, p_kind: "insurance", p_path: "p" });
  });

  it("never calls the model when the reservation is refused", async () => {
    const d = deps({ rpc: rpcFor(async () => { throw new Error("ai_cap_reached"); }) as never });
    const r = await checkOne({ runId: RUN, kind: "insurance", path: "p" }, d);
    expect(r).toEqual({ ok: false, message: AI_CHECK_MESSAGES.ai_cap_reached });
    expect(d.download).not.toHaveBeenCalled();
    expect(d.check).not.toHaveBeenCalled();
  });

  it("loads facts for the run's own bid, not ids from the client", async () => {
    const d = deps({ rpc: rpcFor() as never });
    await checkOne({ runId: RUN, kind: "insurance", path: "p" }, d);
    expect(d.facts).toHaveBeenCalledWith(BID, SOL);
  });

  it("records a missing scan as unclear with no model call", async () => {
    const d = deps({ rpc: rpcFor() as never });
    const r = await checkOne({ runId: RUN, kind: "signed_form", path: null }, d);
    expect(r).toEqual({ ok: true, callFailed: false });
    expect(d.check).not.toHaveBeenCalled();
    expect(recorded(d).every((i) => i.result === "unclear" && i.detail === "Scan not attached" && i.document_path === null))
      .toBe(true);
  });

  it("records a failed call as unclear items with call_failed and its error class", async () => {
    const d = deps({ rpc: rpcFor() as never,
      check: vi.fn().mockResolvedValue({ raw: null, failed: true, errorClass: "http_429" }) as never });
    const r = await checkOne({ runId: RUN, kind: "insurance", path: "p" }, d);
    expect(r).toEqual({ ok: true, callFailed: true });
    const items = recorded(d);
    expect(items.every((i) => i.result === "unclear" && i.call_failed === true)).toBe(true);
    expect(String(items[0].detail)).toContain("http_429");
  });

  it("records evaluated items with the document path", async () => {
    const d = deps({ rpc: rpcFor() as never, check: vi.fn().mockResolvedValue({ raw: { items: [
      { code: "insured_name", result: "met", page: 1, excerpt: "Insured: Basalt Works, Inc.", extracted: "Basalt Works, Inc." },
      { code: "coverage_dates", result: "met", page: 1, excerpt: "x", extracted: "2026-01-01 to 2026-11-30" },
    ] }, failed: false }) as never });
    await checkOne({ runId: RUN, kind: "insurance", path: "p" }, d);
    const items = recorded(d) as { item_code: string; result: string; document_path: string }[];
    expect(items.find((i) => i.item_code === "insured_name")?.result).toBe("met");
    expect(items.find((i) => i.item_code === "coverage_dates")?.result).toBe("not_met");
    expect(items.every((i) => i.document_path === "p")).toBe(true);
  });

  it("rejects an unknown kind, including prototype keys", async () => {
    const d = deps({ rpc: rpcFor() as never });
    for (const kind of ["toString", "nope"]) {
      expect((await checkOne({ runId: RUN, kind: kind as never, path: "p" }, d)).ok).toBe(false);
    }
    expect(d.rpc).not.toHaveBeenCalled();
  });
});

describe("scans", () => {
  it("counts PDF pages and refuses more than 30", async () => {
    const doc = await PDFDocument.create();
    for (let i = 0; i < 31; i++) doc.addPage();
    const bytes = await doc.save();
    expect(await pageCount(bytes)).toBe(31);
    expect(await scanProblem("scan.pdf", "application/pdf", bytes)).toBe("A scan can have at most 30 pages.");
  });
  it("refuses a non-PDF and accepts a small PDF", async () => {
    expect(await scanProblem("scan.png", "image/png", new Uint8Array([1]))).toBe("Attach the scan as a PDF.");
    const doc = await PDFDocument.create();
    doc.addPage();
    expect(await scanProblem("scan.pdf", "application/pdf", await doc.save())).toBeNull();
  });
});
