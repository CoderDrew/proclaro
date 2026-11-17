import type { SolicitationData } from "../domain/solicitation/types";
import { formatDate, formatDateTime, formatTimeWithZone, TBD } from "./format";

export interface DocContext {
  data: SolicitationData;
  number: string | null;
  version: number | null;
  settings: { stateName: string; officeName: string; timezone: string };
  agencyName: string;
  clauses: Record<string, string>;
}

export class UnknownClauseVariable extends Error {
  constructor(public readonly variable: string) {
    super(`UnknownClauseVariable: ${variable}`);
    this.name = "UnknownClauseVariable";
  }
}

const VAR_RE = /\{\{\s*(\w+)\s*\}\}/g;

function substitute(body: string, vars: Record<string, string>, map: (v: string) => string): string {
  return body.replace(VAR_RE, (_m, name: string) => {
    if (!Object.prototype.hasOwnProperty.call(vars, name)) throw new UnknownClauseVariable(name);
    return map(vars[name]);
  });
}

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** Replaces {{name}} with the HTML-escaped value. Throws UnknownClauseVariable for a name not in `vars`. */
export function renderClause(body: string, vars: Record<string, string>): string {
  return substitute(body, vars, escapeHtml);
}

export interface ClauseBlock { kind: "heading" | "paragraph"; text: string }

/**
 * Splits a clause body into blocks (blank-line separated; a block starting with "# " is a heading)
 * and substitutes variables as PLAIN text. Callers render the text through React, which escapes it,
 * so neither the body nor the variable values can inject markup.
 */
export function clauseBlocks(body: string, vars: Record<string, string>): ClauseBlock[] {
  return body
    .split(/\n\s*\n/)
    .map((raw) => raw.trim())
    .filter((raw) => raw.length > 0)
    .map((raw) => {
      const heading = raw.startsWith("# ");
      const text = substitute(heading ? raw.slice(2) : raw, vars, (v) => v);
      return { kind: heading ? "heading" : "paragraph", text } as ClauseBlock;
    });
}

/** The variables templates pass to every clause. */
export function clauseVars(ctx: DocContext): Record<string, string> {
  const { data, settings } = ctx;
  return {
    stateName: settings.stateName,
    officeName: settings.officeName,
    agencyName: ctx.agencyName,
    number: ctx.number ?? "(number to be assigned)",
    bidDueDate: formatDate(data.bidDueDate),
    bidDueTime: data.bidDueDate ? formatTimeWithZone(data.bidDueDate, data.bidDueTime, settings.timezone) : TBD,
    questionsDue: formatDateTime(data.questionsDue, settings.timezone),
    answersDue: formatDateTime(data.answersDue, settings.timezone),
    bidValidityDays: String(data.bidValidityDays),
  };
}
