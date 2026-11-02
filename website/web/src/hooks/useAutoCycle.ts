"use client";

import {useEffect, useRef, useState, type FocusEvent, type RefObject} from "react";

export interface AutoCycle {
  index: number;
  setIndex: (i: number) => void;
  /** True while the slideshow is advancing: playing, on screen and not held by hover or focus. */
  running: boolean;
  /** Duration of the current step, for progress bars. */
  duration: number;
  bind: {
    onMouseEnter: () => void;
    onMouseLeave: () => void;
    onFocus: () => void;
    onBlur: (e: FocusEvent<HTMLElement>) => void;
  };
}

/**
 * An Apple Store style slideshow clock. It advances only while `playing`, while its element is on
 * screen, and while the visitor is not hovering or focusing it. Picking a step restarts the timer.
 */
export function useAutoCycle<T extends HTMLElement>(length: number, ms: number | ((i: number) => number), playing: boolean): [RefObject<T | null>, AutoCycle] {
  const ref = useRef<T>(null);
  const [index, setIndex] = useState(0);
  const [held, setHeld] = useState(false);
  const [visible, setVisible] = useState(false);
  const duration = typeof ms === "number" ? ms : ms(index);
  const running = playing && visible && !held && length > 1;

  useEffect(() => {
    const element = ref.current;
    if (!element || !("IntersectionObserver" in window)) return;
    const io = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting), {threshold: .25});
    io.observe(element);
    return () => io.disconnect();
  }, []);

  useEffect(() => {
    if (!running) return;
    const timer = window.setTimeout(() => setIndex(i => (i + 1) % length), duration);
    return () => window.clearTimeout(timer);
  }, [running, index, duration, length]);

  return [ref, {
    index: index % Math.max(1, length), setIndex, running, duration,
    bind: {
      onMouseEnter: () => setHeld(true),
      onMouseLeave: () => setHeld(false),
      onFocus: () => setHeld(true),
      onBlur: e => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setHeld(false); },
    },
  }];
}
