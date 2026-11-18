export function cx(...parts: (string | false | null | undefined)[]): string | undefined {
  return parts.filter(Boolean).join(" ") || undefined;
}

/** True for a non-empty string: hint and error text render only then (false and "" render nothing). */
export function hasText(v: unknown): v is string {
  return typeof v === "string" && v !== "";
}
