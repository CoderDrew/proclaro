import { describe, expect, it } from "vitest";
import { homePathFor, type SessionContext } from "./session";

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
