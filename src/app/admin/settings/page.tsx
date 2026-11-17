import { createServerClient } from "@/lib/supabase/server";
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
    <main>
      <p><a href="/admin">Administration</a></p>
      <h1>Settings</h1>
      <ActionForm action={saveSettings} className="sol-form">
        <div className="grid">
          <label>State name <input name="stateName" defaultValue={data.state_name} required /></label>
          <label>Office name <input name="officeName" defaultValue={data.office_name} required /></label>
          <label>
            Time zone
            <select name="timezone" defaultValue={data.timezone}>
              {ianaZones().map((z) => <option key={z} value={z}>{z}</option>)}
            </select>
          </label>
          <label>
            Fiscal year starts in
            <select name="fiscalYearStartMonth" defaultValue={String(data.fiscal_year_start_month)}>
              {MONTHS.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
            </select>
          </label>
        </div>
      </ActionForm>
    </main>
  );
}
