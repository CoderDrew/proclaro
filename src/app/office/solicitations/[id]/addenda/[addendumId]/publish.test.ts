import { describe, expect, it, vi } from "vitest";
import { ctxWith } from "@/documents/testFixtures";
import type { DocContext } from "@/documents/clauses";
import type { PdfRenderer } from "@/documents/pdf";
import type { SolicitationData } from "@/domain/solicitation/types";
import { INVALID_STORED_DATA, messageFor } from "../../logic";
import { publishAddendum, type PublishAddendumDeps } from "./publish";

const SID = "11111111-1111-4111-8111-111111111111";
const AID = "33333333-3333-4333-8333-333333333333";
const ME = "22222222-2222-4222-8222-222222222222";
const NOW = new Date("2026-08-20T18:00:00Z");
const V2 = `solicitations/${SID}/v2`;

const twoItems = { items: [{ name: "Dormitory A", description: "Roof" }, { name: "Dormitory B", description: "" }], alternates: [] };
const threeItems = { ...twoItems, items: [...twoItems.items, { name: "Dormitory C", description: "Roof" }] };

/** The addendum's data: attachments-bucket paths and the confidential funding amount, as start_addendum copies them. */
function addendumData(over: Partial<SolicitationData> = {}): SolicitationData {
  return ctxWith(300_000_00, {
    releaseDate: "2026-08-03",
    adStart: "2026-08-03",
    adEnd: "2026-08-31",
    questionsDue: { date: "2026-08-17", time: "13:00" },
    answersDue: { date: "2026-08-24", time: "13:00" },
    bidDueDate: "2026-08-31",
    bidDueTime: "13:00",
    tentativeAwardDate: "2026-09-15",
    estimatedStartDate: "2026-10-01",
    estimatedCompletionDate: "2027-03-01",
    newspapers: "Calder Daily Example",
    fundingAmountCents: 31_000_000,
    schedule: threeItems,
    attachments: [
      { kind: "plans", label: "Roof plans", storagePath: `solicitations/${SID}/ab12cd34-plans.pdf`, issueDate: "2026-07-20" },
      { kind: "specifications", label: "Project manual", storagePath: `solicitations/${SID}/ef56ab78-spec.pdf`, issueDate: "2026-07-20" },
      { kind: "plans", label: "Revised roof plans", storagePath: `solicitations/${SID}/9f9f9f9f-plans-r1.pdf`, issueDate: "2026-08-18" },
      { kind: "sample_contract", label: "Sample contract", storagePath: `solicitations/${SID}/aa11bb22-contract.pdf`, issueDate: null },
      { kind: "prevailing_wage", label: "Wage rates", storagePath: `solicitations/${SID}/cc33dd44-wages.pdf`, issueDate: null },
    ],
    ...over,
  }).data;
}

/** The current published v1 context: snapshot data (no funding, published attachment paths). */
function publishedCtx(): DocContext {
  const data = addendumData({
    schedule: twoItems,
    bidDueDate: "2026-08-27",
    fundingAmountCents: null,
    attachments: [
      { kind: "plans", label: "Roof plans", storagePath: `solicitations/${SID}/v1/attachments/ab12cd34-plans.pdf`, issueDate: "2026-07-20" },
    ],
  });
  return { ...ctxWith(300_000_00, {}, { number: "27-0007", version: 1 }), data };
}

function makeDeps(opts: {
  data?: SolicitationData | null;
  state?: string;
  reviewerId?: string | null;
  checkerId?: string | null;
  rpcError?: Error;
  uploadFailsOn?: string;
  leftovers?: string[];
  listFails?: boolean;
} = {}) {
  const log: string[] = [];
  const uploaded: { path: string; type: string }[] = [];
  const removed: string[][] = [];
  const copies: { from: string; to: string }[] = [];
  const rpc = vi.fn(async (args: Record<string, unknown>) => {
    void args;
    log.push("rpc");
    if (opts.rpcError) throw opts.rpcError;
    return 2;
  });
  const renderer: PdfRenderer = {
    render: vi.fn(async (html: string) => new TextEncoder().encode(`pdf:${html.length}`)),
  };
  const deps: PublishAddendumDeps = {
    now: () => NOW,
    viewerId: ME,
    renderer,
    async loadAddendum() {
      return {
        solicitationId: SID,
        number: 1,
        state: opts.state ?? "approved",
        reviewerId: opts.reviewerId === undefined ? ME : opts.reviewerId,
        checkerId: opts.checkerId ?? null,
        narrative: "Adds Dormitory C to the bid schedule.",
        data: opts.data === undefined ? addendumData() : opts.data,
      };
    },
    async settings() { return { tz: "America/Denver", holidays: [] }; },
    loadPublishedDocContext: vi.fn(async () => publishedCtx()),
    async loadAnswers() {
      return [{ publishedQuestion: "Is the roof membrane specified?", answer: "Yes, see section 07 54 00." }];
    },
    storage: {
      async put(path, _bytes, type) {
        log.push(`put:${path}`);
        if (opts.uploadFailsOn && path.endsWith(opts.uploadFailsOn)) throw new Error("upload_failed");
        uploaded.push({ path, type });
      },
      async copyAttachment(from, to) { log.push(`copy:${to}`); copies.push({ from, to }); uploaded.push({ path: to, type: "copy" }); },
      async remove(paths) { log.push(`remove:${paths.length}`); removed.push(paths); },
      async list(prefix) {
        log.push(`list:${prefix}`);
        if (opts.listFails) throw new Error("list_failed");
        return opts.leftovers ?? [];
      },
    },
    publishRpc: rpc,
  };
  return { deps, log, uploaded, removed, copies, rpc, renderer };
}

