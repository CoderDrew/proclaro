import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("./actions", () => ({ signIn: async () => undefined }));

import { LoginForm } from "./LoginForm";
import { DEMO_ACCOUNTS } from "@/lib/demo";

describe("LoginForm", () => {
  it("lists the demo accounts and hides signup on the hosted site", () => {
    const out = renderToStaticMarkup(createElement(LoginForm, {
      devMode: false, demo: { password: "pw-123", accounts: DEMO_ACCOUNTS }, signupOpen: false,
    }));
    expect(out).toContain("pw-123");
    for (const a of DEMO_ACCOUNTS) expect(out).toContain(a.email);
    expect(out).not.toContain('href="/signup"');
  });

  it("shows neither demo accounts nor a password hint locally, and keeps signup", () => {
    const out = renderToStaticMarkup(createElement(LoginForm, { devMode: false, demo: null, signupOpen: true }));
    expect(out).not.toContain("demo-accounts");
    expect(out).toContain('href="/signup"');
  });
});
