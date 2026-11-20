"use client";

import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { Button, type ButtonVariant } from "./Button";
import { Notice } from "./Notice";

export interface ConfirmActionProps {
  /** The first button's text, e.g. "Post award". */
  label: string;
  /** The confirm button's text, e.g. "Confirm: post award publicly". */
  confirmLabel: string;
  /** What confirming does, shown with the confirm button and read as its description. */
  warning: ReactNode;
  /** Shown on the first button while the confirmed request runs. */
  busyLabel?: string;
  busy?: boolean;
  disabled?: boolean;
  /** Id of the text that explains the first button (for example why it is disabled). */
  describedBy?: string;
  variant?: ButtonVariant;
  "data-testid"?: string;
}

/**
 * A two-step button for an irreversible action. The first click reveals the warning, a confirm button and Cancel;
 * focus moves to the confirm button, and Cancel returns focus to the first button. The confirm button is a submit
 * button, so it is placed inside the form whose onSubmit runs the action.
 */
export function ConfirmAction({
  label, confirmLabel, warning, busyLabel, busy, disabled, describedBy, variant = "primary", ...rest
}: ConfirmActionProps) {
  const [asking, setAsking] = useState(false);
  const confirmRef = useRef<HTMLButtonElement>(null);
  const startRef = useRef<HTMLButtonElement>(null);
  const returnFocus = useRef(false);
  const warningId = useId();
  const testId = rest["data-testid"];

  useEffect(() => {
    if (asking) confirmRef.current?.focus();
    else if (returnFocus.current) {
      returnFocus.current = false;
      startRef.current?.focus();
    }
  }, [asking]);

  if (!asking || disabled) {
    return (
      <Button ref={startRef} type="button" variant={variant} disabled={disabled} loading={busy}
        aria-describedby={describedBy} data-testid={testId} onClick={() => setAsking(true)}>
        {busy && busyLabel ? busyLabel : label}
      </Button>
    );
  }

  return (
    <Notice tone="warning" role="group" aria-label={label} className="ui-confirm"
      data-testid={testId ? `${testId}-confirm-step` : undefined}>
      <p id={warningId}>{warning}</p>
      <span className="ui-inline-actions">
        <Button ref={confirmRef} type="submit" variant={variant} loading={busy} aria-describedby={warningId}
          data-testid={testId ? `${testId}-confirm` : undefined}>
          {busy && busyLabel ? busyLabel : confirmLabel}
        </Button>
        <Button type="button" disabled={busy} data-testid={testId ? `${testId}-cancel` : undefined}
          onClick={() => { returnFocus.current = true; setAsking(false); }}>
          Cancel
        </Button>
      </span>
    </Notice>
  );
}