type RpcArgs = Record<string, unknown> & { p_snapshot: { data: Record<string, unknown> & SolicitationData } };
const rpcArgs = (t: ReturnType<typeof makeDeps>) => t.rpc.mock.calls[0][0] as RpcArgs;
const renders = (t: ReturnType<typeof makeDeps>) =>
  (t.renderer.render as ReturnType<typeof vi.fn>).mock.calls as [string, { footerTemplate?: string }][];

describe("publishAddendum", () => {
  it("uploads the three v2 PDFs, then calls publish_addendum with the funding sent separately", async () => {
    const t = makeDeps();
    const r = await publishAddendum(AID, t.deps);
    expect(r).toEqual({ ok: true, number: 1 });
    expect(t.uploaded.filter((u) => u.type === "application/pdf").map((u) => u.path)).toEqual([
      `${V2}/rfb.pdf`, `${V2}/bid-form.pdf`, `${V2}/addendum.pdf`,
    ]);
    expect(t.rpc).toHaveBeenCalledTimes(1);
    const a = rpcArgs(t);
    expect(a.p_addendum_id).toBe(AID);
    expect(a.p_rfb_path).toBe(`${V2}/rfb.pdf`);
    expect(a.p_bid_form_path).toBe(`${V2}/bid-form.pdf`);
    expect(a.p_addendum_path).toBe(`${V2}/addendum.pdf`);
    expect(a.p_bid_due_at).toBe("2026-08-31T19:00:00.000Z");
    expect(a.p_funding_cents).toBe(31_000_000);
    expect(JSON.stringify(a.p_snapshot)).not.toContain("fundingAmountCents");
    expect(JSON.stringify(a.p_snapshot)).not.toContain("31000000");
    expect(t.log.indexOf("rpc")).toBeGreaterThan(t.log.indexOf(`put:${V2}/addendum.pdf`));
  });

  it("snapshots the addendum data minus funding, with the attachments at their v2 published paths", async () => {
    const t = makeDeps();
    await publishAddendum(AID, t.deps);
    expect(t.copies).toEqual([
      { from: `solicitations/${SID}/ab12cd34-plans.pdf`, to: `${V2}/attachments/ab12cd34-plans.pdf` },
      { from: `solicitations/${SID}/ef56ab78-spec.pdf`, to: `${V2}/attachments/ef56ab78-spec.pdf` },
      { from: `solicitations/${SID}/9f9f9f9f-plans-r1.pdf`, to: `${V2}/attachments/9f9f9f9f-plans-r1.pdf` },
      { from: `solicitations/${SID}/aa11bb22-contract.pdf`, to: `${V2}/attachments/aa11bb22-contract.pdf` },
      { from: `solicitations/${SID}/cc33dd44-wages.pdf`, to: `${V2}/attachments/cc33dd44-wages.pdf` },
    ]);
    const { fundingAmountCents: _f, ...expected } = addendumData();
    void _f;
    const attachments = expected.attachments.map((x) => ({
      ...x, storagePath: x.storagePath.replace(`solicitations/${SID}/`, `${V2}/attachments/`),
    }));
    expect(rpcArgs(t).p_snapshot).toEqual({
      data: { ...expected, attachments },
      clauses: publishedCtx().clauses,
      settings: publishedCtx().settings,
      renderedAt: NOW.toISOString(),
    });
  });

  it("renders the RFB and bid form as version 2 and the addendum PDF with its changes and answers", async () => {
    const t = makeDeps();
    await publishAddendum(AID, t.deps);
    const calls = renders(t);
    expect(calls).toHaveLength(3);
    const [[rfb], [bidForm, bidOpts], [addendum, addOpts]] = calls;
    expect(rfb).toContain("Dormitory C");
    expect(rfb).not.toContain("DRAFT");
    expect(bidForm).toContain("Dormitory C");
    expect(bidOpts.footerTemplate).toContain("Solicitation 27-0007 · Version 2 · Page ");
    expect(addendum).toContain("Adds Dormitory C to the bid schedule.");
    expect(addendum).toContain("Item 3 added: Dormitory C: Roof");
    expect(addendum).toContain("Is the roof membrane specified?");
    expect(addendum).toContain("August 27, 2026, 1:00 PM MDT");
    expect(addendum).toContain("August 31, 2026, 1:00 PM MDT");
    expect(addendum).toContain("August 20, 2026");
    expect(addOpts.footerTemplate).toContain("Solicitation 27-0007 · Version 2 · Page ");
  });

  it("never prints the confidential funding amount in any of the three documents", async () => {
    const t = makeDeps();
    await publishAddendum(AID, t.deps);
    for (const [html] of renders(t)) {
      for (const s of ["31000000", "31,000,000", "310,000.00", "310000"]) expect(html).not.toContain(s);
    }
  });

  it("removes leftovers from an earlier crashed attempt before uploading (R18)", async () => {
    const t = makeDeps({ leftovers: [`${V2}/attachments/old.pdf`] });
    expect((await publishAddendum(AID, t.deps)).ok).toBe(true);
    expect(t.log[0]).toBe(`list:${V2}/attachments`);
    expect([...t.removed[0]].sort()).toEqual([
      `${V2}/addendum.pdf`, `${V2}/attachments/old.pdf`, `${V2}/bid-form.pdf`, `${V2}/rfb.pdf`,
    ]);
    expect(t.log.indexOf("remove:4")).toBeLessThan(t.log.findIndex((l) => l.startsWith("put:")));
  });

  it("still publishes when the leftover sweep fails", async () => {
    const t = makeDeps({ listFails: true });
    expect((await publishAddendum(AID, t.deps)).ok).toBe(true);
  });

  it("removes what it uploaded and returns the message when publish_addendum raises too_close", async () => {
    const t = makeDeps({ rpcError: new Error("too_close") });
    const r = await publishAddendum(AID, t.deps);
    expect(r).toEqual({ ok: false, message: messageFor(new Error("too_close")), errors: [] });
    const cleanup = t.removed[t.removed.length - 1];
    expect([...cleanup].sort()).toEqual(t.uploaded.map((u) => u.path).sort());
    expect(cleanup).toContain(`${V2}/addendum.pdf`);
    expect(cleanup).toContain(`${V2}/attachments/9f9f9f9f-plans-r1.pdf`);
  });

  it("cleans up and does not call the database when an upload fails", async () => {
    const t = makeDeps({ uploadFailsOn: "addendum.pdf" });
    const r = await publishAddendum(AID, t.deps);
    expect(r.ok).toBe(false);
    expect(t.rpc).not.toHaveBeenCalled();
    expect(t.removed[t.removed.length - 1]).toContain(`${V2}/rfb.pdf`);
  });

  it("returns the locked-field errors without rendering or uploading", async () => {
    const t = makeDeps({ data: addendumData({ newspapers: "Another Paper" }) });
    const r = await publishAddendum(AID, t.deps);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.errors).toEqual([expect.objectContaining({ code: "locked_field", field: "newspapers" })]);
    expect(t.renderer.render).not.toHaveBeenCalled();
    expect(t.uploaded).toEqual([]);
    expect(t.rpc).not.toHaveBeenCalled();
  });

  it("refuses a bid due time less than 5 days out before uploading", async () => {
    const t = makeDeps({ data: addendumData({ bidDueDate: "2026-08-24", answersDue: { date: "2026-08-18", time: "13:00" } }) });
    const r = await publishAddendum(AID, t.deps);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.errors.some((e) => e.code === "too_close")).toBe(true);
    expect(t.uploaded).toEqual([]);
  });

  it("refuses an addendum that is not approved, or a caller who is neither reviewer nor checker", async () => {
    for (const t of [makeDeps({ state: "in_check" }), makeDeps({ reviewerId: "x", checkerId: "y" })]) {
      expect((await publishAddendum(AID, t.deps)).ok).toBe(false);
      expect(t.renderer.render).not.toHaveBeenCalled();
      expect(t.rpc).not.toHaveBeenCalled();
    }
    expect((await publishAddendum(AID, makeDeps({ reviewerId: "x", checkerId: ME }).deps)).ok).toBe(true);
  });

  it("returns a typed error when the stored data is invalid", async () => {
    const t = makeDeps({ data: null });
    const r = await publishAddendum(AID, t.deps);
    expect(r).toEqual({ ok: false, message: INVALID_STORED_DATA, errors: [] });
    expect(t.renderer.render).not.toHaveBeenCalled();
    expect(t.uploaded).toEqual([]);
    expect(t.removed).toEqual([]);
    expect(t.rpc).not.toHaveBeenCalled();
  });
});

describe("messageFor (addenda and questions)", () => {
  it("has a specific message for every new database code", () => {
    for (const code of [
      "too_close", "locked_field", "stale_draft", "ack_missing", "questions_closed", "question_not_open",
      "question_in_addendum", "addendum_in_progress", "narrative_required", "invalid_question", "bids_closed",
    ]) {
      expect(messageFor(new Error(code)), code).not.toMatch(/something went wrong/i);
    }
  });
});
