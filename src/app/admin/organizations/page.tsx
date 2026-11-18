import { createServerClient } from "@/lib/supabase/server";
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
    <main>
      <p><a href="/admin">Administration</a></p>
      <h1>Organizations</h1>

      <h2>Create</h2>
      <ActionForm action={createOrganization} submitLabel="Create" className="sol-form">
        <div className="row">
          <label>Name <input name="name" required /></label>
          <label>
            Kind{" "}
            <select name="kind" defaultValue="agency">
              <option value="agency">Agency</option>
              <option value="office">Procurement office</option>
            </select>
          </label>
        </div>
      </ActionForm>

      <h2>Rename</h2>
      <table className="list">
        <thead><tr><th>Kind</th><th>Name</th></tr></thead>
        <tbody>
          {data!.map((o) => (
            <tr key={o.id}>
              <td>{o.kind}</td>
              <td>
                <ActionForm action={renameOrganization} submitLabel="Rename">
                  <input type="hidden" name="id" value={o.id} />
                  <input name="name" defaultValue={o.name} required aria-label={`Name of ${o.name}`} />{" "}
                </ActionForm>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
