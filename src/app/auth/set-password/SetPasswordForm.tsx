"use client";

import { useActionState } from "react";
import { setPassword } from "./actions";

export function SetPasswordForm({ email, minLength }: { email: string; minLength: number }) {
  const [state, action, pending] = useActionState(setPassword, undefined);
  return (
    <form action={action} style={{ display: "grid", gap: 8 }}>
      {/* Lets password managers file the new password under the right account. */}
      <input type="email" name="username" autoComplete="username" value={email} readOnly hidden />
      <label>
        New password
        <input name="password" type="password" autoComplete="new-password" minLength={minLength} required />
      </label>
      <label>
        Confirm password
        <input name="confirm" type="password" autoComplete="new-password" minLength={minLength} required />
      </label>
      {state?.error && <p role="alert" className="error">{state.error}</p>}
      <button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Set password and continue"}
      </button>
    </form>
  );
}
