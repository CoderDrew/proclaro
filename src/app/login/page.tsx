import { devEmailLoginEnabled } from "@/lib/devEmailLogin";
import { demoLogins, signupClosed } from "@/lib/demo";
import { LoginForm } from "./LoginForm";

// Read the gates per request so toggling DEV_EMAIL_LOGIN, DEMO_PASSWORD or SIGNUP_CLOSED (and restarting) shows at once.
export const dynamic = "force-dynamic";

export default function LoginPage() {
  return (
    <LoginForm devMode={devEmailLoginEnabled(process.env)} demo={demoLogins(process.env)}
               signupOpen={!signupClosed(process.env)} />
  );
}
