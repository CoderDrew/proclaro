"use client";

import Link from "next/link";
import { useActionState } from "react";
import { signIn } from "./actions";

export default function LoginPage() {
  const [state, action, pending] = useActionState(signIn, undefined);
  return (
    <main style={{ maxWidth: 360 }}>
      <h1>Sign in</h1>
      <form action={action} style={{ display: "grid", gap: 8 }}>
        <label>
          Email
          <input name="email" type="email" autoComplete="username" required />
        </label>
        <label>
          Password
          <input name="password" type="password" autoComplete="current-password" required />
        </label>
        {state?.error && <p role="alert" className="error">{state.error}</p>}
        <button type="submit" disabled={pending}>
          {pending ? "Signing in..." : "Sign in"}
        </button>
      </form>
      <p>New bidder? <Link href="/signup">Create an account</Link></p>
    </main>
  );
}
