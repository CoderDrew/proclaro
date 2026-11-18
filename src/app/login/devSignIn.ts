/** Dev-only email sign-in logic with injected dependencies, so it is unit-testable. */
export type DevSignInDeps = {
  /** Result of devEmailLoginEnabled(process.env), evaluated on the server. */
  enabled: boolean;
  /** Token hash for an existing user with a profile, or null for anyone else. */
  mintTokenHash: (email: string) => Promise<string | null>;
  /** Exchanges the token hash for session cookies; returns an error message on failure. */
  verifyOtp: (tokenHash: string) => Promise<{ error: string | null }>;
};

export const SIGN_IN_FAILED = "Sign-in failed. Check the email address.";

export async function devSignIn(email: string, deps: DevSignInDeps): Promise<{ error?: string }> {
  if (!deps.enabled) return { error: SIGN_IN_FAILED };
  const tokenHash = await deps.mintTokenHash(email);
  if (!tokenHash) return { error: SIGN_IN_FAILED };
  const { error } = await deps.verifyOtp(tokenHash);
  return error ? { error: SIGN_IN_FAILED } : {};
}
