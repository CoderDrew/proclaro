// Live evaluation of the AI document check against fixtures/aicheck (planted defects). Calls the OpenAI API once per
// fixture, so it costs money: run it on purpose with `npm run aicheck:eval`, never in CI. It needs OPENAI_API_KEY (and
// optionally OPENAI_MODEL) in the environment, prints a per-item table with the false-met rate shown separately, and
// writes docs/evaluation/YYYY-MM-DD-aicheck.md.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { it } from "vitest";
import { aiCheckConfig, checkDocument } from "@/server/aicheck/openai";
import { evaluate, type Facts } from "@/domain/aicheck/evaluate";
import type { DocumentKind } from "@/domain/aicheck/checklist";
import { score, type Case, type Result } from "@/domain/aicheck/score";

interface Entry { file: string; kind: DocumentKind; facts: Facts; expected: Record<string, Result>; defect?: string }

const pct = (n: number) => `${(n * 100).toFixed(1)}%`;

it("evaluates the AI check against the planted-defect fixtures", async () => {
  if (!process.env.OPENAI_API_KEY) throw new Error("Set OPENAI_API_KEY to run the live evaluation.");
  const model = aiCheckConfig().model;
  const dir = join(process.cwd(), "fixtures", "aicheck");
  const entries: Entry[] = JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8"));
  console.log(`Evaluating ${entries.length} documents with ${model}: ${entries.length} model calls.`);

  const cases: (Case & { file: string })[] = [];
  const failures: string[] = [];
  for (const e of entries) {
    const res = await checkDocument(e.kind, readFileSync(join(dir, e.file)), { model });
    if (res.failed) failures.push(`${e.file}: ${res.errorClass}`);
    const items = evaluate(e.kind, res.raw, e.facts);
    for (const [code, expected] of Object.entries(e.expected)) {
      const actual = items.find((i) => i.code === code)?.result ?? "unclear";
      cases.push({ file: e.file, code, expected, actual });
    }
  }

  const s = score(cases);
  const date = new Date().toISOString().slice(0, 10);
  const lines = [
    `# AI document check evaluation, ${date}`,
    "",
    `Model: \`${model}\`. Documents: ${entries.length}. Items: ${s.total}. Failed calls: ${failures.length}.`,
    "",
    `- **False met rate: ${pct(s.falseMetRate)}** (${s.falseMet} of the items that should not pass). This is the costly error.`,
    `- False not-met rate: ${pct(s.falseNotMetRate)} (${s.falseNotMet} of the items that should pass).`,
    `- Correct: ${s.correct} of ${s.total}. Unclear where the truth was not met (a safe miss): ${s.unclear}.`,
    "",
    "| Item | Total | Correct | False met | False not met | Unclear |",
    "|---|---|---|---|---|---|",
    ...Object.entries(s.byCode).map(([c, t]) =>
      `| ${c} | ${t.total} | ${t.correct} | ${t.falseMet} | ${t.falseNotMet} | ${t.unclear} |`),
    "",
    "## Misses",
    "",
    ...cases.filter((c) => c.actual !== c.expected)
      .map((c) => `- ${c.file} · ${c.code}: expected ${c.expected}, got ${c.actual}`),
    ...(failures.length ? ["", "## Failed calls", "", ...failures.map((f) => `- ${f}`)] : []),
    "",
  ];
  mkdirSync(join(process.cwd(), "docs", "evaluation"), { recursive: true });
  const out = join(process.cwd(), "docs", "evaluation", `${date}-aicheck.md`);
  writeFileSync(out, lines.join("\n"));
  console.log(lines.join("\n"));
  console.log(`Wrote ${out}`);
});
