import { describe, expect, it, vi } from "vitest";
import {
  localInputValue, parseReceivedAt, parseVersion, runLogOriginal, runVoidOriginal, type OriginalsDeps,
} from "./logic";

const SOL = "11111111-1111-4111-8111-111111111111";
const ENTRY = "22222222-2222-4222-8222-222222222222";
const TZ = "America/Denver";
const NOW = new Date("2026-08-31T19:30:00Z");

function deps(over: Partial<OriginalsDeps> = {}) {
  return {
    now: () => NOW,
    tz: vi.fn(async () => TZ),
    call: vi.fn(async () => {}),
    ...over,
  } satisfies OriginalsDeps;
}

describe("parseReceivedAt", () => {
  it("reads a datetime-local value in the configured zone", () => {
    const r = parseReceivedAt("2026-08-31T12:59", TZ, NOW);
    expect(r).toEqual({ ok: true, at: new Date("2026-08-31T18:59:00.000Z") });
    if (r.ok) expect(r.at?.toISOString()).toBe("2026-08-31T18:59:00.000Z");
  });

  it("refuses a time in the future", () => {
    expect(parseReceivedAt("2026-08-31T12:59", TZ, new Date("2026-08-31T18:58:00Z")))
      .toEqual({ ok: false, message: "The received time can't be in the future." });
  });

  it("accepts the current minute", () => {
    expect(parseReceivedAt("2026-08-31T12:59", TZ, new Date("2026-08-31T18:59:00Z")).ok).toBe(true);
  });

  it("treats blank as null (the database uses now())", () => {
    expect(parseReceivedAt("", TZ, NOW)).toEqual({ ok: true, at: null });
    expect(parseReceivedAt("   ", TZ, NOW)).toEqual({ ok: true, at: null });
  });

  it("refuses a malformed value", () => {
    const r = parseReceivedAt("31/08/2026 12:59", TZ, NOW);
    expect(r.ok).toBe(false);
  });
});

describe("localInputValue", () => {
  it("is the current minute in the configured zone, and parses back to a time not in the future", () => {
    const now = new Date("2026-08-31T19:30:45Z");
    expect(localInputValue(now, TZ)).toBe("2026-08-31T13:30");
    expect(parseReceivedAt(localInputValue(now, TZ), TZ, now)).toEqual({ ok: true, at: new Date("2026-08-31T19:30:00Z") });
  });
});

describe("parseVersion", () => {
  it("accepts a positive whole number", () => {
    expect(parseVersion("1")).toBe(1);
    expect(parseVersion(" 12 ")).toBe(12);
  });

  it("refuses zero, words, decimals, negatives and huge numbers", () => {
    expect(parseVersion("0")).toBeNull();
    expect(parseVersion("x")).toBeNull();
    expect(parseVersion("1.5")).toBeNull();
    expect(parseVersion("-1")).toBeNull();
    expect(parseVersion("")).toBeNull();
    expect(parseVersion("99999999999")).toBeNull();
  });
});

describe("runLogOriginal", () => {
  const input = { reference: " k7qm 2xvd ", version: "2", item: "signed_form", receivedAt: "2026-08-31T12:59" };

  it("calls log_bid_original with the parsed values", async () => {
    const d = deps();
    expect(await runLogOriginal(SOL, input, d)).toEqual({ ok: true });
    expect(d.call).toHaveBeenCalledWith("log_bid_original", {
      p_solicitation_id: SOL, p_reference: "k7qm 2xvd", p_version: 2, p_item: "signed_form",
      p_received_at: "2026-08-31T18:59:00.000Z",
    });
  });

  it("omits the received time when blank, so the database uses now()", async () => {
    const d = deps();
    await runLogOriginal(SOL, { ...input, receivedAt: "" }, d);
    expect(d.call).toHaveBeenCalledWith("log_bid_original", {
      p_solicitation_id: SOL, p_reference: "k7qm 2xvd", p_version: 2, p_item: "signed_form",
    });
  });

  it("words unknown_bid with the reference and version", async () => {
    const d = deps({ call: vi.fn(async () => { throw new Error("unknown_bid"); }) });
    expect(await runLogOriginal(SOL, input, d))
      .toEqual({ ok: false, message: "No submitted bid K7QM-2XVD version 2 on this solicitation." });
  });

  it("words received_in_future from the database the same way", async () => {
    const d = deps({ call: vi.fn(async () => { throw new Error("received_in_future"); }) });
    expect(await runLogOriginal(SOL, input, d))
      .toEqual({ ok: false, message: "The received time can't be in the future." });
  });

  it("never calls the database for invalid input", async () => {
    const d = deps();
    for (const bad of [
      { ...input, reference: "  " },
      { ...input, version: "0" },
      { ...input, item: "cheque" },
      { ...input, receivedAt: "2026-08-31T13:31" },
    ]) {
      expect((await runLogOriginal(SOL, bad, d)).ok).toBe(false);
    }
    expect(d.call).not.toHaveBeenCalled();
  });
});

describe("runVoidOriginal", () => {
  it("never calls the database with a blank reason", async () => {
    const d = deps();
    expect(await runVoidOriginal(ENTRY, "   ", d)).toEqual({ ok: false, message: "Enter a reason for the void." });
    expect(d.call).not.toHaveBeenCalled();
  });

  it("calls void_bid_original with the trimmed reason", async () => {
    const d = deps();
    expect(await runVoidOriginal(ENTRY, "  Wrong version  ", d)).toEqual({ ok: true });
    expect(d.call).toHaveBeenCalledWith("void_bid_original", { p_entry_id: ENTRY, p_reason: "Wrong version" });
  });

  it("words already_voided and invalid_state", async () => {
    for (const [code, message] of [
      ["already_voided", "That entry has already been voided."],
      ["invalid_state", "A void can't be voided. Log the item again instead."],
      ["not_found", "That log entry was not found."],
    ] as const) {
      const d = deps({ call: vi.fn(async () => { throw new Error(code); }) });
      expect(await runVoidOriginal(ENTRY, "x", d)).toEqual({ ok: false, message });
    }
  });
});
