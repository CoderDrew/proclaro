import { createServerClient } from "@/lib/supabase/server";
import { ActionForm } from "../ActionForm";
import { requireAdminPage } from "../guard";
import { addHoliday, removeHoliday } from "./actions";

export const dynamic = "force-dynamic";

export default async function HolidaysPage() {
  await requireAdminPage();
  const supabase = await createServerClient();
  const { data, error } = await supabase.from("holidays").select("day, name").order("day");
  if (error) throw new Error(error.message);

  return (
    <main>
      <p><a href="/admin">Administration</a></p>
      <h1>Holidays</h1>
      <p>Holidays are local dates (YYYY-MM-DD). The date rules skip them when counting days.</p>

      <h2>Add</h2>
      <ActionForm action={addHoliday} submitLabel="Add" className="sol-form">
        <div className="row">
          <label>Date <input name="day" type="date" required /></label>
          <label>Name <input name="name" required /></label>
        </div>
      </ActionForm>

      <h2>Existing</h2>
      {data!.length === 0 ? (
        <p>No holidays are set.</p>
      ) : (
        <table className="list">
          <thead><tr><th>Date</th><th>Name</th><th /></tr></thead>
          <tbody>
            {data!.map((h) => (
              <tr key={h.day}>
                <td>{h.day}</td>
                <td>{h.name}</td>
                <td>
                  <ActionForm action={removeHoliday} submitLabel="Remove">
                    <input type="hidden" name="day" value={h.day} />
                  </ActionForm>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </main>
  );
}
