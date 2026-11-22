// Scoring for the AI check evaluation. A false "met" (the check passed something it shouldn't) is the costly error and
// is reported separately from a false "not met". "unclear" when the truth is not_met is a safe miss, counted apart.
export type Result = "met" | "not_met" | "unclear";

export interface Case { code: string; expected: Result; actual: Result }

export interface Tally { total: number; correct: number; falseMet: number; falseNotMet: number; unclear: number }

export interface Score extends Tally {
  /** False met / cases whose truth is not met (not_met or unclear). */
  falseMetRate: number;
  /** False not met / cases whose truth is met. */
  falseNotMetRate: number;
  byCode: Record<string, Tally>;
}

const empty = (): Tally => ({ total: 0, correct: 0, falseMet: 0, falseNotMet: 0, unclear: 0 });

function add(t: Tally, c: Case) {
  t.total++;
  if (c.actual === c.expected) t.correct++;
  else if (c.actual === "met") t.falseMet++;
  else if (c.actual === "not_met" && c.expected === "met") t.falseNotMet++;
  else if (c.actual === "unclear") t.unclear++;
}

export function score(cases: Case[]): Score {
  const all = empty();
  const byCode: Record<string, Tally> = {};
  for (const c of cases) {
    add(all, c);
    add((byCode[c.code] ??= empty()), c);
  }
  const shouldNotMeet = cases.filter((c) => c.expected !== "met").length;
  const shouldMeet = cases.filter((c) => c.expected === "met").length;
  return {
    ...all,
    falseMetRate: shouldNotMeet === 0 ? 0 : all.falseMet / shouldNotMeet,
    falseNotMetRate: shouldMeet === 0 ? 0 : all.falseNotMet / shouldMeet,
    byCode,
  };
}
