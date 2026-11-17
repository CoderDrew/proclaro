export type Cents = number;

const MONEY_RE = /^\$?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?$/;

export function parseMoney(input: string): Cents | null {
  const m = MONEY_RE.exec(input.trim());
  if (!m) return null;
  const whole = Number(m[1].replace(/,/g, ""));
  const frac = Number((m[2] ?? "").padEnd(2, "0"));
  const cents = whole * 100 + frac;
  return Number.isSafeInteger(cents) ? cents : null;
}

export function formatMoney(c: Cents): string {
  const sign = c < 0 ? "-" : "";
  const abs = Math.abs(c);
  const dollars = Math.floor(abs / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `${sign}$${dollars}.${String(abs % 100).padStart(2, "0")}`;
}
