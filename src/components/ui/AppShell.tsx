import type { ReactNode } from "react";
import { signOut } from "@/app/login/actions";
import { homePathFor, type SessionContext } from "@/lib/session";
import { AppNav } from "./AppNav";
import { Button } from "./Button";
import { navFor } from "./nav";

export function AppShell({ ctx, orgName, children }: { ctx: SessionContext; orgName: string; children: ReactNode }) {
  return (
    <>
      <header className="ui-topbar">
        <a href={ctx ? homePathFor(ctx) : "/"} className="ui-wordmark">
          <strong>Proclaro</strong>
        </a>
        <AppNav links={navFor(ctx)} />
        {ctx && (
          <div className="ui-topbar-user">
            <span>
              {ctx.displayName} · {orgName}
              {ctx.isAdmin ? " · admin" : ""}
            </span>
            <form action={signOut}>
              <Button type="submit">Sign out</Button>
            </form>
          </div>
        )}
      </header>
      <div className="ui-content">{children}</div>
    </>
  );
}
