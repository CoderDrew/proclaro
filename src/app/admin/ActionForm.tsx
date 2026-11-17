"use client";

import { useActionState } from "react";
import type { AdminResult } from "./common";

/**
 * A form bound to a server action that returns { ok, message } instead of throwing.
 * Server components pass the action in; the form shows the result under the fields.
 */
export function ActionForm({
  action,
  children,
  className,
  submitLabel = "Save",
}: {
  action: (formData: FormData) => Promise<AdminResult>;
  children: React.ReactNode;
  className?: string;
  submitLabel?: string;
}) {
  const [state, run, pending] = useActionState(
    async (_prev: AdminResult | null, fd: FormData) => action(fd),
    null,
  );
  return (
    <form action={run} className={className}>
      {children}
      <button type="submit" disabled={pending}>{pending ? "Working..." : submitLabel}</button>
      {state && (
        <span role={state.ok ? "status" : "alert"} style={{ marginLeft: 8, color: state.ok ? "green" : "crimson" }}>
          {state.ok ? state.message ?? "Saved." : state.message}
        </span>
      )}
    </form>
  );
}
