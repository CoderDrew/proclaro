import { describe, expect, it } from "vitest";
import { validateSignup } from "./logic";

describe("validateSignup", () => {
  it("rejects a short password with the 8-character error", () => {
    expect(validateSignup("a@b.test", "short", "short")).toEqual({ error: "Use at least 8 characters." });
  });
  it("rejects mismatched confirmation", () => {
    expect(validateSignup("a@b.test", "longenough1", "different1")).toEqual({ error: "The passwords do not match." });
  });
  it("requires an email", () => {
    expect(validateSignup("  ", "longenough1", "longenough1")).toEqual({ error: "Enter your email address." });
    expect(validateSignup("not-an-email", "longenough1", "longenough1")).toEqual({ error: "Enter a valid email address." });
  });
  it("accepts and trims the email", () => {
    expect(validateSignup(" A@b.test ", "longenough1", "longenough1")).toEqual({ email: "A@b.test", password: "longenough1" });
  });
});
