import { Card, Page, PageHeader } from "@/components/ui";
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
    <Page width="full">
      <PageHeader title="Administration" />
      <div className="ui-link-grid">
        {LINKS.map(([href, name, blurb]) => (
          <Card key={href} className="ui-link-card">
            <a href={href}>{name}</a>
            <p className="muted">{blurb}</p>
          </Card>
        ))}
      </div>
    </Page>
  );
}
