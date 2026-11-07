import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "The Garage | Automotive Care & Auto Spares",
  description: "The Garage — expert vehicle servicing, repairs, quality auto spares and specialist parts sourcing."
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
