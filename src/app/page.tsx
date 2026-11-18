import { redirect } from "next/navigation";
import { getAuthState, landingPathFor } from "@/lib/session";

export default async function Home() {
  redirect(landingPathFor(await getAuthState()));
}
