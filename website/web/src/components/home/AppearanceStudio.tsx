"use client";

import type {CSSProperties} from "react";
import {ACCENT_PACKS, type Accent, type AccentPack} from "@/lib/home/palette";
import page from "./RefinedLanding.module.css";
import s from "./Showcase.module.css";

export type Mood = "Automatic" | "Glass" | "Graphite" | "Pearl";
export const MOODS: Mood[] = ["Automatic", "Glass", "Graphite", "Pearl"];

/**
 * `true` for a light Dock, `false` for a dark one, `null` for Automatic. Automatic stays unresolved
 * in markup so the static page is right for both: `page.autoAccent` and `page.autoLight` follow
 * `prefers-color-scheme` in CSS.
 */
export type Light = boolean | null;

/** Sets `--accent` for an element. With Automatic, also add `page.autoAccent` to pick the variant. */
export function accentVars(accent: Accent, light: Light): CSSProperties {
  const vars: Record<string, string> = light === null ? {"--accent-light": accent.light, "--accent-dark": accent.dark} : {"--accent": light ? accent.light : accent.dark};
  return vars;
}

function chroma(hex: string) {
  const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255);
  return Math.max(r, g, b) - Math.min(r, g, b);
}
/** The pack's most colourful accent, which the Dock preview wears while the pack is on screen. */
export function signature(pack: AccentPack): Accent {
  return pack.colors.reduce((best, c) => chroma(c.dark) > chroma(best.dark) ? c : best, pack.colors[0]);
}


export default function AppearanceStudio({mood, onPickMood, packIndex, onPickPack, light}: {
  mood: Mood; onPickMood: (m: Mood) => void; packIndex: number; onPickPack: (index: number) => void; light: Light;
}) {
  const pack = ACCENT_PACKS[packIndex];
  const accent = signature(pack);

  return <div className={s.studio} role="group" aria-label="Preview Dock appearance">
    <p className={s.studioLabel}>Pick a mood</p>
    <div className={s.moods}>
      {MOODS.map(m => <button key={m} type="button" aria-pressed={mood === m} className={mood === m ? s.moodActive : ""} onClick={() => onPickMood(m)}>{m}</button>)}
    </div>
    <label className={s.colorLabel}>Accent collection
      <select value={packIndex} onChange={e => onPickPack(Number(e.target.value))}>
        {ACCENT_PACKS.map((p, i) => <option key={p.name} value={i}>{p.name} · {p.mood}</option>)}
      </select>
    </label>
    <div className={s.packMeta} aria-live="polite">
      <span className={s.swatchRow}>
        {pack.colors.map(c => <i key={c.name} title={c.name} className={`${c.name === accent.name ? s.swatchActive : ""} ${light === null ? page.autoAccent : ""}`} style={{...accentVars(c, light), background: "var(--accent)"}}/>)}
      </span>
      <span className={s.packCount}>{accent.name}</span>
    </div>
    <p className={s.studioNote}>Colors adapt to light and dark appearance.</p>
  </div>;
}
