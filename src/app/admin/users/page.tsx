import { createServerClient } from "@/lib/supabase/server";
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
    <main>
      <p><a href="/admin">Administration</a></p>
      <h1>Users</h1>

      <h2>Invite a user</h2>
      <p>The user receives an email invitation. No self-signup exists for staff.</p>
      <ActionForm action={createUser} submitLabel="Send invitation" className="sol-form">
        <div className="row">
          <label>Email <input name="email" type="email" required /></label>
          <label>Display name <input name="displayName" required /></label>
          <label>
            Organization{" "}
            <select name="orgId" required defaultValue="">
              <option value="" disabled>Choose...</option>
              {invitable.map((o) => (
                <option key={o.id} value={o.id}>{o.name} ({o.kind})</option>
              ))}
            </select>
          </label>
          <label className="inline"><input name="isAdmin" type="checkbox" /> Administrator</label>
        </div>
      </ActionForm>

      <h2>Existing users</h2>
      <table className="list">
        <thead><tr><th>Name</th><th>Organization</th><th>Administrator</th></tr></thead>
        <tbody>
          {profiles.data!.map((p) => (
            <tr key={p.user_id}>
              <td>{p.display_name}</td>
              <td>{orgName.get(p.org_id) ?? ""}</td>
              <td>{p.is_admin ? "Yes" : ""}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
