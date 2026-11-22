"use server";

import { redirect } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { signupClosed } from "@/lib/demo";
import { SIGNUP_CLOSED_MESSAGE, validateSignup } from "./logic";

export type SignUpState = { error?: string; notice?: string } | undefined;

export async function signUp(_prev: SignUpState, formData: FormData): Promise<SignUpState> {
  if (signupClosed(process.env)) return { error: SIGNUP_CLOSED_MESSAGE };
  const checked = validateSignup(formData.get("email"), formData.get("password"), formData.get("confirm"));
  if ("error" in checked) return { error: checked.error };

  const supabase = await createServerClient();
  const { data, error } = await supabase.auth.signUp({ email: checked.email, password: checked.password });
  if (error) {
    console.error("sign up failed", error.code ?? error.message);
    if (error.code === "user_already_exists") {
      return { error: "An account with that email already exists. Sign in instead." };
    }
    return { error: "The account could not be created. Try a different email or password." };
  }
  // No session means email confirmation is on: the account exists but cannot continue yet.
  if (!data.session) return { notice: "Check your email to confirm your account." };
  redirect("/register");
}
