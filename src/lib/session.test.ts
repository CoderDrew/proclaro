import { describe, expect, it } from "vitest";
import { homePathFor, landingPathFor, type SessionContext } from "./session";

const base = {
  userId: "u1",
  orgId: "o1",
  displayName: "Test User",
};

describe("homePathFor", () => {
  it("sends anonymous users to /login", () => {
    expect(homePathFor(null)).toBe("/login");
  });
  it("sends agency users to /agency", () => {
    const ctx: SessionContext = { ...base, orgKind: "agency", isAdmin: false };
    expect(homePathFor(ctx)).toBe("/agency");
  });
  it("sends office users to /office", () => {
    const ctx: SessionContext = { ...base, orgKind: "office", isAdmin: false };
    expect(homePathFor(ctx)).toBe("/office");
  });
  it("sends admins to /admin regardless of org kind", () => {
    expect(homePathFor({ ...base, orgKind: "agency", isAdmin: true })).toBe("/admin");
    expect(homePathFor({ ...base, orgKind: "office", isAdmin: true })).toBe("/admin");
  });
});

describe("homePathFor bidder", () => {
  it("sends bidders to /bidder", () => {
    expect(homePathFor({ ...base, orgKind: "bidder", isAdmin: false })).toBe("/bidder");
  });
});

describe("landingPathFor", () => {
  const ctx = { ...base, orgKind: "agency" as const, isAdmin: false };
  it("signed out goes to /login", () => {
    expect(landingPathFor({ status: "signed_out" })).toBe("/login");
  });
  it("unregistered, not invited goes to /register", () => {
    expect(landingPathFor({ status: "unregistered", userId: "u", invited: false })).toBe("/register");
  });
  it("unregistered and invited goes to /login", () => {
    expect(landingPathFor({ status: "unregistered", userId: "u", invited: true })).toBe("/login");
  });
  it("members go to their home", () => {
    expect(landingPathFor({ status: "member", ctx })).toBe("/agency");
  });
});
