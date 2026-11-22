"use client";

import Link from "next/link";
import { useActionState } from "react";
import { Button, Card, Field, Notice, Page, PageHeader, Table, Td, Th } from "@/components/ui";
import type { DemoAccount } from "@/lib/demo";
import { signIn } from "./actions";

export function LoginForm({ devMode, demo, signupOpen }: {
  devMode: boolean;
  demo: { password: string; accounts: DemoAccount[] } | null;
  signupOpen: boolean;
}) {
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
        {signupOpen && <p>New bidder? <Link href="/signup">Create an account</Link></p>}
      </Card>
      {demo && (
        <Card title="Demo accounts" data-testid="demo-accounts">
          <p>
            Every account uses the password <code>{demo.password}</code>. The data is fictional and shared by every
            visitor, and it is reset from time to time.
          </p>
          <Table>
            <thead><tr><Th>Email</Th><Th>Role</Th></tr></thead>
            <tbody>
              {demo.accounts.map((a) => (
                <tr key={a.email}><Td><code>{a.email}</code></Td><Td>{a.role}</Td></tr>
              ))}
            </tbody>
          </Table>
        </Card>
      )}
    </Page>
  );
}
