"use client";

import { useActionState, useState } from "react";
import { registerCompany } from "./actions";

export function RegisterForm() {
  const [state, action, pending] = useActionState(registerCompany, undefined);
  const [resident, setResident] = useState(false);
  return (
    <form action={action} style={{ display: "grid", gap: 8 }}>
      <label>
        Company legal name
        <input name="legalName" required />
      </label>
      <label>
        Address
        <input name="address" autoComplete="street-address" required />
      </label>
      <label>
        Contact name
        <input name="contactName" autoComplete="name" required />
      </label>
      <label>
        Contact phone
        <input name="contactPhone" type="tel" autoComplete="tel" required />
      </label>
      <label>
        Contact email
        <input name="contactEmail" type="email" required />
      </label>
      <label>
        <input
          name="residentClaimed"
          type="checkbox"
          checked={resident}
          onChange={(e) => setResident(e.target.checked)}
        />{" "}
        We claim resident bidder status
      </label>
      {resident && (
        <label>
          Resident certificate number
          <input name="residentCertificate" required />
        </label>
      )}
      {state?.message && <p role="alert" className="error">{state.message}</p>}
      <button type="submit" disabled={pending}>{pending ? "Registering..." : "Register company"}</button>
    </form>
  );
}
