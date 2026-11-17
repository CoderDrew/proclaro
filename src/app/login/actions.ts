"use server";

import { redirect } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { getSessionContext, homePathFor } from "@/lib/session";

export type SignInState = { error?: string } | undefined;

/**
 * Email + password sign-in for local development (seed users).
 * Magic link can replace the body of this function later; the login page
 * only depends on the (state, formData) -> redirect/error contract.
 */
export async function signIn(
  _prev: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  if (!email || !password) return { error: "Enter email and password." };

  const supabase = await createServerClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { error: "Sign-in failed. Check your email and password." };

  const ctx = await getSessionContext();
  if (!ctx) {
    await supabase.auth.signOut();
    return { error: "This account has no profile. Contact an administrator." };
  }
  redirect(homePathFor(ctx));
}

export async function signOut() {
  const supabase = await createServerClient();
  await supabase.auth.signOut();
  redirect("/login");
}
