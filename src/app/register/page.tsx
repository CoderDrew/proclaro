import { redirect } from "next/navigation";
import { getAuthState, landingPathFor } from "@/lib/session";
import { RegisterForm } from "./RegisterForm";

export const dynamic = "force-dynamic";

export default async function RegisterPage() {
  const state = await getAuthState();
  // Only a signed-in, uninvited account without a profile registers a company. Staff never do.
  if (state.status !== "unregistered" || state.invited) redirect(landingPathFor(state));
  return (
    <main style={{ maxWidth: 420 }}>
      <h1>Register your company</h1>
      <p>Tell us about your company before you bid. You can bid on any open solicitation once registered.</p>
      <RegisterForm />
    </main>
  );
}
