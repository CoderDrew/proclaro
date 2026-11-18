export type StatusTone = "success" | "danger" | "warning" | "neutral";

export type DomainStatus =
  | { kind: "solicitation"; state: string }
  | { kind: "bidding"; status: "Open" | "Closed" }
  | { kind: "bidVersion"; status: string }
  | { kind: "original"; received: boolean }
  | { kind: "files"; flags: string[] }
  | { kind: "file"; status: string }
  | { kind: "logEntry"; flag: "afterDue" };

type Badge = { tone: StatusTone; label: string };

const SOLICITATION: Record<string, Badge> = {
  draft: { tone: "neutral", label: "Draft" },
  submitted: { tone: "warning", label: "Submitted" },
  in_review: { tone: "warning", label: "In review" },
  in_check: { tone: "warning", label: "In check" },
  approved: { tone: "success", label: "Approved" },
  published: { tone: "success", label: "Published" },
};

const BID_VERSION: Record<string, StatusTone> = {
  current: "success",
  superseded: "neutral",
  withdrawn: "neutral",
};

/** A label is never blank: an empty value reads "Unknown". */
function readable(s: string): string {
  return s.trim() === "" ? "Unknown" : s;
}

export function statusBadge(s: DomainStatus): Badge {
  switch (s.kind) {
    case "solicitation":
      return Object.hasOwn(SOLICITATION, s.state)
        ? SOLICITATION[s.state]
        : { tone: "neutral", label: readable(s.state) };
    case "bidding":
      return s.status === "Open"
        ? { tone: "success", label: "Open" }
        : { tone: "neutral", label: "Closed" };
    case "bidVersion":
      return {
        tone: Object.hasOwn(BID_VERSION, s.status) ? BID_VERSION[s.status] : "neutral",
        label: readable(s.status),
      };
    case "original":
      return s.received
        ? { tone: "success", label: "Received" }
        : { tone: "danger", label: "Non-responsive" };
    case "files":
      return s.flags.length === 0
        ? { tone: "success", label: "Unaltered" }
        : { tone: "danger", label: s.flags.join("; ") };
    case "file":
      return s.status === "ok"
        ? { tone: "success", label: "Unaltered" }
        : { tone: "danger", label: `${readable(s.status)} since submission` };
    case "logEntry":
      return { tone: "warning", label: "after the bid due time" };
    default:
      return { tone: "neutral", label: "Unknown" };
  }
}
