"use client";

import { ChevronUp } from "lucide-react";

export default function BackToTop() {
  return <button type="button" className="back-top" aria-label="Back to top" onClick={() => window.scrollTo({ top: 0, behavior: "smooth" })}><ChevronUp size={20}/></button>;
}
