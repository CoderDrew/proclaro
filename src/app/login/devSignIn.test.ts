import { describe, expect, it, vi } from "vitest";
import { devSignIn, SIGN_IN_FAILED, type DevSignInDeps } from "./devSignIn";

const deps = (over: Partial<DevSignInDeps> = {}): DevSignInDeps => ({
  enabled: true,
  mintTokenHash: vi.fn(async () => "hash-1"),
  verifyOtp: vi.fn(async () => ({ error: null })),
  ...over,
});

describe("devSignIn", () => {
  it("is refused when the gate is off, without minting or verifying anything", async () => {
    const d = deps({ enabled: false });
    expect(await devSignIn("reviewer1@example.test", d)).toEqual({ error: SIGN_IN_FAILED });
    expect(d.mintTokenHash).not.toHaveBeenCalled();
    expect(d.verifyOtp).not.toHaveBeenCalled();
  });
  it("gives the generic error for an unknown email and never verifies", async () => {
    const d = deps({ mintTokenHash: vi.fn(async () => null) });
    expect(await devSignIn("nobody@example.test", d)).toEqual({ error: SIGN_IN_FAILED });
    expect(d.verifyOtp).not.toHaveBeenCalled();
  });
  it("calls verifyOtp with the minted token hash on success", async () => {
    const d = deps();
    expect(await devSignIn("reviewer1@example.test", d)).toEqual({});
    expect(d.mintTokenHash).toHaveBeenCalledWith("reviewer1@example.test");
    expect(d.verifyOtp).toHaveBeenCalledWith("hash-1");
  });
  it("gives the generic error when verifyOtp fails", async () => {
    const d = deps({ verifyOtp: vi.fn(async () => ({ error: "expired" })) });
    expect(await devSignIn("reviewer1@example.test", d)).toEqual({ error: SIGN_IN_FAILED });
  });
});
