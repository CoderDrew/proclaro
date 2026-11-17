import { redirect } from "next/navigation";
import { getSessionContext } from "@/lib/session";
import { createServerClient } from "@/lib/supabase/server";
import { hasInviteSession } from "../guard";
import { LINK_INVALID_PATH, MIN_PASSWORD_LENGTH } from "../logic";
import { SetPasswordForm } from "./SetPasswordForm";

export const dynamic = "force-dynamic";

export default async function SetPasswordPage() {
  // Reachable only from a session the invite link created; a password sign-in does not qualify.
  if (!(await hasInviteSession())) redirect(LINK_INVALID_PATH);
  const ctx = await getSessionContext();
  if (!ctx) redirect("/login");

  const { data } = await (await createServerClient()).auth.getUser();

  return (
    <main style={{ maxWidth: 360 }}>
      <h1>Choose a password</h1>
      <p>
        Welcome, {ctx.displayName}. Set a password for <strong>{data.user?.email}</strong>. You will
        use it with your email address to sign in from now on.
      </p>
      <SetPasswordForm email={data.user?.email ?? ""} minLength={MIN_PASSWORD_LENGTH} />
    </main>
  );
}
