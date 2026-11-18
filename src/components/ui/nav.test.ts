import { describe, expect, it } from "vitest";
import type { SessionContext } from "@/lib/session";
import { currentValue, isCurrentLink, navFor } from "./nav";

type Ctx = NonNullable<SessionContext>;
const mk = (orgKind: Ctx["orgKind"], isAdmin = false): Ctx => ({
  userId: "u1",
  orgId: "o1",
  orgKind,
  isAdmin,
  displayName: "Test User",
});

const ADMIN = [
  { href: "/admin/users", label: "Users" },
  { href: "/admin/organizations", label: "Organizations" },
  { href: "/admin/clauses", label: "Clauses" },
  { href: "/admin/holidays", label: "Holidays" },
  { href: "/admin/settings", label: "Settings" },
];
const OFFICE = [
  { href: "/office", label: "Review queue" },
  { href: "/office#published", label: "Published" },
];
const AGENCY = [{ href: "/agency", label: "My solicitations" }];

describe("navFor", () => {
  it("signed out (and profile-less, which is a null context)", () => {
    expect(navFor(null)).toEqual([
      { href: "/solicitations", label: "Solicitations" },
      { href: "/login", label: "Sign in" },
    ]);
  });
  it("bidder", () => {
    expect(navFor(mk("bidder"))).toEqual([
      { href: "/bidder#my-bids", label: "My bids" },
      { href: "/bidder", label: "Open solicitations" },
    ]);
  });
  it("agency member", () => expect(navFor(mk("agency"))).toEqual(AGENCY));
  it("office member", () => expect(navFor(mk("office"))).toEqual(OFFICE));
  it("admin in an office", () => expect(navFor(mk("office", true))).toEqual([...OFFICE, ...ADMIN]));
  it("admin in an agency", () => expect(navFor(mk("agency", true))).toEqual([...AGENCY, ...ADMIN]));

  describe("guard consistency", () => {
    const starts = (c: SessionContext, p: string) => navFor(c).some((l) => l.href.startsWith(p));
    it("non-admins never see /admin", () => {
      for (const c of [null, mk("bidder"), mk("agency"), mk("office")]) expect(starts(c, "/admin")).toBe(false);
    });
    it("bidder sees no office or agency link", () => {
      expect(starts(mk("bidder"), "/office")).toBe(false);
      expect(starts(mk("bidder"), "/agency")).toBe(false);
    });
    it("office and agency see no bidder link", () => {
      for (const c of [mk("office"), mk("agency"), mk("office", true), mk("agency", true)]) expect(starts(c, "/bidder")).toBe(false);
    });
    it("agency sees no office link", () => {
      expect(starts(mk("agency"), "/office")).toBe(false);
      expect(starts(mk("agency", true), "/office")).toBe(false);
    });
    it("a bidder flagged admin is not given admin links beyond what guards allow", () => {
      // admin pages admit any isAdmin member, so admin links apply to every org kind.
      expect(navFor(mk("bidder", true)).map((l) => l.href)).toEqual(["/bidder#my-bids", "/bidder", ...ADMIN.map((l) => l.href)]);
    });
  });
});

describe("isCurrentLink", () => {
  it("exact match", () => expect(isCurrentLink("/admin/users", "/admin/users")).toBe(true));
  it("nested pages mark their section", () => {
    expect(isCurrentLink("/bidder", "/bidder/solicitations/abc")).toBe(true);
    expect(isCurrentLink("/admin/users", "/admin/users/123")).toBe(true);
    expect(isCurrentLink("/agency", "/agency/solicitations/new")).toBe(true);
  });
  it("matches on a segment boundary only", () => {
    expect(isCurrentLink("/office", "/office-hours")).toBe(false);
    expect(isCurrentLink("/admin/users", "/admin/users-archive")).toBe(false);
  });
  it("other sections are not marked", () => {
    expect(isCurrentLink("/admin/users", "/admin/clauses")).toBe(false);
    expect(isCurrentLink("/bidder", "/office")).toBe(false);
  });
  it("root is exact", () => {
    expect(isCurrentLink("/", "/")).toBe(true);
    expect(isCurrentLink("/", "/solicitations")).toBe(false);
  });
  it("hash links are never current", () => {
    expect(isCurrentLink("/bidder#my-bids", "/bidder")).toBe(false);
    expect(isCurrentLink("/office#published", "/office#published")).toBe(false);
  });
});

describe("currentValue", () => {
  it("exact path is page", () => expect(currentValue("/admin/users", "/admin/users")).toBe("page"));
  it("nested path is a section match, true", () => {
    expect(currentValue("/bidder", "/bidder/solicitations/abc")).toBe("true");
    expect(currentValue("/admin/users", "/admin/users/123")).toBe("true");
  });
  it("no match and hash links are undefined", () => {
    expect(currentValue("/admin/users", "/admin/clauses")).toBeUndefined();
    expect(currentValue("/bidder#my-bids", "/bidder")).toBeUndefined();
  });
});
