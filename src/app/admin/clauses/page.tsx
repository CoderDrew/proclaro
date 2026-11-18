import { CLAUSE_KEYS, CLAUSE_VARIABLES } from "@/documents/clauseKeys";
import { createServerClient } from "@/lib/supabase/server";
import { Card, Page, PageHeader } from "@/components/ui";
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
    <Page width="full">
      <PageHeader crumbs={<a href="/admin">Administration</a>} title="Clauses" />
      <p>
        Saving creates a new version; earlier versions are kept and cannot be changed. A solicitation locks the
        versions in force when it is sent to check, so later edits do not change it. Blank lines separate paragraphs;
        a paragraph starting with <code>#&nbsp;</code> is a heading.
      </p>
      <p>
        Variables you may use:{" "}
        {CLAUSE_VARIABLES.map((v) => <code key={v} className="ui-code-list">{`{{${v}}}`}</code>)}
      </p>

      {CLAUSE_KEYS.map((key) => {
        const versions = clauses.data!.filter((c) => c.key === key);
        const latest = versions[0];
        return (
          <Card
            key={key}
            titleId={key}
            title={<>{key} {latest && <small className="muted">(version {latest.version})</small>}</>}
          >
            <ActionForm action={saveClauseForm.bind(null, key)} submitLabel="Save as new version" submitAriaLabel={`Save ${key} as new version`} className="ui-form">
              <textarea name="body" rows={10} defaultValue={latest?.body ?? ""} aria-label={`Text of ${key}`} />
            </ActionForm>
            <details>
              <summary>Version history ({versions.length})</summary>
              {versions.map((v) => (
                <div key={v.version} className="ui-clause-version">
                  <strong>Version {v.version}</strong>
                  {" - "}
                  {v.created_by ? who.get(v.created_by) ?? "unknown" : "seed"}, {new Date(v.created_at).toISOString().slice(0, 10)}
                  <pre className="ui-pre">{v.body}</pre>
                </div>
              ))}
            </details>
          </Card>
        );
      })}
    </Page>
  );
}
