import { createServerClient } from "@/lib/supabase/server";
import { Card, Field, FieldGrid, Page, PageHeader, Table, Td, Th } from "@/components/ui";
import { ActionForm } from "../ActionForm";
import { requireAdminPage } from "../guard";
import { createOrganization, renameOrganization } from "./actions";

export const dynamic = "force-dynamic";

export default async function OrganizationsPage() {
  await requireAdminPage();
  const supabase = await createServerClient();
  // Bidder orgs are created by bidder registration and named by the bidder; admins cannot create or rename them.
  const { data, error } = await supabase.from("organizations").select("id, name, kind").neq("kind", "bidder").order("name");
  if (error) throw new Error(error.message);

  return (
    <Page width="full">
      <PageHeader crumbs={<a href="/admin">Administration</a>} title="Organizations" />

      <Card title="Create">
        <ActionForm action={createOrganization} submitLabel="Create" className="ui-form">
          <FieldGrid>
            <Field label="Name"><input name="name" required /></Field>
            <Field label="Kind">
              <select name="kind" defaultValue="agency">
                <option value="agency">Agency</option>
                <option value="office">Procurement office</option>
              </select>
            </Field>
          </FieldGrid>
        </ActionForm>
      </Card>

      <Card title="Rename">
        <Table>
          <thead><tr><Th>Kind</Th><Th>Name</Th></tr></thead>
          <tbody>
            {data!.map((o) => (
              <tr key={o.id}>
                <Td>{o.kind}</Td>
                <Td>
                  <ActionForm
                    action={renameOrganization}
                    submitLabel="Rename"
                    submitVariant="secondary"
                    submitAriaLabel={`Rename ${o.name}`}
                    className="ui-inline-form"
                  >
                    <input type="hidden" name="id" value={o.id} />
                    <input name="name" defaultValue={o.name} required aria-label={`Name of ${o.name}`} />
                  </ActionForm>
                </Td>
              </tr>
            ))}
          </tbody>
        </Table>
      </Card>
    </Page>
  );
}
