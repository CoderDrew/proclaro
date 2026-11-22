export type StatusTone = "success" | "danger" | "warning" | "neutral";

export type DomainStatus =
  | { kind: "solicitation"; state: string }
  | { kind: "addendum"; state: string }
  | { kind: "bidding"; status: "Open" | "Closed" }
  | { kind: "bidVersion"; status: string }
  | { kind: "original"; received: boolean }
  | { kind: "files"; flags: string[] }
  | { kind: "file"; status: string }
  | { kind: "logEntry"; flag: "afterDue" }
  | { kind: "evaluation"; stage: string; awaitingAgency: boolean }
  | { kind: "review"; status: string }
  | { kind: "question"; status: string };

type Badge = { tone: StatusTone; label: string };

const SOLICITATION: Record<string, Badge> = {
  draft: { tone: "neutral", label: "Draft" },
  submitted: { tone: "warning", label: "Submitted" },
  in_review: { tone: "warning", label: "In review" },
  in_check: { tone: "warning", label: "In check" },
  approved: { tone: "success", label: "Approved" },
  published: { tone: "success", label: "Published" },
};

// Addenda share the solicitation workflow states, plus withdrawn (also shown for an unpublished addendum after close).
const ADDENDUM: Record<string, Badge> = { ...SOLICITATION, withdrawn: { tone: "neutral", label: "Withdrawn" } };

const EVALUATION: Record<string, Badge> = {
  bid_review: { tone: "warning", label: "Bid review" },
  recap_check: { tone: "warning", label: "Recap in check" },
  recap_posted: { tone: "warning", label: "Award pending" },
  award_check: { tone: "warning", label: "Award in check" },
  awarded: { tone: "success", label: "Awarded" },
  all_rejected: { tone: "danger", label: "All bids rejected" },
};

const REVIEW: Record<string, Badge> = {
  accepted: { tone: "success", label: "Accepted" },
  flagged: { tone: "warning", label: "Flagged for agency" },
  flag_accepted: { tone: "success", label: "Accepted by agency" },
  flag_rejected: { tone: "danger", label: "Rejected by agency" },
  non_responsive: { tone: "danger", label: "Non-responsive" },
  pending_cure: { tone: "warning", label: "Pending cure" },
  undecided: { tone: "neutral", label: "Not reviewed" },
};

const BID_VERSION: Record<string, StatusTone> = {
  current: "success",
  superseded: "neutral",
  withdrawn: "neutral",
  // The latest version was entered against a schedule an addendum changed: it does not count at close.
  not_counted: "danger",
  // office_bid_index (0035): same meaning, seen by the office before close. An original for it counts for nothing.
  resubmit_required: "danger",
};

const BID_VERSION_LABEL: Record<string, string> = {
  resubmit_required: "Resubmit required (not counted)",
};

// A bidder's question; the page passes the full label (e.g. "Answered in Addendum 2", "Closed: duplicate").
const QUESTION: Record<string, Badge> = {
  open: { tone: "warning", label: "Open" },
  answered: { tone: "success", label: "Answered" },
  closed: { tone: "neutral", label: "Closed" },
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
    case "addendum":
      return Object.hasOwn(ADDENDUM, s.state) ? ADDENDUM[s.state] : { tone: "neutral", label: readable(s.state) };
    case "bidding":
      return s.status === "Open"
        ? { tone: "success", label: "Open" }
        : { tone: "neutral", label: "Closed" };
    case "bidVersion":
      return {
        tone: Object.hasOwn(BID_VERSION, s.status) ? BID_VERSION[s.status] : "neutral",
        label: Object.hasOwn(BID_VERSION_LABEL, s.status) ? BID_VERSION_LABEL[s.status] : readable(s.status),
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
    case "evaluation":
      if (s.stage === "bid_review" && s.awaitingAgency) return { tone: "warning", label: "Awaiting agency" };
      return Object.hasOwn(EVALUATION, s.stage) ? EVALUATION[s.stage] : { tone: "neutral", label: readable(s.stage) };
    case "review":
      return Object.hasOwn(REVIEW, s.status) ? REVIEW[s.status] : { tone: "neutral", label: readable(s.status) };
    case "question":
      return Object.hasOwn(QUESTION, s.status) ? QUESTION[s.status] : { tone: "neutral", label: readable(s.status) };
    default:
      return { tone: "neutral", label: "Unknown" };
  }
}
