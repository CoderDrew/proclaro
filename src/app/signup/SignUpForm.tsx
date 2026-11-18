"use client";

import { useActionState } from "react";
import { signUp } from "./actions";

export function SignUpForm({ minLength }: { minLength: number }) {
  const [state, action, pending] = useActionState(signUp, undefined);
  return (
    <form action={action} style={{ display: "grid", gap: 8 }}>
      <label>
        Email
        <input name="email" type="email" autoComplete="username" required />
      </label>
      <label>
        Password
        <input name="password" type="password" autoComplete="new-password" minLength={minLength} required />
      </label>
      <label>
        Confirm password
        <input name="confirm" type="password" autoComplete="new-password" minLength={minLength} required />
      </label>
      {state?.error && <p role="alert" className="error">{state.error}</p>}
      {state?.notice && <p role="status">{state.notice}</p>}
      <button type="submit" disabled={pending}>{pending ? "Creating account..." : "Create account"}</button>
    </form>
  );
}
