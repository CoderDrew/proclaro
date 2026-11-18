import { createServerClient } from "@/lib/supabase/server";
import { Card, Choice, Field, FieldGrid, Page, PageHeader, Table, Td, Th } from "@/components/ui";
import { ActionForm } from "../ActionForm";
import { requireAdminPage } from "../guard";
import { createUser } from "./actions";
import { INVITABLE_ORG_KINDS } from "./logic";

export const dynamic = "force-dynamic";

export default async function UsersPage() {
  await requireAdminPage();
  const supabase = await createServerClient();
  const [orgs, profiles] = await Promise.all([
    supabase.from("organizations").select("id, name, kind").order("name"),
    supabase.from("profiles").select("user_id, display_name, org_id, is_admin").order("display_name"),
  ]);
  for (const r of [orgs, profiles]) if (r.error) throw new Error(r.error.message);
  const orgName = new Map(orgs.data!.map((o) => [o.id, o.name]));
  // Staff are invited into agencies and offices only; bidder orgs are never offered (and the action refuses them).
  const invitable = orgs.data!.filter((o) => (INVITABLE_ORG_KINDS as readonly string[]).includes(o.kind));

  return (
    <Page width="full">
      <PageHeader crumbs={<a href="/admin">Administration</a>} title="Users" />

      <Card title="Invite a user">
        <p className="muted">The user receives an email invitation. No self-signup exists for staff.</p>
        <ActionForm action={createUser} submitLabel="Send invitation" className="ui-form">
          <FieldGrid>
            <Field label="Email"><input name="email" type="email" required /></Field>
            <Field label="Display name"><input name="displayName" required /></Field>
            <Field label="Organization">
              <select name="orgId" required defaultValue="">
                <option value="" disabled>Choose...</option>
                {invitable.map((o) => (
                  <option key={o.id} value={o.id}>{o.name} ({o.kind})</option>
                ))}
              </select>
            </Field>
            <Choice label="Administrator"><input name="isAdmin" type="checkbox" /></Choice>
          </FieldGrid>
        </ActionForm>
      </Card>

      <Card title="Existing users">
        <Table>
          <thead><tr><Th>Name</Th><Th>Organization</Th><Th>Administrator</Th></tr></thead>
          <tbody>
            {profiles.data!.map((p) => (
              <tr key={p.user_id}>
                <Td>{p.display_name}</Td>
                <Td>{orgName.get(p.org_id) ?? ""}</Td>
                <Td>{p.is_admin ? "Yes" : ""}</Td>
              </tr>
            ))}
          </tbody>
        </Table>
      </Card>
    </Page>
  );
}
