// Rule comparisons for values the model extracted. Each returns true (met), false (not met) or null (unclear: the value
// is missing or can't be read). Never guesses "met".

const SUFFIXES = new Set(["llc", "inc", "incorporated", "co", "company", "corp", "corporation", "ltd", "limited"]);

function normalizeName(s: string): string[] {
  const words = s.toLowerCase().replace(/[.,'’&]/g, (c) => (c === "&" ? " and " : "")).split(/[^a-z0-9]+/)
    .filter((w) => w !== "");
  while (words.length > 1 && SUFFIXES.has(words[words.length - 1])) words.pop();
  return words;
}

export function namesMatch(a: string, b: string): boolean {
  const x = normalizeName(a);
  const y = normalizeName(b);
  return x.length > 0 && x.join(" ") === y.join(" ");
}

/** True when one name contains the other's words in order (an obligee "State of Calder, Department of X"). */
export function nameIncludes(haystack: string | null, needle: string): boolean | null {
  if (!haystack || haystack.trim() === "") return null;
  const h = ` ${normalizeName(haystack).join(" ")} `;
  const n = normalizeName(needle).join(" ");
  return n !== "" && h.includes(` ${n} `);
}

const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
  "november", "december"];

/** A date in YYYY-MM-DD, MM/DD/YYYY or "Month D, YYYY" form, as YYYY-MM-DD; null otherwise. */
export function parseDate(s: string | null): string | null {
  if (!s) return null;
  const t = s.trim();
  let y: number, m: number, d: number;
  let r = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(t);
  if (r) [y, m, d] = [Number(r[1]), Number(r[2]), Number(r[3])];
  else if ((r = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(t))) [m, d, y] = [Number(r[1]), Number(r[2]), Number(r[3])];
  else if ((r = /^([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})$/.exec(t))) {
    const mi = MONTHS.findIndex((mo) => mo.startsWith(r![1].toLowerCase().slice(0, 3)));
    if (mi < 0) return null;
    [m, d, y] = [mi + 1, Number(r[2]), Number(r[3])];
  } else return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

export function coversDate(from: string | null, to: string | null, dueLocalDate: string): boolean | null {
  const f = parseDate(from);
  const t = parseDate(to);
  if (!f || !t) return null;
  return f <= dueLocalDate && dueLocalDate <= t;
}

/** "YYYY-MM-DD to YYYY-MM-DD" (any of the date forms, separated by "to", "-" or "through") as a pair. */
export function splitRange(s: string | null): [string | null, string | null] {
  if (!s) return [null, null];
  const parts = s.split(/\s+(?:to|through|thru|–|—|-)\s+/i);
  return parts.length === 2 ? [parts[0], parts[1]] : [null, null];
}

const NONE = /^(none|n\/a|na|no addenda|0)$/;

/** The addendum numbers on an acknowledgment line: dates are dropped, and ranges ("1 through 3", "1-3") expanded. */
export function addendaNumbers(listed: string): number[] | null {
  const t = listed.trim().toLowerCase();
  if (NONE.test(t)) return [];
  const noDates = t
    .replace(/\d{1,2}\/\d{1,2}\/\d{2,4}/g, " ")
    .replace(/\d{4}-\d{1,2}-\d{1,2}/g, " ")
    .replace(/(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}/g, " ");
  const nums: number[] = [];
  const rest = noDates.replace(/(\d+)\s*(?:-|–|—|through|thru|to)\s*(\d+)/g, (_m, a: string, b: string) => {
    const [lo, hi] = [Number(a), Number(b)];
    if (hi >= lo && hi - lo <= 50) for (let n = lo; n <= hi; n++) nums.push(n);
    return " ";
  });
  for (const m of rest.matchAll(/\d+/g)) nums.push(Number(m[0]));
  return nums.length === 0 ? null : [...new Set(nums)].sort((x, y) => x - y);
}

export function addendaMatch(listed: string | null, published: number[]): boolean | null {
  if (listed === null || listed.trim() === "") return null;
  const a = addendaNumbers(listed);
  if (a === null) return null;
  const b = [...new Set(published)].sort((x, y) => x - y);
  return a.length === b.length && a.every((n, i) => n === b[i]);
}

export function versionMatch(extracted: string | null, submitted: number): boolean | null {
  if (!extracted) return null;
  const m = /(?:version|ver\.?|v)\s*(\d+)/i.exec(extracted) ?? /^\s*(\d+)\s*$/.exec(extracted);
  return m ? Number(m[1]) === submitted : null;
}

export function certificateMatch(extracted: string | null, claimed: string): boolean | null {
  if (!extracted || extracted.trim() === "") return null;
  const norm = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, "");
  return norm(extracted) === norm(claimed);
}
