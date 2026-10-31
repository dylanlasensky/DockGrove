"use client";

import { useEffect, useRef, type RefObject } from "react";

/*
 * Port of the scroll-reveal in website/public/home.js:
 *
 *   const reduced = matchMedia('(prefers-reduced-motion: reduce)');
 *   if ('IntersectionObserver' in window && !reduced.matches) {
 *     observer = new IntersectionObserver(..., { threshold: 0.08 });  // adds .is-visible once
 *     document.documentElement.classList.add('motion-ready');
 *     reduced.addEventListener('change', e => { if (e.matches) { remove 'motion-ready'; disconnect } });
 *   }
 *
 * The matching CSS (`.reveal`, `.motion-ready .reveal`, `.motion-ready .reveal.is-visible`)
 * lives in src/app/globals.css. Put `className="reveal"` on the element you attach the ref to.
 * Without JavaScript (or with Reduced Motion) everything stays visible, as in the original.
 */

const QUERY = "(prefers-reduced-motion: reduce)";
const MOTION_READY = "motion-ready";
const VISIBLE = "is-visible";

let observer: IntersectionObserver | null = null;
let disabled = false;

function getObserver(): IntersectionObserver | null {
  if (observer || disabled) return observer;
  if (typeof window === "undefined" || !("IntersectionObserver" in window)) return null;
  const reduced = window.matchMedia(QUERY);
  if (reduced.matches) return null;

  const io = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add(VISIBLE);
          io.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.08 },
  );
  document.documentElement.classList.add(MOTION_READY);
  reduced.addEventListener("change", (event) => {
    if (event.matches) {
      document.documentElement.classList.remove(MOTION_READY);
      io.disconnect();
      observer = null;
      disabled = true;
    }
  });
  observer = io;
  return io;
}

/**
 * Attach the returned ref to an element with `className="reveal"`; it fades/slides in the
 * first time 8% of it enters the viewport, exactly like the original `.reveal` elements.
 */
export function useReveal<T extends HTMLElement>(): RefObject<T | null> {
  const ref = useRef<T>(null);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const io = getObserver();
    if (!io) return;
    io.observe(element);
    return () => io.unobserve(element);
  }, []);

  return ref;
}

export default useReveal;
