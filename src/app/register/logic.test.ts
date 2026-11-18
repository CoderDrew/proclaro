import { describe, expect, it } from "vitest";
import { parseRegistration, registerErrorMessage } from "./logic";

const ok = {
  legalName: "  Granite Mesa Contractors ",
  address: " 1 Main St, Calder ",
  contactName: " Pat Example ",
  contactPhone: " 555-0100 ",
  contactEmail: " pat@example.test ",
};

describe("parseRegistration", () => {
  it("rejects a blank legal name", () => {
    expect(parseRegistration({ ...ok, legalName: "   " })).toEqual({ ok: false, message: "Enter the company's legal name." });
  });
  it("rejects blank address, contact name, phone, email", () => {
    expect(parseRegistration({ ...ok, address: "" })).toMatchObject({ ok: false });
    expect(parseRegistration({ ...ok, contactName: "" })).toMatchObject({ ok: false });
    expect(parseRegistration({ ...ok, contactPhone: "" })).toMatchObject({ ok: false });
    expect(parseRegistration({ ...ok, contactEmail: "" })).toMatchObject({ ok: false });
  });
  it("requires a certificate when resident is claimed", () => {
    expect(parseRegistration({ ...ok, residentClaimed: "on", residentCertificate: "  " })).toEqual({
      ok: false, message: "Enter the resident certificate number.",
    });
  });
  it("passes trimmed values through", () => {
    expect(parseRegistration(ok)).toEqual({
      ok: true,
      value: {
        legalName: "Granite Mesa Contractors", address: "1 Main St, Calder", contactName: "Pat Example",
        contactPhone: "555-0100", contactEmail: "pat@example.test", residentClaimed: false, residentCertificate: null,
      },
    });
  });
  it("keeps the certificate when claimed, drops it when not", () => {
    expect(parseRegistration({ ...ok, residentClaimed: "on", residentCertificate: " R-123 " })).toMatchObject({
      ok: true, value: { residentClaimed: true, residentCertificate: "R-123" },
    });
    expect(parseRegistration({ ...ok, residentCertificate: "R-123" })).toMatchObject({
      ok: true, value: { residentClaimed: false, residentCertificate: null },
    });
  });
});

describe("registerErrorMessage", () => {
  it("maps database codes", () => {
    expect(registerErrorMessage("name_taken")).toBe("A company with that legal name is already registered.");
    expect(registerErrorMessage("not_authorized")).toContain("invited");
    expect(registerErrorMessage("invalid_data")).toContain("check");
    expect(registerErrorMessage("whatever")).toBe("The company could not be registered. Try again.");
  });
});
