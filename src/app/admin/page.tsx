import { requireAdminPage } from "./guard";

export const dynamic = "force-dynamic";

const LINKS = [
  ["/admin/users", "Users", "Invite staff and assign them to an organization."],
  ["/admin/organizations", "Organizations", "Agencies and the procurement office."],
  ["/admin/clauses", "Clauses", "Versioned clause text used in published documents."],
  ["/admin/holidays", "Holidays", "Days skipped by the calendar-day date rules."],
  ["/admin/settings", "Settings", "State and office names, time zone, fiscal year."],
] as const;

export default async function AdminHome() {
  await requireAdminPage();
  return (
    <main>
      <h1>Administration</h1>
      <ul>
        {LINKS.map(([href, name, blurb]) => (
          <li key={href}>
            <a href={href}>{name}</a> - {blurb}
          </li>
        ))}
      </ul>
    </main>
  );
}
