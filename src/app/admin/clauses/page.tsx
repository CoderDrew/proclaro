import { CLAUSE_KEYS, CLAUSE_VARIABLES } from "@/documents/clauseKeys";
import { createServerClient } from "@/lib/supabase/server";
import { ActionForm } from "../ActionForm";
import { requireAdminPage } from "../guard";
import { saveClauseForm } from "./actions";

export const dynamic = "force-dynamic";

export default async function ClausesPage() {
  await requireAdminPage();
  const supabase = await createServerClient();
  const [clauses, people] = await Promise.all([
    supabase.from("clauses").select("key, version, body, created_by, created_at").order("version", { ascending: false }),
    supabase.from("profiles").select("user_id, display_name"),
  ]);
  for (const r of [clauses, people]) if (r.error) throw new Error(r.error.message);
  const who = new Map(people.data!.map((p) => [p.user_id, p.display_name]));

  return (
    <main>
      <p><a href="/admin">Administration</a></p>
      <h1>Clauses</h1>
      <p>
        Saving creates a new version; earlier versions are kept and cannot be changed. A solicitation locks the
        versions in force when it is sent to check, so later edits do not change it. Blank lines separate paragraphs;
        a paragraph starting with <code>#&nbsp;</code> is a heading.
      </p>
      <p>
        Variables you may use:{" "}
        {CLAUSE_VARIABLES.map((v) => <code key={v} style={{ marginRight: 6 }}>{`{{${v}}}`}</code>)}
      </p>

      {CLAUSE_KEYS.map((key) => {
        const versions = clauses.data!.filter((c) => c.key === key);
        const latest = versions[0];
        return (
          <section key={key} style={{ margin: "20px 0", borderTop: "1px solid #ccc", paddingTop: 8 }}>
            <h2 id={key}>{key} {latest && <small>(version {latest.version})</small>}</h2>
            <ActionForm action={saveClauseForm.bind(null, key)} submitLabel="Save as new version" className="sol-form">
              <textarea name="body" rows={10} defaultValue={latest?.body ?? ""} aria-label={`Text of ${key}`} />
              <br />
            </ActionForm>
            <details>
              <summary>Version history ({versions.length})</summary>
              {versions.map((v) => (
                <div key={v.version} style={{ margin: "8px 0" }}>
                  <strong>Version {v.version}</strong>
                  {" - "}
                  {v.created_by ? who.get(v.created_by) ?? "unknown" : "seed"}, {new Date(v.created_at).toISOString().slice(0, 10)}
                  <pre style={{ whiteSpace: "pre-wrap", background: "#f6f6f6", padding: 6 }}>{v.body}</pre>
                </div>
              ))}
            </details>
          </section>
        );
      })}
    </main>
  );
}
