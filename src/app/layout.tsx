import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";
import { getSessionContext, homePathFor } from "@/lib/session";
import { createServerClient } from "@/lib/supabase/server";
import { signOut } from "./login/actions";

export const metadata: Metadata = {
  title: "Proclaro",
  description: "Solicitation setup and review",
};

export default async function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const ctx = await getSessionContext();
  let orgName = "";
  if (ctx) {
    const supabase = await createServerClient();
    const { data } = await supabase
      .from("organizations")
      .select("name")
      .eq("id", ctx.orgId)
      .maybeSingle();
    orgName = data?.name ?? "";
  }

  return (
    <html lang="en">
      <body>
        <header className="shell-header">
          <a href={ctx ? homePathFor(ctx) : "/"}>
            <strong>Proclaro</strong>
          </a>
          <Link href="/solicitations">Solicitations</Link>
          <span className="spacer" />
          {ctx ? (
            <>
              <span>
                {ctx.displayName} · {orgName}
                {ctx.isAdmin ? " · admin" : ""}
              </span>
              <form action={signOut}>
                <button type="submit">Sign out</button>
              </form>
            </>
          ) : (
            <a href="/login">Sign in</a>
          )}
        </header>
        <div className="shell-body">{children}</div>
      </body>
    </html>
  );
}
