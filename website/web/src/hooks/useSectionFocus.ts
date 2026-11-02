"use client";

import {useEffect, useRef, useState, type RefObject} from "react";

/** The id of the section crossing the middle of the window, or "" above the first one. */
export function useSectionFocus(ids: readonly string[]): string {
  const [active, setActive] = useState("");
  const key = ids.join(" ");
  useEffect(() => {
    if (!("IntersectionObserver" in window)) return;
    const io = new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) setActive(entry.target.id);
    }, {rootMargin: "-45% 0px -50% 0px"});
    const elements = key.split(" ").map(id => document.getElementById(id)).filter((e): e is HTMLElement => !!e);
    elements.forEach(e => io.observe(e));
    return () => io.disconnect();
  }, [key]);
  return active;
}

/** True once the element has had real focus in the window (a third of it visible). Stays true. */
export function useSeen<T extends HTMLElement>(): [RefObject<T | null>, boolean] {
  const ref = useRef<T>(null);
  const [seen, setSeen] = useState(false);
  useEffect(() => {
    const element = ref.current;
    if (!element || seen || !("IntersectionObserver" in window)) return;
    const io = new IntersectionObserver(([entry]) => { if (entry.isIntersecting) { setSeen(true); io.disconnect(); } }, {threshold: .35});
    io.observe(element);
    return () => io.disconnect();
  }, [seen]);
  return [ref, seen];
}

/** 0 → 1 as the element scrolls through a pinned stretch of the window. Reduced Motion jumps to 1. */
export function useScrollProgress<T extends HTMLElement>(reduced: boolean): [RefObject<T | null>, number] {
  const ref = useRef<T>(null);
  const [progress, setProgress] = useState(0);
  useEffect(() => {
    if (reduced) return;
    let frame = 0;
    const update = () => {
      frame = 0;
      const element = ref.current;
      if (!element) return;
      const box = element.getBoundingClientRect();
      const travel = box.height - window.innerHeight;
      setProgress(travel > 0 ? Math.min(1, Math.max(0, -box.top / travel)) : 1);
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(update); };
    update();
    window.addEventListener("scroll", schedule, {passive: true});
    window.addEventListener("resize", schedule);
    return () => { cancelAnimationFrame(frame); window.removeEventListener("scroll", schedule); window.removeEventListener("resize", schedule); };
  }, [reduced]);
  return [ref, reduced ? 1 : progress];
}
