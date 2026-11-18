import type { SessionContext } from "@/lib/session";

export interface NavLink {
  href: string;
  label: string;
}

const ADMIN_LINKS: NavLink[] = [
  { href: "/admin/users", label: "Users" },
  { href: "/admin/organizations", label: "Organizations" },
  { href: "/admin/clauses", label: "Clauses" },
  { href: "/admin/holidays", label: "Holidays" },
  { href: "/admin/settings", label: "Settings" },
];

/** Links a session can actually use, mirroring the page guards. Pure: the layout builds it server-side. */
export function navFor(ctx: SessionContext): NavLink[] {
  if (!ctx) {
    return [
      { href: "/solicitations", label: "Solicitations" },
      { href: "/login", label: "Sign in" },
    ];
  }
  let links: NavLink[];
  if (ctx.orgKind === "bidder") {
    links = [
      { href: "/bidder#my-bids", label: "My bids" },
      { href: "/bidder", label: "Open solicitations" },
    ];
  } else if (ctx.orgKind === "agency") {
    links = [{ href: "/agency", label: "My solicitations" }];
  } else {
    links = [
      { href: "/office", label: "Review queue" },
      { href: "/office#published", label: "Published" },
    ];
  }
  return ctx.isAdmin ? [...links, ...ADMIN_LINKS] : links;
}

/**
 * Whether a nav link marks the current page. Hash links are never current. "/" matches exactly; every
 * other link matches its own path and anything nested under it (on a segment boundary, so /office does
 * not match /office-hours).
 */
export function isCurrentLink(href: string, pathname: string): boolean {
  if (href.includes("#")) return false;
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(href + "/");
}

/** aria-current value for a nav link: "page" only on an exact path match, "true" when the page is nested under the link's section. */
export function currentValue(href: string, pathname: string): "page" | "true" | undefined {
  if (!isCurrentLink(href, pathname)) return undefined;
  return pathname === href ? "page" : "true";
}
