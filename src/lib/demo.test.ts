import { describe, expect, it } from "vitest";
import { DEMO_ACCOUNTS, demoLogins, signupClosed } from "./demo";

describe("demoLogins", () => {
  it("lists the accounts only when DEMO_PASSWORD is set", () => {
    expect(demoLogins({})).toBeNull();
    expect(demoLogins({ DEMO_PASSWORD: "  " })).toBeNull();
    expect(demoLogins({ DEMO_PASSWORD: "pw" })).toEqual({ password: "pw", accounts: DEMO_ACCOUNTS });
  });

  it("matches the seeded users", async () => {
    const { readFileSync } = await import("node:fs");
    const seed = readFileSync("supabase/seed.sql", "utf8");
    for (const a of DEMO_ACCOUNTS) expect(seed).toContain(`'${a.email}'`);
  });
});

describe("signupClosed", () => {
  it("is true only for SIGNUP_CLOSED=1", () => {
    expect(signupClosed({ SIGNUP_CLOSED: "1" })).toBe(true);
    expect(signupClosed({ SIGNUP_CLOSED: "true" })).toBe(false);
    expect(signupClosed({})).toBe(false);
  });
});
