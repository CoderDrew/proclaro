import { describe, expect, it, vi } from "vitest";
import type { SessionContext } from "@/lib/session";
import { addHoliday, removeHoliday, type HolidayDeps } from "./holidays/logic";
import { createOrganization, renameOrganization, type OrgDeps } from "./organizations/logic";
import { saveSettings, type SettingsDeps } from "./settings/logic";
import { createUser, INVITABLE_ORG_KINDS, type UserDeps } from "./users/logic";

const admin: SessionContext = { userId: "u-admin", orgId: "o1", orgKind: "office", isAdmin: true, displayName: "Admin" };
const staff: SessionContext = { ...admin!, isAdmin: false };
const ORG = "10000000-0000-4000-8000-000000000001";

describe("settings", () => {
  const d = (): SettingsDeps => ({ update: vi.fn(async () => true) });
  const good = { stateName: "State of Calder", officeName: "Calder State Construction Office", timezone: "America/Denver", fiscalYearStartMonth: "7" };

  it("saves valid settings", async () => {
    const deps = d();
    expect((await saveSettings(admin, good, deps)).ok).toBe(true);
    expect(deps.update).toHaveBeenCalledWith({
      state_name: "State of Calder", office_name: "Calder State Construction Office", timezone: "America/Denver", fiscal_year_start_month: 7,
    });
  });
  it("rejects a time zone that is not in the IANA list", async () => {
    for (const timezone of ["Mars/Olympus", "MST7MDT-bogus", "", "america/denver "]) {
      const deps = d();
      expect((await saveSettings(admin, { ...good, timezone }, deps)).ok, timezone).toBe(false);
      expect(deps.update).not.toHaveBeenCalled();
    }
  });
  it("rejects fiscal-year start months outside 1-12 or not whole", async () => {
    for (const m of ["0", "13", "-1", "6.5", "abc", ""]) {
      expect((await saveSettings(admin, { ...good, fiscalYearStartMonth: m }, d())).ok, m).toBe(false);
    }
    for (const m of ["1", "12"]) expect((await saveSettings(admin, { ...good, fiscalYearStartMonth: m }, d())).ok).toBe(true);
  });
  it("rejects blank names and refuses non-admins", async () => {
    expect((await saveSettings(admin, { ...good, stateName: " " }, d())).ok).toBe(false);
    const deps = d();
    expect((await saveSettings(staff, good, deps)).ok).toBe(false);
    expect(deps.update).not.toHaveBeenCalled();
  });
  it("reports when no settings row was updated", async () => {
    expect((await saveSettings(admin, good, { update: async () => false })).ok).toBe(false);
  });
});

describe("holidays", () => {
  const d = (over: Partial<HolidayDeps> = {}): HolidayDeps => ({
    insert: vi.fn(async () => "ok" as const),
    remove: vi.fn(async () => true),
    ...over,
  });

  it("adds a valid local date", async () => {
    const deps = d();
    expect((await addHoliday(admin, { day: "2027-07-05", name: "Observed Day" }, deps)).ok).toBe(true);
    expect(deps.insert).toHaveBeenCalledWith({ day: "2027-07-05", name: "Observed Day" });
  });
  it("rejects invalid calendar dates and wrong formats", async () => {
    for (const day of ["2027-02-30", "2027-13-01", "2027-00-10", "2027-4-5", "04/05/2027", "2027-04-05T00:00", "", "2027-02-29"]) {
      const deps = d();
      expect((await addHoliday(admin, { day, name: "X" }, deps)).ok, day).toBe(false);
      expect(deps.insert).not.toHaveBeenCalled();
    }
    expect((await addHoliday(admin, { day: "2028-02-29", name: "Leap" }, d())).ok).toBe(true);
  });
  it("rejects a duplicate date", async () => {
    const r = await addHoliday(admin, { day: "2027-07-05", name: "Again" }, d({ insert: async () => "duplicate" }));
    expect(!r.ok && r.message).toMatch(/already/i);
  });
  it("requires a name; refuses non-admins", async () => {
    expect((await addHoliday(admin, { day: "2027-07-05", name: " " }, d())).ok).toBe(false);
    const deps = d();
    expect((await addHoliday(staff, { day: "2027-07-05", name: "X" }, deps)).ok).toBe(false);
    expect((await removeHoliday(staff, "2027-07-05", deps)).ok).toBe(false);
    expect(deps.insert).not.toHaveBeenCalled();
    expect(deps.remove).not.toHaveBeenCalled();
  });
  it("removes by valid date only", async () => {
    const deps = d();
    expect((await removeHoliday(admin, "2027-07-05", deps)).ok).toBe(true);
    expect((await removeHoliday(admin, "nope", deps)).ok).toBe(false);
    expect((await removeHoliday(admin, "2027-07-05", d({ remove: async () => false }))).ok).toBe(false);
  });
});

