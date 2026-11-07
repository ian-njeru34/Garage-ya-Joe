"use client";

import { useEffect, useRef, type ReactNode } from "react";

export default function ScrollExperience({ children }: { children: ReactNode }) {
  const endRef = useRef<HTMLDivElement>(null);
  const looping = useRef(false);

  useEffect(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const revealObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          revealObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -35px 0px" });

    document.querySelectorAll("[data-reveal]").forEach((element) => revealObserver.observe(element));

    let returnTimer: ReturnType<typeof setTimeout> | undefined;
    const footerObserver = new IntersectionObserver((entries) => {
      if (reducedMotion.matches || looping.current) return;
      if (entries.some((entry) => entry.isIntersecting)) {
        looping.current = true;
        returnTimer = setTimeout(() => {
          window.scrollTo({ top: 0, behavior: "smooth" });
        }, 850);
      }
    }, { threshold: 0.9 });

    if (endRef.current) footerObserver.observe(endRef.current);

    const resetLoop = () => {
      if (window.scrollY < 100 && looping.current) {
        looping.current = false;
      }
    };
    window.addEventListener("scroll", resetLoop, { passive: true });

    return () => {
      revealObserver.disconnect();
      footerObserver.disconnect();
      window.removeEventListener("scroll", resetLoop);
      if (returnTimer) clearTimeout(returnTimer);
    };
  }, []);

  return <>{children}<div ref={endRef} className="page-end-sentinel" aria-hidden="true" /></>;
}
