"use client";

import { useActionState } from "react";
import { Button, Notice, type ButtonVariant } from "@/components/ui";
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
  submitVariant = "primary",
  submitAriaLabel,
}: {
  action: (formData: FormData) => Promise<AdminResult>;
  children: React.ReactNode;
  className?: string;
  submitLabel?: string;
  submitVariant?: ButtonVariant;
  submitAriaLabel?: string;
}) {
  const [state, run, pending] = useActionState(
    async (_prev: AdminResult | null, fd: FormData) => action(fd),
    null,
  );
  return (
    <form action={run} className={className}>
      {children}
      <Button type="submit" variant={submitVariant} loading={pending} aria-label={pending ? undefined : submitAriaLabel}>
        {pending ? "Working..." : submitLabel}
      </Button>
      {state && (
        <Notice
          tone={state.ok ? "success" : "error"}
          role={state.ok ? "status" : "alert"}
          className="ui-inline-status"
        >
          {state.ok ? state.message ?? "Saved." : state.message}
        </Notice>
      )}
    </form>
  );
}
