import type { Metadata } from "next";
import "./globals.css";
import {BusinessBrandingProvider} from "./components/business-branding";

export const metadata: Metadata = {
  title: "Garage ya Joe | Automotive Care & Auto Spares",
  description: "Vehicle servicing, repairs, quality auto spares and specialist parts sourcing."
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body><BusinessBrandingProvider>{children}</BusinessBrandingProvider></body></html>;
}
