import Link from "next/link";
import { redirect } from "next/navigation";
import { getAuthState, landingPathFor } from "@/lib/session";
import { MIN_PASSWORD_LENGTH } from "@/app/auth/logic";
import { Card, Page, PageHeader } from "@/components/ui";
import { SignUpForm } from "./SignUpForm";

export const dynamic = "force-dynamic";

export default async function SignUpPage() {
  const state = await getAuthState();
  if (state.status !== "signed_out") redirect(landingPathFor(state));
  return (
    <Page width="narrow">
      <Card>
        <PageHeader title="Create an account" />
        <p>For bidders. After creating your account you will register your company.</p>
        <SignUpForm minLength={MIN_PASSWORD_LENGTH} />
        <p>Already have an account? <Link href="/login">Sign in</Link></p>
      </Card>
    </Page>
  );
}
