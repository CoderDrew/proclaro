"use server";

import { redirect } from "next/navigation";
import { createServerClient } from "@/lib/supabase/server";
import { getAuthState, landingPathFor } from "@/lib/session";
import { parseRegistration, registerErrorMessage } from "./logic";

export type RegisterState = { ok: false; message: string } | undefined;

export async function registerCompany(_prev: RegisterState, formData: FormData): Promise<RegisterState> {
  const state = await getAuthState();
  if (state.status !== "unregistered" || state.invited) redirect(landingPathFor(state));

  const parsed = parseRegistration({
    legalName: formData.get("legalName"),
    address: formData.get("address"),
    contactName: formData.get("contactName"),
    contactPhone: formData.get("contactPhone"),
    contactEmail: formData.get("contactEmail"),
    residentClaimed: formData.get("residentClaimed"),
    residentCertificate: formData.get("residentCertificate"),
  });
  if (!parsed.ok) return { ok: false, message: parsed.message };
  const v = parsed.value;

  const supabase = await createServerClient();
  const { error } = await supabase.rpc("register_bidder", {
    p_legal_name: v.legalName,
    p_address: v.address,
    p_contact_name: v.contactName,
    p_contact_phone: v.contactPhone,
    p_contact_email: v.contactEmail,
    p_resident_claimed: v.residentClaimed,
    p_resident_certificate: v.residentCertificate as string,
  });
  if (error) {
    if (error.message === "already_registered") redirect(landingPathFor(await getAuthState()));
    return { ok: false, message: registerErrorMessage(error.message) };
  }
  redirect("/bidder");
}
