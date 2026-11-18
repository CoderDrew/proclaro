"use server";

import { redirect } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { getAuthState, landingPathFor } from "@/lib/session";
import { devEmailLoginEnabled } from "@/lib/devEmailLogin";
import { mintDevLoginTokenHash } from "./devLogin";
import { devSignIn } from "./devSignIn";

export type SignInState = { error?: string } | undefined;

/**
 * Sign-in, in one of two modes. Normally: email + password (signInWithPassword). Development only, when
 * devEmailLoginEnabled(process.env) is true (re-checked here on the server) and no password was sent:
 * email alone, for an existing user with a profile (see ./devLogin). The dev mode has one generic error
 * for every failure. The login page only depends on the (state, formData) -> redirect/error contract.
 */
export async function signIn(
  _prev: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const supabase = await createServerClient();

  // Development only: with the gate open (re-checked here, never trusted from the client) and no
  // password submitted, sign in by email alone. With the gate closed this branch does not exist.
  const devMode = devEmailLoginEnabled(process.env);
  if (devMode && email && !password) {
    const result = await devSignIn(email, {
      enabled: devMode,
      mintTokenHash: mintDevLoginTokenHash,
      verifyOtp: async (tokenHash) => {
        const { error } = await supabase.auth.verifyOtp({ type: "magiclink", token_hash: tokenHash });
        return { error: error?.message ?? null };
      },
    });
    if (result.error) return result;
  } else {
    if (!email || !password) return { error: "Enter email and password." };
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) return { error: "Sign-in failed. Check your email and password." };
  }

  const state = await getAuthState();
  // An invited account with no profile is staff that was never set up: it never self-registers.
  if (state.status === "unregistered" && state.invited) {
    await supabase.auth.signOut();
    return { error: "This account has no profile. Contact an administrator." };
  }
  redirect(landingPathFor(state));
}

export async function signOut() {
  const supabase = await createServerClient();
  await supabase.auth.signOut();
  redirect("/login");
}
