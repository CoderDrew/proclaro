// Self-signup input checks. Pure: no Next, no Supabase.
import { validateNewPassword } from "@/app/auth/logic";

export function validateSignup(
  email: unknown,
  password: unknown,
  confirm: unknown,
): { email: string; password: string } | { error: string } {
  const e = typeof email === "string" ? email.trim() : "";
  if (!e) return { error: "Enter your email address." };
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) return { error: "Enter a valid email address." };
  const checked = validateNewPassword(password, confirm);
  if ("error" in checked) {
    return { error: checked.error === "The two passwords do not match." ? "The passwords do not match." : checked.error };
  }
  return { email: e, password: checked.password };
}

export const SIGNUP_CLOSED_MESSAGE = "New accounts can't be created on this site. Sign in with one of the demo accounts.";
