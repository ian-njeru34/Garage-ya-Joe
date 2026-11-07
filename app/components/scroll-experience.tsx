"use client";

import { useEffect, useRef, type ReactNode } from "react";

export default function ScrollExperience({ children }: { children: ReactNode }) {
  const endRef = useRef<HTMLDivElement>(null);

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
    let hasReturned = false;
    let waitingAtBottom = false;

    const checkPageBottom = () => {
      if (reducedMotion.matches || hasReturned) return;

      const atBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 3;

      if (atBottom && !waitingAtBottom) {
        waitingAtBottom = true;
        // Begin the full six-second pause only once the real page bottom is reached.
        returnTimer = setTimeout(() => {
          const stillAtBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 3;
          if (stillAtBottom) {
            hasReturned = true;
            window.scrollTo({ top: 0, behavior: "smooth" });
          } else {
            waitingAtBottom = false;
          }
        }, 6000);
      } else if (!atBottom && waitingAtBottom) {
        if (returnTimer) clearTimeout(returnTimer);
        returnTimer = undefined;
        waitingAtBottom = false;
      }
    };

    window.addEventListener("scroll", checkPageBottom, { passive: true });
    window.addEventListener("resize", checkPageBottom);
    checkPageBottom();

    return () => {
      revealObserver.disconnect();
      window.removeEventListener("scroll", checkPageBottom);
      window.removeEventListener("resize", checkPageBottom);
      if (returnTimer) clearTimeout(returnTimer);
    };
  }, []);

  return <>{children}<div ref={endRef} className="page-end-sentinel" aria-hidden="true" /></>;
}
