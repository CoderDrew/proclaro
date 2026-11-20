import { describe, expect, it, vi } from "vitest";
import { ctxWith } from "@/documents/testFixtures";
import type { DocContext } from "@/documents/clauses";
import type { PdfRenderer } from "@/documents/pdf";
import type { SolicitationData } from "@/domain/solicitation/types";
import { publishSolicitation, putObject, type PublishDeps } from "./publish";

const ID = "11111111-1111-4111-8111-111111111111";
const ME = "22222222-2222-4222-8222-222222222222";
const NOW = new Date("2026-08-04T01:00:00Z"); // still Aug 3 in America/Denver

function validData(over: Partial<SolicitationData> = {}): SolicitationData {
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
    attachments: [
      { kind: "plans", label: "Roof plans", storagePath: `solicitations/${ID}/ab12cd34-plans.pdf`, issueDate: "2026-07-20" },
      { kind: "specifications", label: "Project manual", storagePath: `solicitations/${ID}/ef56ab78-spec.pdf`, issueDate: "2026-07-20" },
      { kind: "sample_contract", label: "Sample contract", storagePath: `solicitations/${ID}/aa11bb22-contract.pdf`, issueDate: null },
      { kind: "prevailing_wage", label: "Wage rates", storagePath: `solicitations/${ID}/cc33dd44-wages.pdf`, issueDate: null },
    ],
    ...over,
  }).data;
}

function makeDeps(opts: {
  data?: SolicitationData;
  state?: string;
  reviewerId?: string | null;
  checkerId?: string | null;
  rpcError?: Error;
  uploadFailsOn?: string;
  /** The stored data failed the schema (loadRow reports null). */
  storedInvalid?: boolean;
} = {}) {
  const data = opts.data ?? validData();
  const uploaded: { path: string; type: string }[] = [];
  const removed: string[][] = [];
  const copies: { from: string; to: string }[] = [];
  const rpc = vi.fn(async (args: Record<string, unknown>) => {
    void args;
    if (opts.rpcError) throw opts.rpcError;
  });
  const renderer: PdfRenderer = {
    render: vi.fn(async (html: string) => new TextEncoder().encode(`pdf:${html.length}`)),
  };
  const ctx: DocContext = {
    ...ctxWith(300_000_00, {}, { number: "27-0007", version: null }),
    data,
  };
  const docCtx = vi.fn(async (id: string) => { void id; return ctx; });
  const deps: PublishDeps = {
    now: () => NOW,
    viewerId: ME,
    renderer,
    async loadRow() {
      return {
        state: opts.state ?? "approved",
        reviewerId: opts.reviewerId === undefined ? ME : opts.reviewerId,
        checkerId: opts.checkerId ?? null,
        latestSubmittedAt: "2026-07-20T18:00:00Z",
        data: opts.storedInvalid ? null : data,
      };
    },
    async settings() { return { tz: "America/Denver", holidays: [] }; },
    loadDocContext: docCtx,
    storage: {
      async put(path, _bytes, type) {
        if (opts.uploadFailsOn && path.endsWith(opts.uploadFailsOn)) throw new Error("upload_failed");
        uploaded.push({ path, type });
      },
      async copyAttachment(from, to) { copies.push({ from, to }); uploaded.push({ path: to, type: "copy" }); },
      async remove(paths) { removed.push(paths); },
    },
    publishRpc: rpc,
  };
  return { deps, uploaded, removed, copies, rpc, renderer, docCtx };
}

