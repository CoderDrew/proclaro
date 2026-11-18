import { createServerClient } from "@/lib/supabase/server";
import { Card, EmptyState, Field, FieldGrid, Page, PageHeader, Table, Td, Th } from "@/components/ui";
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
    <Page width="full">
      <PageHeader crumbs={<a href="/admin">Administration</a>} title="Holidays" />
      <p className="muted">Holidays are local dates (YYYY-MM-DD). The date rules skip them when counting days.</p>

      <Card title="Add">
        <ActionForm action={addHoliday} submitLabel="Add" className="ui-form">
          <FieldGrid>
            <Field label="Date"><input name="day" type="date" required /></Field>
            <Field label="Name"><input name="name" required /></Field>
          </FieldGrid>
        </ActionForm>
      </Card>

      <Card title="Existing">
        {data!.length === 0 ? (
          <EmptyState>No holidays are set.</EmptyState>
        ) : (
          <Table>
            <thead><tr><Th>Date</Th><Th>Name</Th><Th /></tr></thead>
            <tbody>
              {data!.map((h) => (
                <tr key={h.day}>
                  <Td>{h.day}</Td>
                  <Td>{h.name}</Td>
                  <Td>
                    <ActionForm
                      action={removeHoliday}
                      submitLabel="Remove"
                      submitVariant="danger"
                      submitAriaLabel={`Remove holiday ${h.day}`}
                      className="ui-inline-form"
                    >
                      <input type="hidden" name="day" value={h.day} />
                    </ActionForm>
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </Page>
  );
}
