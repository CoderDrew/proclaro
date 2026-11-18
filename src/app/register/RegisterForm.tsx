"use client";

import { useActionState, useState } from "react";
import { Button, Choice, Field, Notice } from "@/components/ui";
import { registerCompany } from "./actions";

export function RegisterForm() {
  const [state, action, pending] = useActionState(registerCompany, undefined);
  const [resident, setResident] = useState(false);
  return (
    <form action={action} className="ui-form">
      <Field label="Company legal name">
        <input name="legalName" required />
      </Field>
      <Field label="Address">
        <input name="address" autoComplete="street-address" required />
      </Field>
      <Field label="Contact name">
        <input name="contactName" autoComplete="name" required />
      </Field>
      <Field label="Contact phone">
        <input name="contactPhone" type="tel" autoComplete="tel" required />
      </Field>
      <Field label="Contact email">
        <input name="contactEmail" type="email" required />
      </Field>
      <Choice label="We claim resident bidder status">
        <input
          name="residentClaimed"
          type="checkbox"
          checked={resident}
          onChange={(e) => setResident(e.target.checked)}
        />
      </Choice>
      {resident && (
        <Field label="Resident certificate number">
          <input name="residentCertificate" required />
        </Field>
      )}
      {state?.message && <Notice tone="error" role="alert">{state.message}</Notice>}
      <Button type="submit" variant="primary" loading={pending}>{pending ? "Registering..." : "Register company"}</Button>
    </form>
  );
}
