"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { currentValue, type NavLink } from "./nav";

/** Links are computed on the server; this only marks the current page. Nested pages mark their section; hash links are never marked. */
export function AppNav({ links }: { links: NavLink[] }) {
  const pathname = usePathname();
  return (
    <nav aria-label="Main" className="ui-nav">
      {links.map((l) => (
        <Link key={l.href} href={l.href} aria-current={currentValue(l.href, pathname)}>
          {l.label}
        </Link>
      ))}
    </nav>
  );
}
