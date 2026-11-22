import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { CHECKLIST } from "./checklist";

interface Entry { file: string; kind: string; seed: string | null; expected: Record<string, string>; defect?: string }

const dir = join(process.cwd(), "fixtures", "aicheck");
const manifest = (): Entry[] => JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8"));

describe("AI check fixtures", () => {
  it("cover every checklist code with a met and a not_met case", () => {
    const codes = new Set(Object.values(CHECKLIST).flatMap((items) => items.map((i) => i.code)));
    for (const code of codes) {
      const results = manifest().flatMap((e) => (e.expected[code] ? [e.expected[code]] : []));
      expect(results, code).toContain("met");
      expect(results, code).toContain("not_met");
    }
  });

  it("carry the seed's planted defects", () => {
    const seed = manifest().filter((e) => e.seed);
    expect(seed.find((e) => e.file === "granite-insurance.pdf")?.expected.coverage_dates).toBe("not_met");
    expect(seed.find((e) => e.file === "juniper-signed-form.pdf")?.expected.amount_in_words).toBe("not_met");
    expect(seed.find((e) => e.file === "basalt-signed-form.pdf")?.expected.addenda_listed).toBe("not_met");
  });

  it("matches the sizes and MD5s seed.sql records for the insurance uploads", () => {
    const seed = readFileSync(join(process.cwd(), "supabase", "seed.sql"), "utf8");
    const rows = [...seed.matchAll(/\('([a-z]+)', '10000000-0000-0000-0000-0000000000\d\d'::uuid, (\d+), '([0-9a-f]{32})'/g)];
    expect(rows.map((r) => r[1])).toEqual(["ridgeback", "granite", "juniper", "basalt"]);
    for (const [, key, size, md5] of rows) {
      const bytes = readFileSync(join(dir, `${key}-insurance.pdf`));
      expect(bytes.byteLength, key).toBe(Number(size));
      expect(createHash("md5").update(bytes).digest("hex"), key).toBe(md5);
    }
  });

  it("has a PDF for every entry", () => {
    for (const e of manifest()) expect(existsSync(join(dir, e.file)), e.file).toBe(true);
  });
});
