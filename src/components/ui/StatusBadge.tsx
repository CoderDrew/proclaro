import { statusBadge, type DomainStatus } from "./status";

export function StatusBadge({
  status, label, role, wrap, ...rest
}: { status: DomainStatus; label?: string; role?: "alert" | "status"; wrap?: boolean; "data-testid"?: string }) {
  const b = statusBadge(status);
  return (
    <span {...rest} className={`ui-badge ui-badge--${b.tone}${wrap ? " ui-badge--wrap" : ""}`} role={role}>
      {label ?? b.label}
    </span>
  );
}
