import type { Issue } from "@/domain/solicitation/validate";

export const ackKey = (i: Pick<Issue, "code" | "field">) => `${i.code}|${i.field}`;

/** Errors (red) or warnings (amber, with an Acknowledge button). */
export function IssueList({
  issues, kind, acked, onAck, disabled,
}: {
  issues: Issue[];
  kind: "error" | "warning";
  acked?: ReadonlySet<string>;
  onAck?: (issue: Issue) => void;
  disabled?: boolean;
}) {
  if (issues.length === 0) return null;
  return (
    <ul className={`issues issues-${kind}`}>
      {issues.map((i) => {
        const done = kind === "warning" && acked?.has(ackKey(i));
        return (
          <li key={ackKey(i) + i.message}>
            {i.message}
            {kind === "warning" && (done ? (
              <em> Acknowledged.</em>
            ) : onAck ? (
              <button type="button" disabled={disabled} onClick={() => onAck(i)}>Acknowledge</button>
            ) : null)}
          </li>
        );
      })}
    </ul>
  );
}
