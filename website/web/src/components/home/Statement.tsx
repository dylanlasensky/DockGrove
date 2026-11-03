"use client";

import type {CSSProperties} from "react";
import {useReducedMotion} from "@/hooks/useReducedMotion";
import {useScrollProgress} from "@/hooks/useSectionFocus";
import s from "./Showcase.module.css";

const WORDS = "Your apps. Live widgets. A shelf in the notch. Menus that feel like a Mac. And a small friend who keeps you company. All within reach.".split(" ");

/** A pinned statement whose words light up one by one as the window scrolls past, Apple Store style. */
export default function Statement() {
  const reduced = useReducedMotion();
  const [ref, progress] = useScrollProgress<HTMLElement>(reduced);
  const lit = progress * (WORDS.length + 2);
  return <section ref={ref} className={s.statement} aria-label="DockGrove in a sentence">
    <div className={s.statementPin}>
      <p className={s.statementText} style={{"--p": progress} as CSSProperties}>
        {WORDS.map((word, i) => <span key={i} className={lit > i ? s.lit : ""}>{word} </span>)}
      </p>
    </div>
  </section>;
}
