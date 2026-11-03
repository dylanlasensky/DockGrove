"use client";

import type {CSSProperties, ReactNode} from "react";
import {useReveal} from "@/hooks/useReveal";
import s from "./Showcase.module.css";

/** Fades, unblurs and lifts its children the first time they scroll into view. `step` staggers siblings. */
export default function Reveal({children, step = 0, className = ""}: {children: ReactNode; step?: number; className?: string}) {
  const ref = useReveal<HTMLDivElement>();
  return <div ref={ref} className={`${s.rise} ${className}`} style={{"--step": step} as CSSProperties}>{children}</div>;
}
