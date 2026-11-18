"use client";

import Link from "next/link";
import { useActionState } from "react";
import { Button, Card, Field, Notice, Page, PageHeader } from "@/components/ui";
import { signIn } from "./actions";

export function LoginForm({ devMode }: { devMode: boolean }) {
  const [state, action, pending] = useActionState(signIn, undefined);
  return (
    <Page width="narrow">
      <Card>
        <PageHeader title="Sign in" />
        <form action={action} className="ui-form">
          <Field label="Email">
            <input name="email" type="email" autoComplete="username" required />
          </Field>
          {devMode ? (
            <Notice tone="warning">Development sign-in: no password required</Notice>
          ) : (
            <Field label="Password">
              <input name="password" type="password" autoComplete="current-password" required />
            </Field>
          )}
          {state?.error && <Notice tone="error" role="alert">{state.error}</Notice>}
          <Button type="submit" variant="primary" loading={pending}>
            {pending ? "Signing in..." : "Sign in"}
          </Button>
        </form>
        <p>New bidder? <Link href="/signup">Create an account</Link></p>
      </Card>
    </Page>
  );
}
