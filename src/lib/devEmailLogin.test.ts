import { describe, expect, it } from "vitest";
import { devEmailLoginEnabled } from "./devEmailLogin";

const on = { NODE_ENV: "development", DEV_EMAIL_LOGIN: "1", NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321" };

describe("devEmailLoginEnabled", () => {
  it("is on when every condition holds (127.0.0.1 or localhost, dev or test)", () => {
    expect(devEmailLoginEnabled(on)).toBe(true);
    expect(devEmailLoginEnabled({ ...on, NEXT_PUBLIC_SUPABASE_URL: "http://localhost:54321" })).toBe(true);
    expect(devEmailLoginEnabled({ ...on, NODE_ENV: "test" })).toBe(true);
  });
  it("is off in production", () => {
    expect(devEmailLoginEnabled({ ...on, NODE_ENV: "production" })).toBe(false);
  });
  it("is off unless DEV_EMAIL_LOGIN is exactly 1", () => {
    for (const v of [undefined, "", "0", "true", "yes", " 1"]) {
      expect(devEmailLoginEnabled({ ...on, DEV_EMAIL_LOGIN: v })).toBe(false);
    }
  });
  it("is off when the Supabase URL is not this machine, missing or malformed", () => {
    for (const u of [undefined, "", "not a url", "https://abc.supabase.co", "http://127.0.0.1.evil.com:54321", "http://evil.com/127.0.0.1", "http://localhost.evil.com", "http://127.0.0.1.nip.io:54321"]) {
      expect(devEmailLoginEnabled({ ...on, NEXT_PUBLIC_SUPABASE_URL: u })).toBe(false);
    }
  });
});
