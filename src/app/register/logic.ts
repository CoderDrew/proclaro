// Company registration input checks and error text. Pure: no Next, no Supabase.

export type RegistrationInput = {
  legalName: string;
  address: string;
  contactName: string;
  contactPhone: string;
  contactEmail: string;
  residentClaimed: boolean;
  residentCertificate: string | null;
};

function text(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function parseRegistration(
  form: Record<string, unknown>,
): { ok: true; value: RegistrationInput } | { ok: false; message: string } {
  const legalName = text(form.legalName);
  const address = text(form.address);
  const contactName = text(form.contactName);
  const contactPhone = text(form.contactPhone);
  const contactEmail = text(form.contactEmail);
  const residentClaimed = form.residentClaimed === "on" || form.residentClaimed === true;
  const cert = text(form.residentCertificate);

  if (!legalName) return { ok: false, message: "Enter the company's legal name." };
  if (!address) return { ok: false, message: "Enter the company's address." };
  if (!contactName) return { ok: false, message: "Enter a contact name." };
  if (!contactPhone) return { ok: false, message: "Enter a contact phone number." };
  if (!contactEmail) return { ok: false, message: "Enter a contact email address." };
  if (residentClaimed && !cert) return { ok: false, message: "Enter the resident certificate number." };

  return {
    ok: true,
    value: {
      legalName, address, contactName, contactPhone, contactEmail,
      residentClaimed,
      residentCertificate: residentClaimed ? cert : null,
    },
  };
}

/** Plain-language text for a register_bidder error code. */
export function registerErrorMessage(code: string): string {
  switch (code) {
    case "name_taken":
      return "A company with that legal name is already registered.";
    case "not_authorized":
      return "This account was invited as staff and cannot register a company. Sign in with your staff account instead.";
    case "invalid_data":
      return "Some details are missing or invalid. Please check the form and try again.";
    default:
      return "The company could not be registered. Try again.";
  }
}
