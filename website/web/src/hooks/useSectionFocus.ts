"use client";

import {useEffect, useState} from "react";

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