describe("organizations", () => {
  const d = (over: Partial<OrgDeps> = {}): OrgDeps => ({
    insert: vi.fn(async () => "ok" as const),
    rename: vi.fn(async () => "ok" as const),
    ...over,
  });

  it("creates an agency or office; rejects other kinds and blank names", async () => {
    const deps = d();
    expect((await createOrganization(admin, { name: " Calder Dept ", kind: "agency" }, deps)).ok).toBe(true);
    expect(deps.insert).toHaveBeenCalledWith({ name: "Calder Dept", kind: "agency" });
    expect((await createOrganization(admin, { name: "X", kind: "bidder" }, d())).ok).toBe(false);
    expect((await createOrganization(admin, { name: " ", kind: "agency" }, d())).ok).toBe(false);
  });
  it("reports a duplicate name; reports a missing org on rename", async () => {
    expect((await createOrganization(admin, { name: "X", kind: "agency" }, d({ insert: async () => "duplicate" }))).ok).toBe(false);
    expect((await renameOrganization(admin, { id: ORG, name: "Y" }, d({ rename: async () => "duplicate" }))).ok).toBe(false);
    expect((await renameOrganization(admin, { id: ORG, name: "Y" }, d({ rename: async () => "missing" }))).ok).toBe(false);
    expect((await renameOrganization(admin, { id: "not-a-uuid", name: "Y" }, d())).ok).toBe(false);
    expect((await renameOrganization(admin, { id: ORG, name: "Y" }, d())).ok).toBe(true);
  });
  it("refuses non-admins", async () => {
    const deps = d();
    expect((await createOrganization(staff, { name: "X", kind: "agency" }, deps)).ok).toBe(false);
    expect((await renameOrganization(staff, { id: ORG, name: "Y" }, deps)).ok).toBe(false);
    expect(deps.insert).not.toHaveBeenCalled();
    expect(deps.rename).not.toHaveBeenCalled();
  });
});

describe("createUser", () => {
  const d = (over: Partial<UserDeps> = {}): UserDeps => ({
    orgKind: vi.fn(async () => "office" as string | null),
    invite: vi.fn(async () => ({ userId: "new-user" }) as { userId: string } | { error: string }),
    profileExists: vi.fn(async () => false),
    insertProfile: vi.fn(async () => true),
    deleteAuthUser: vi.fn(async () => {}),
    ...over,
  });
  const input = { email: "New.Person@example.test", displayName: " New Person ", orgId: ORG, isAdmin: false };

  it("invites, then inserts the profile", async () => {
    const deps = d();
    const r = await createUser(admin, input, deps);
    expect(r.ok).toBe(true);
    expect(deps.invite).toHaveBeenCalledWith("new.person@example.test", "New Person");
    expect(deps.insertProfile).toHaveBeenCalledWith({ userId: "new-user", orgId: ORG, displayName: "New Person", isAdmin: false });
  });
  it("accepts the seed-style organization ids (not RFC-versioned UUIDs)", async () => {
    const deps = d();
    const seed = "10000000-0000-0000-0000-000000000002";
    expect((await createUser(admin, { ...input, orgId: seed }, deps)).ok).toBe(true);
    expect(deps.insertProfile).toHaveBeenCalledWith(expect.objectContaining({ orgId: seed }));
  });
  it("removes the auth user again if the profile insert fails, so no half-created account remains", async () => {
    const deps = d({ insertProfile: async () => false });
    const r = await createUser(admin, input, deps);
    expect(r.ok).toBe(false);
    expect(deps.deleteAuthUser).toHaveBeenCalledWith("new-user");
  });
  it("leaves an existing account alone when the email was already registered (invite returns the existing user)", async () => {
    const deps = d({ profileExists: async () => true });
    const r = await createUser(admin, input, deps);
    expect(!r.ok && r.message).toMatch(/already exists/i);
    expect(deps.insertProfile).not.toHaveBeenCalled();
    expect(deps.deleteAuthUser).not.toHaveBeenCalled();
  });
  it("does not insert a profile when the invite fails", async () => {
    const deps = d({ invite: async () => ({ error: "A user with this email address has already been registered" }) });
    const r = await createUser(admin, input, deps);
    expect(!r.ok && r.message).toMatch(/already/i);
    expect(deps.insertProfile).not.toHaveBeenCalled();
  });
  it("validates email, name and organization before inviting anyone", async () => {
    for (const bad of [{ email: "nope" }, { email: "" }, { displayName: " " }, { orgId: "x" }]) {
      const deps = d();
      expect((await createUser(admin, { ...input, ...bad }, deps)).ok, JSON.stringify(bad)).toBe(false);
      expect(deps.invite).not.toHaveBeenCalled();
    }
    const deps = d({ orgKind: async () => null });
    expect((await createUser(admin, input, deps)).ok).toBe(false);
    expect(deps.invite).not.toHaveBeenCalled();
  });
  it("refuses a bidder organization before inviting anyone (staff never join a bidder org)", async () => {
    const deps = d({ orgKind: vi.fn(async () => "bidder") });
    const r = await createUser(admin, input, deps);
    expect(r).toEqual({ ok: false, message: "Choose an agency or office." });
    expect(deps.orgKind).toHaveBeenCalledWith(ORG);
    expect(deps.invite).not.toHaveBeenCalled();
    expect(deps.insertProfile).not.toHaveBeenCalled();
  });
  it("invites into an agency or an office", async () => {
    for (const kind of ["agency", "office"]) {
      const deps = d({ orgKind: async () => kind });
      expect((await createUser(admin, input, deps)).ok, kind).toBe(true);
      expect(deps.insertProfile).toHaveBeenCalled();
    }
  });
  it("offers agency and office organizations only", () => {
    expect([...INVITABLE_ORG_KINDS]).toEqual(["agency", "office"]);
  });
  it("refuses non-admins before any lookup", async () => {
    const deps = d();
    expect((await createUser(staff, input, deps)).ok).toBe(false);
    expect((await createUser(null, input, deps)).ok).toBe(false);
    expect(deps.orgKind).not.toHaveBeenCalled();
    expect(deps.invite).not.toHaveBeenCalled();
  });
});
