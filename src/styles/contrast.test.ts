import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { contrastRatio, readTokens } from "./contrast";

const tokens = readTokens(readFileSync(join(__dirname, "tokens.css"), "utf8"));
const t = (name: string) => {
  const v = tokens[name];
  if (!v) throw new Error(`token --${name} missing`);
  return v;
};

describe("contrastRatio", () => {
  it("matches known values", () => {
    expect(contrastRatio("#000000", "#ffffff")).toBeCloseTo(21, 2);
    expect(contrastRatio("#777777", "#ffffff")).toBeCloseTo(4.48, 2);
  });
});

describe("token contrast (WCAG AA)", () => {
  const text: [string, string][] = [
    ["color-text", "color-surface"],
    ["color-text", "color-page"],
    ["color-text-muted", "color-surface"],
    ["color-text-muted", "color-page"],
    ["color-accent", "color-surface"],
    ["color-accent", "color-page"],
    ["color-on-accent", "color-accent"],
    ["color-on-accent", "color-accent-hover"],
    ["color-on-accent", "color-danger-solid"],
    ["color-disabled-text", "color-disabled-bg"],
    ["color-danger-text", "color-page"],
    ["color-danger-text", "color-surface"],
    ["color-warning-text", "color-surface"],
    ...["success", "danger", "warning", "neutral", "info"].map(
      (n): [string, string] => [`color-${n}-text`, `color-${n}-bg`],
    ),
  ];
  it.each(text)("%s on %s is at least 4.5:1", (fg, bg) => {
    expect(contrastRatio(t(fg), t(bg))).toBeGreaterThanOrEqual(4.5);
  });

  const ui: [string, string][] = [
    ["color-focus", "color-surface"],
    ["color-focus", "color-page"],
    ["color-control-border", "color-surface"],
  ];
  it.each(ui)("%s on %s is at least 3:1", (fg, bg) => {
    expect(contrastRatio(t(fg), t(bg))).toBeGreaterThanOrEqual(3);
  });
});
