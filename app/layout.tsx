import type { Metadata } from "next";
import "./globals.css";
import {BusinessBrandingProvider} from "./components/business-branding";
import {createClient} from "@supabase/supabase-js";

export async function generateMetadata(): Promise<Metadata> {
  let businessName = "Garage ya Joe";
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (url && key) {
    try {
      const {data,error} = await createClient(url,key).rpc("get_public_business_branding");
      if (!error && typeof data === "string" && data.trim()) businessName = data.trim();
    } catch {
      // Keep a safe fallback if the public branding lookup is temporarily unavailable.
    }
  }
  return {
    title: businessName + " | Automotive Care & Auto Spares",
    description: businessName + " — expert vehicle servicing, repairs, quality auto spares and specialist parts sourcing."
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body><BusinessBrandingProvider>{children}</BusinessBrandingProvider></body></html>;
}
