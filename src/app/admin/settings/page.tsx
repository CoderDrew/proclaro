import { createServerClient } from "@/lib/supabase/server";
import { Card, Field, FieldGrid, Page, PageHeader } from "@/components/ui";
import { ActionForm } from "../ActionForm";
import { requireAdminPage } from "../guard";
import { saveSettings } from "./actions";
import { ianaZones } from "./logic";

export const dynamic = "force-dynamic";

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

export default async function SettingsPage() {
  await requireAdminPage();
  const supabase = await createServerClient();
  const { data, error } = await supabase
    .from("settings")
    .select("state_name, office_name, timezone, fiscal_year_start_month")
    .eq("id", 1)
    .single();
  if (error) throw new Error(error.message);

  return (
    <Page width="full">
      <PageHeader crumbs={<a href="/admin">Administration</a>} title="Settings" />
      <Card>
        <ActionForm action={saveSettings} className="ui-form">
          <FieldGrid>
            <Field label="State name"><input name="stateName" defaultValue={data.state_name} required /></Field>
            <Field label="Office name"><input name="officeName" defaultValue={data.office_name} required /></Field>
            <Field label="Time zone">
              <select name="timezone" defaultValue={data.timezone}>
                {ianaZones().map((z) => <option key={z} value={z}>{z}</option>)}
              </select>
            </Field>
            <Field label="Fiscal year starts in">
              <select name="fiscalYearStartMonth" defaultValue={String(data.fiscal_year_start_month)}>
                {MONTHS.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
              </select>
            </Field>
          </FieldGrid>
        </ActionForm>
      </Card>
    </Page>
  );
}
