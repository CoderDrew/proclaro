// The hosted site's shared demo accounts and closed signup. Both are read from server-side env on each request; neither
// is NEXT_PUBLIC_. DEMO_PASSWORD must equal the one in .env.hosted that npm run hosted:reset seeds (README "Hosting").

export interface DemoAccount { email: string; role: string }

export const DEMO_ACCOUNTS: DemoAccount[] = [
  { email: "author.corrections@example.test", role: "Agency author (Corrections)" },
  { email: "author.parks@example.test", role: "Agency author (Parks)" },
  { email: "reviewer1@example.test", role: "Office reviewer" },
  { email: "reviewer2@example.test", role: "Office reviewer" },
  { email: "admin@example.test", role: "Office admin" },
  { email: "bidder.ridgeback@example.test", role: "Bidder (resident certificate)" },
  { email: "bidder.granite@example.test", role: "Bidder" },
  { email: "bidder.juniper@example.test", role: "Bidder" },
  { email: "bidder.basalt@example.test", role: "Bidder" },
];

/** The demo accounts to list on the sign-in page, or null when this site has none. */
export function demoLogins(env: Record<string, string | undefined>): { password: string; accounts: DemoAccount[] } | null {
  const password = env.DEMO_PASSWORD?.trim();
  return password ? { password, accounts: DEMO_ACCOUNTS } : null;
}

/** True when new accounts can't be created here (the hosted site). */
export function signupClosed(env: Record<string, string | undefined>): boolean {
  return env.SIGNUP_CLOSED === "1";
}