describe("publishSolicitation", () => {
  it("allows a release date that is still today in the configured zone, though UTC has rolled over", async () => {
    const t = makeDeps({ data: validData({ releaseDate: "2026-08-03" }) });
    const r = await publishSolicitation(ID, t.deps);
    expect(r).toEqual({ ok: true, number: "27-0007" });
  });

  it("refuses a release date that has passed with release_too_soon", async () => {
    const t = makeDeps({ data: validData({ releaseDate: "2026-08-02" }) });
    const r = await publishSolicitation(ID, t.deps);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    const issue = r.errors.find((e) => e.code === "release_too_soon"
      && e.message === "Release date has passed; correct the dates before publishing");
    expect(issue).toBeDefined();
    expect(t.uploaded).toEqual([]);
    expect(t.rpc).not.toHaveBeenCalled();
  });

  it("returns a typed error instead of throwing when the stored data is invalid", async () => {
    const t = makeDeps({ storedInvalid: true });
    const r = await publishSolicitation(ID, t.deps);
    expect(r).toEqual({ ok: false, message: "This solicitation's data is invalid; return it to the agency.", errors: [] });
    expect(t.uploaded).toEqual([]);
    expect(t.rpc).not.toHaveBeenCalled();
  });

  it("maps the database's path and bid-due refusals to messages", async () => {
    for (const code of ["invalid_paths", "bid_due_mismatch"]) {
      const r = await publishSolicitation(ID, makeDeps({ rpcError: new Error(code) }).deps);
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.message).not.toMatch(/something went wrong/i);
    }
  });

  it("refuses when the state is not approved", async () => {
    const t = makeDeps({ state: "in_check" });
    const r = await publishSolicitation(ID, t.deps);
    expect(r.ok).toBe(false);
    expect(t.uploaded).toEqual([]);
    expect(t.rpc).not.toHaveBeenCalled();
  });

  it("refuses a caller who is neither reviewer nor checker before rendering anything", async () => {
    const t = makeDeps({ reviewerId: "someone-else", checkerId: "another" });
    const r = await publishSolicitation(ID, t.deps);
    expect(r.ok).toBe(false);
    expect(t.renderer.render).not.toHaveBeenCalled();
    expect(t.rpc).not.toHaveBeenCalled();
  });

  it("allows the checker", async () => {
    const t = makeDeps({ reviewerId: "someone-else", checkerId: ME });
    expect((await publishSolicitation(ID, t.deps)).ok).toBe(true);
  });

  it("refuses when validation fails (missing field)", async () => {
    const t = makeDeps({ data: validData({ summary: "" }) });
    const r = await publishSolicitation(ID, t.deps);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.errors.some((e) => e.code === "required" && e.field === "summary")).toBe(true);
  });

  it("renders both documents as final, version 1, and uploads to the uuid-keyed v1 paths", async () => {
    const t = makeDeps();
    const r = await publishSolicitation(ID, t.deps);
    expect(r.ok).toBe(true);
    expect(t.docCtx).toHaveBeenCalledWith(ID);
    const calls = (t.renderer.render as ReturnType<typeof vi.fn>).mock.calls as [string, { footerTemplate?: string }][];
    expect(calls).toHaveLength(2);
    const [rfbHtml, rfbOpts] = calls[0];
    const [bidHtml, bidOpts] = calls[1];
    expect(rfbHtml).not.toContain("DRAFT");
    expect(rfbOpts.footerTemplate).toBeUndefined();
    expect(bidHtml).not.toContain("DRAFT");
    expect(bidOpts.footerTemplate).toContain("Solicitation 27-0007 · Version 1 · Page ");
    expect(bidOpts.footerTemplate).toContain("pageNumber");
    expect(bidOpts.footerTemplate).toContain("totalPages");
    expect(t.uploaded.filter((u) => u.type === "application/pdf").map((u) => u.path)).toEqual([
      `solicitations/${ID}/v1/rfb.pdf`,
      `solicitations/${ID}/v1/bid-form.pdf`,
    ]);
  });

  it("copies attachments into the published bucket and records the published paths in the snapshot", async () => {
    const t = makeDeps();
    await publishSolicitation(ID, t.deps);
    expect(t.copies).toEqual([
      { from: `solicitations/${ID}/ab12cd34-plans.pdf`, to: `solicitations/${ID}/v1/attachments/ab12cd34-plans.pdf` },
      { from: `solicitations/${ID}/ef56ab78-spec.pdf`, to: `solicitations/${ID}/v1/attachments/ef56ab78-spec.pdf` },
      { from: `solicitations/${ID}/aa11bb22-contract.pdf`, to: `solicitations/${ID}/v1/attachments/aa11bb22-contract.pdf` },
      { from: `solicitations/${ID}/cc33dd44-wages.pdf`, to: `solicitations/${ID}/v1/attachments/cc33dd44-wages.pdf` },
    ]);
    const args = t.rpc.mock.calls[0][0] as { p_snapshot: { data: SolicitationData } };
    expect(args.p_snapshot.data.attachments.map((a) => a.storagePath)).toEqual([
      `solicitations/${ID}/v1/attachments/ab12cd34-plans.pdf`,
      `solicitations/${ID}/v1/attachments/ef56ab78-spec.pdf`,
      `solicitations/${ID}/v1/attachments/aa11bb22-contract.pdf`,
      `solicitations/${ID}/v1/attachments/cc33dd44-wages.pdf`,
    ]);
  });

  it("calls publish_solicitation with paths, snapshot and bid_due_at in UTC", async () => {
    const t = makeDeps();
    await publishSolicitation(ID, t.deps);
    expect(t.rpc).toHaveBeenCalledTimes(1);
    const a = t.rpc.mock.calls[0][0] as Record<string, unknown> & {
      p_snapshot: { data: unknown; clauses: unknown; settings: unknown; renderedAt: string };
    };
    expect(a.p_id).toBe(ID);
    expect(a.p_rfb_path).toBe(`solicitations/${ID}/v1/rfb.pdf`);
    expect(a.p_bid_form_path).toBe(`solicitations/${ID}/v1/bid-form.pdf`);
    expect(a.p_bid_due_at).toBe("2026-08-31T19:00:00.000Z");
    expect(Object.keys(a.p_snapshot).sort()).toEqual(["clauses", "data", "renderedAt", "settings"]);
    expect(a.p_snapshot.renderedAt).toBe(NOW.toISOString());
  });

  it("keeps the funding amount out of the public snapshot and sends it separately (Ruling 2)", async () => {
    const t = makeDeps({ data: validData({ fundingAmountCents: 31_000_000 }) });
    const r = await publishSolicitation(ID, t.deps);
    expect(r.ok).toBe(true);
    const a = t.rpc.mock.calls[0][0] as Record<string, unknown> & { p_snapshot: { data: Record<string, unknown> } };
    expect(a.p_funding_cents).toBe(31_000_000);
    expect("fundingAmountCents" in a.p_snapshot.data).toBe(false);
    expect(JSON.stringify(a.p_snapshot)).not.toContain("fundingAmountCents");
    expect(JSON.stringify(a.p_snapshot)).not.toContain("31000000");
  });

  it("deletes every upload, including copied attachments, when publish_solicitation fails", async () => {
    const t = makeDeps({ rpcError: new Error("invalid_state") });
    const r = await publishSolicitation(ID, t.deps);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.message).toMatch(/no longer in the right state/);
    expect(t.removed.flat().sort()).toEqual(t.uploaded.map((u) => u.path).sort());
    expect(t.removed.flat()).toContain(`solicitations/${ID}/v1/rfb.pdf`);
    expect(t.removed.flat()).toContain(`solicitations/${ID}/v1/bid-form.pdf`);
  });

  it("cleans up and does not call the database function when an upload fails", async () => {
    const t = makeDeps({ uploadFailsOn: "bid-form.pdf" });
    const r = await publishSolicitation(ID, t.deps);
    expect(r.ok).toBe(false);
    expect(t.rpc).not.toHaveBeenCalled();
    expect(t.removed.flat()).toContain(`solicitations/${ID}/v1/rfb.pdf`);
  });

  it("returns a typed failure, never throwing, when a dependency throws", async () => {
    const t = makeDeps();
    t.deps.loadDocContext = async () => { throw new Error("clause missing"); };
    const r = await publishSolicitation(ID, t.deps);
    expect(r.ok).toBe(false);
  });
});

describe("putObject", () => {
  function fakeBucket(existing: boolean) {
    const log: string[] = [];
    let present = existing;
    const bucket = {
      async upload(path: string, _b: Uint8Array, o: { upsert: boolean }) {
        log.push(`upload:${path}:upsert=${o.upsert}`);
        if (present) return { error: { message: "The resource already exists", statusCode: "409" } };
        present = true;
        return { error: null };
      },
      async remove(paths: string[]) { log.push(`remove:${paths.join(",")}`); present = false; return { error: null }; },
    };
    return { bucket, log };
  }

  it("uploads with upsert false", async () => {
    const { bucket, log } = fakeBucket(false);
    await putObject(bucket, "p", new Uint8Array(), "application/pdf");
    expect(log).toEqual(["upload:p:upsert=false"]);
  });

  it("deletes a leftover object from an earlier failed attempt, then writes", async () => {
    const { bucket, log } = fakeBucket(true);
    await putObject(bucket, "p", new Uint8Array(), "application/pdf");
    expect(log).toEqual(["upload:p:upsert=false", "remove:p", "upload:p:upsert=false"]);
  });
});
