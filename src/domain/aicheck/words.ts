// An amount written in words, to integer cents. Null for anything it can't parse: the caller then reports "unclear",
// never "met".

const UNITS: Record<string, number> = {
  zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18,
  nineteen: 19, twenty: 20, thirty: 30, forty: 40, fourty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80,
  ninety: 90,
};
const SCALES: Record<string, number> = { thousand: 1_000, million: 1_000_000, billion: 1_000_000_000 };
const FILLER = new Set(["and", "only", "no", "exactly", "us", "usd", "the", "sum", "of"]);

/** Words for a whole number ("one million two hundred thousand"), or null. */
function wordsToNumber(text: string): number | null {
  const tokens = text.split(/\s+/).filter((t) => t !== "" && !FILLER.has(t));
  if (tokens.length === 0) return null;
  let total = 0;
  let current = 0;
  for (const t of tokens) {
    if (t in UNITS) current += UNITS[t];
    else if (t === "hundred") current = (current === 0 ? 1 : current) * 100;
    else if (t in SCALES) {
      total += (current === 0 ? 1 : current) * SCALES[t];
      current = 0;
    } else return null;
  }
  return total + current;
}

export function wordsToCents(text: string): number | null {
  if (!text) return null;
  let s = text.toLowerCase().replace(/[,.$]/g, " ").replace(/-/g, " ").replace(/\s+/g, " ").trim();
  let cents = 0;

  const fraction = /(\d{1,2})\s*\/\s*100/.exec(s);
  if (fraction) {
    cents = Number(fraction[1]);
    s = (s.slice(0, fraction.index) + " " + s.slice(fraction.index + fraction[0].length)).replace(/\bcents?\b/g, " ");
  }

  // After "dollars": nothing but filler, or (with no fraction) a number of cents.
  const [dollarPart, ...rest] = s.split(/\bdollars?\b/);
  const after = rest.join(" ").replace(/\b(and|only|no)\b/g, " ").trim();
  if (after !== "") {
    if (fraction || !/\bcents?\b/.test(after)) return null;
    const c = wordsToNumber(after.replace(/\bcents?\b/g, " ").trim());
    if (c === null || c > 99) return null;
    cents = c;
  }

  const dollars = wordsToNumber(dollarPart.trim());
  if (dollars === null) return null;
  return dollars * 100 + cents;
}
