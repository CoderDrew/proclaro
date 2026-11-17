import { redirect } from "next/navigation";
import { getSessionContext, homePathFor } from "@/lib/session";

export default async function Home() {
  redirect(homePathFor(await getSessionContext()));
}
