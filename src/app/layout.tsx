import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { AppShell } from "@/components/ui/AppShell";
import { getSessionContext } from "@/lib/session";
import { createServerClient } from "@/lib/supabase/server";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" });

export const metadata: Metadata = {
  title: "Proclaro",
  description: "Solicitation setup and review",
};

export default async function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const ctx = await getSessionContext();
  let orgName = "";
  if (ctx) {
    const supabase = await createServerClient();
    const { data } = await supabase
      .from("organizations")
      .select("name")
      .eq("id", ctx.orgId)
      .maybeSingle();
    orgName = data?.name ?? "";
  }

  return (
    <html lang="en" className={inter.variable}>
      <body>
        <AppShell ctx={ctx} orgName={orgName}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
