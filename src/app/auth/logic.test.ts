import { describe, expect, it } from "vitest";
import { canSetInitialPassword, inviteRedirectUrl, parseConfirmParams, validateNewPassword } from "./logic";

const HASH = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c";

describe("inviteRedirectUrl", () => {
  it("points at the confirm route on the configured origin", () => {
    expect(inviteRedirectUrl("http://127.0.0.1:3000")).toBe("http://127.0.0.1:3000/auth/confirm");
  });
  it("drops trailing slashes", () => {
    expect(inviteRedirectUrl("https://proclaro.example.test/")).toBe("https://proclaro.example.test/auth/confirm");
  });
  it("falls back to the local dev origin", () => {
    expect(inviteRedirectUrl(undefined)).toBe("http://127.0.0.1:3000/auth/confirm");
    expect(inviteRedirectUrl("  ")).toBe("http://127.0.0.1:3000/auth/confirm");
  });
});

describe("parseConfirmParams", () => {
  it("accepts an invite token hash", () => {
    expect(parseConfirmParams(new URLSearchParams({ token_hash: HASH, type: "invite" }))).toEqual({
      tokenHash: HASH,
      type: "invite",
    });
  });
  it("rejects a missing token", () => {
    expect(parseConfirmParams(new URLSearchParams({ type: "invite" }))).toBeNull();
    expect(parseConfirmParams(new URLSearchParams({ token_hash: "", type: "invite" }))).toBeNull();
  });
  it("rejects every token type other than invite", () => {
    for (const type of ["signup", "magiclink", "recovery", "email_change", "email", ""]) {
      expect(parseConfirmParams(new URLSearchParams({ token_hash: HASH, type }))).toBeNull();
    }
    expect(parseConfirmParams(new URLSearchParams({ token_hash: HASH }))).toBeNull();
  });
  it("rejects a token that is not a hex hash", () => {
    expect(parseConfirmParams(new URLSearchParams({ token_hash: "abc<script>", type: "invite" }))).toBeNull();
    expect(parseConfirmParams(new URLSearchParams({ token_hash: "abc", type: "invite" }))).toBeNull();
  });
});

describe("canSetInitialPassword", () => {
  const invitedAt = "2026-11-17T20:16:31Z";
  it("allows an invited user whose session came from the emailed token", () => {
    expect(canSetInitialPassword([{ method: "otp", timestamp: 1 }], invitedAt)).toBe(true);
  });
  it("accepts the RFC 8176 plain-string form", () => {
    expect(canSetInitialPassword(["otp"], invitedAt)).toBe(true);
  });
  it("refuses a password sign-in, even for an invited user", () => {
    expect(canSetInitialPassword([{ method: "password", timestamp: 1 }], invitedAt)).toBe(false);
    expect(canSetInitialPassword(["password"], invitedAt)).toBe(false);
  });
  it("refuses a user who was never invited (the seeded users)", () => {
    expect(canSetInitialPassword([{ method: "otp", timestamp: 1 }], null)).toBe(false);
    expect(canSetInitialPassword([{ method: "otp", timestamp: 1 }], undefined)).toBe(false);
  });
  it("is closed to every session while dev email sign-in is enabled, even an invited otp one", () => {
    expect(canSetInitialPassword([{ method: "otp", timestamp: 1 }], invitedAt, true)).toBe(false);
    expect(canSetInitialPassword([{ method: "otp", timestamp: 1 }], invitedAt, false)).toBe(true);
  });
  it("refuses missing or malformed claims", () => {
    expect(canSetInitialPassword(undefined, invitedAt)).toBe(false);
    expect(canSetInitialPassword("otp", invitedAt)).toBe(false);
    expect(canSetInitialPassword([null, 42, { method: "invite" }], invitedAt)).toBe(false);
  });
});

describe("validateNewPassword", () => {
  it("accepts a matching password of the minimum length", () => {
    expect(validateNewPassword("abcdefgh", "abcdefgh")).toEqual({ password: "abcdefgh" });
  });
  it("rejects blank, short and non-string input", () => {
    expect(validateNewPassword("", "")).toEqual({ error: "Enter a password." });
    expect(validateNewPassword(null, null)).toEqual({ error: "Enter a password." });
    expect(validateNewPassword("abcdefg", "abcdefg")).toEqual({ error: "Use at least 8 characters." });
  });
  it("rejects passwords longer than 72 bytes, counting multi-byte characters", () => {
    expect("error" in validateNewPassword("a".repeat(73), "a".repeat(73))).toBe(true);
    expect(validateNewPassword("a".repeat(72), "a".repeat(72))).toEqual({ password: "a".repeat(72) });
    const wide = "é".repeat(37); // 37 characters, 74 bytes
    expect("error" in validateNewPassword(wide, wide)).toBe(true);
  });
  it("rejects leading or trailing spaces", () => {
    expect("error" in validateNewPassword(" abcdefgh", " abcdefgh")).toBe(true);
  });
  it("rejects a mismatched confirmation", () => {
    expect(validateNewPassword("abcdefgh", "abcdefgH")).toEqual({ error: "The two passwords do not match." });
  });
});
