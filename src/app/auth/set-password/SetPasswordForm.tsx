"use client";

import { useActionState } from "react";
import { Button, Field, Notice } from "@/components/ui";
import { setPassword } from "./actions";

export function SetPasswordForm({ email, minLength }: { email: string; minLength: number }) {
  const [state, action, pending] = useActionState(setPassword, undefined);
  return (
    <form action={action} className="ui-form">
      {/* Lets password managers file the new password under the right account. */}
      <input type="email" name="username" autoComplete="username" value={email} readOnly hidden />
      <Field label="New password">
        <input name="password" type="password" autoComplete="new-password" minLength={minLength} required />
      </Field>
      <Field label="Confirm password">
        <input name="confirm" type="password" autoComplete="new-password" minLength={minLength} required />
      </Field>
      {state?.error && <Notice tone="error" role="alert">{state.error}</Notice>}
      <Button type="submit" variant="primary" loading={pending}>
        {pending ? "Saving..." : "Set password and continue"}
      </Button>
    </form>
  );
}
