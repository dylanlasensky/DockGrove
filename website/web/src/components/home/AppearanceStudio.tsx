"use client";

import type {RefObject} from "react";
import {ACCENT_PACKS, type Accent, type AccentPack} from "@/lib/home/palette";
import type {AutoCycle} from "@/hooks/useAutoCycle";
import s from "./Showcase.module.css";

export type Mood = "Automatic" | "Glass" | "Graphite" | "Pearl";
export const MOODS: Mood[] = ["Automatic", "Glass", "Graphite", "Pearl"];
/** Packs shown per mood before the slideshow moves to the next mood. */
export const PACKS_PER_MOOD = 4;

/** The swatch value a mood shows: Pearl uses an accent's light variant, the others its dark one. */
export function accentHex(accent: Accent, light: boolean): string {
  return light ? accent.light : accent.dark;
}

function chroma(hex: string) {
  const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255);
  return Math.max(r, g, b) - Math.min(r, g, b);
}
/** The pack's most colourful accent, which the Dock preview wears while the pack is on screen. */
export function signature(pack: AccentPack): Accent {
  return pack.colors.reduce((best, c) => chroma(c.dark) > chroma(best.dark) ? c : best, pack.colors[0]);
}


export default function AppearanceStudio({mood, onPickMood, show, showRef, light}: {
  mood: Mood; onPickMood: (m: Mood) => void; show: AutoCycle; showRef: RefObject<HTMLDivElement | null>; light: boolean;
}) {
  const pack = ACCENT_PACKS[show.index];
  const accent = signature(pack);

  return <div ref={showRef} className={s.studio} role="group" aria-label="Preview Dock appearance">
    <p className={s.studioLabel}>Pick a mood</p>
    <div className={s.moods}>
      {MOODS.map(m => <button key={m} type="button" aria-pressed={mood === m} className={mood === m ? s.moodActive : ""} onClick={() => onPickMood(m)}>{m}</button>)}
    </div>
    <label className={s.colorLabel}>Accent collection
      <select value={show.index} onChange={e => show.setIndex(Number(e.target.value))}>
        {ACCENT_PACKS.map((p, i) => <option key={p.name} value={i}>{p.name} · {p.mood}</option>)}
      </select>
    </label>
    <div className={s.packMeta} aria-live="polite">
      <span className={s.swatchRow}>
        {pack.colors.map(c => <i key={c.name} title={c.name} className={c.name === accent.name ? s.swatchActive : ""} style={{background: accentHex(c, light)}}/>)}
      </span>
      <span className={s.packCount}>{accent.name}</span>
    </div>
    <p className={s.studioNote}>Colors adapt to light and dark appearance.</p>
  </div>;
}
