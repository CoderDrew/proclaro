/** The badge key for a bid receipt. The visible label stays the receipt's own status text (which carries the withdrawn time). */
export type ReceiptKey = "withdrawn" | "current" | "superseded";

export function receiptKey(r: { withdrawn: boolean; isCurrent: boolean }): ReceiptKey {
  return r.withdrawn ? "withdrawn" : r.isCurrent ? "current" : "superseded";
}
