import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Garage ya Joe | Garage & Auto Spares",
  description: "Vehicle servicing, repairs, spare parts and special-order imports in one place."
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
