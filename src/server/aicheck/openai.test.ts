import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

import { aiCheckConfig, checkDocument, DEFAULT_MODEL, type OpenAILike } from "./openai";
import { evaluate } from "@/domain/aicheck/evaluate";
import { CHECKLIST } from "@/domain/aicheck/checklist";

const PDF = new Uint8Array([0x25, 0x50, 0x44, 0x46]);

function fakeClient(reply: () => Promise<{ output_text: string }>) {
  const create = vi.fn().mockImplementation(reply);
  return { client: { responses: { create } } as unknown as OpenAILike, create };
}

describe("aiCheckConfig", () => {
  it("reads enabled, configured and the model from the environment", () => {
    expect(aiCheckConfig({ AI_CHECK_ENABLED: "1", OPENAI_API_KEY: "sk-test" }))
      .toEqual({ enabled: true, configured: true, model: DEFAULT_MODEL });
    expect(aiCheckConfig({ AI_CHECK_ENABLED: "true", OPENAI_MODEL: "x" }))
      .toEqual({ enabled: false, configured: false, model: "x" });
  });
});

describe("checkDocument", () => {
  it("sends the PDF as a file input with a strict schema listing exactly the kind's codes", async () => {
    const { client, create } = fakeClient(async () => ({ output_text: '{"items":[]}' }));
    const out = await checkDocument("insurance", PDF, { client, model: "m" });
    expect(out.failed).toBe(false);
    const params = create.mock.calls[0][0];
    const content = params.input[0].content;
    expect(content.some((c: { type: string; file_data?: string }) =>
      c.type === "input_file" && c.file_data?.startsWith("data:application/pdf;base64,"))).toBe(true);
    expect(params.text.format.type).toBe("json_schema");
    expect(params.text.format.strict).toBe(true);
    const codes = params.text.format.schema.properties.items.items.properties.code.enum;
    expect(codes).toEqual(CHECKLIST.insurance.map((i) => i.code));
    expect(params.instructions).toMatch(/untrusted/i);
    expect(params.model).toBe("m");
  });

  it("returns failed with an error class and never the key or text when the call throws", async () => {
    const { client } = fakeClient(async () => { throw Object.assign(new Error("401 sk-secret-key bad"), { status: 401 }); });
    const out = await checkDocument("insurance", PDF, { client, model: "m" });
    expect(out.failed).toBe(true);
    expect(out.errorClass).toBe("http_401");
    expect(JSON.stringify(out)).not.toContain("sk-secret");
  });

  it("garbage output becomes unclear items (Review Focus 1)", async () => {
    const { client } = fakeClient(async () => ({ output_text: "not json" }));
    const out = await checkDocument("signed_form", PDF, { client, model: "m" });
    const items = evaluate("signed_form", out.raw, {
      legalName: "X", baseTotalCents: 1, publishedAddenda: [], submittedFormVersion: 1, residentCertificate: null,
      agencyName: "Y", dueLocalDate: "2026-12-04",
    });
    expect(items.every((i) => i.result === "unclear")).toBe(true);
  });
});
