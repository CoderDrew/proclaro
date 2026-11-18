"use client";

import { useActionState } from "react";
import { Button, Field, Notice } from "@/components/ui";
import { signUp } from "./actions";

export function SignUpForm({ minLength }: { minLength: number }) {
  const [state, action, pending] = useActionState(signUp, undefined);
  return (
    <form action={action} className="ui-form">
      <Field label="Email">
        <input name="email" type="email" autoComplete="username" required />
      </Field>
      <Field label="Password">
        <input name="password" type="password" autoComplete="new-password" minLength={minLength} required />
      </Field>
      <Field label="Confirm password">
        <input name="confirm" type="password" autoComplete="new-password" minLength={minLength} required />
      </Field>
      {state?.error && <Notice tone="error" role="alert">{state.error}</Notice>}
      {state?.notice && <Notice tone="success" role="status">{state.notice}</Notice>}
      <Button type="submit" variant="primary" loading={pending}>{pending ? "Creating account..." : "Create account"}</Button>
    </form>
  );
}
