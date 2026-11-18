import { devEmailLoginEnabled } from "@/lib/devEmailLogin";
import { LoginForm } from "./LoginForm";

// Read the dev gate per request so toggling DEV_EMAIL_LOGIN (and restarting) is reflected at once.
export const dynamic = "force-dynamic";

export default function LoginPage() {
  return <LoginForm devMode={devEmailLoginEnabled(process.env)} />;
}
