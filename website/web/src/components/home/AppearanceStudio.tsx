"use client";

import type {CSSProperties, RefObject} from "react";
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

const MOOD_PREVIEW: Record<Mood, string> = {Automatic: s.moodAuto, Glass: s.moodGlass, Graphite: s.moodGraphite, Pearl: s.moodPearl};

export default function AppearanceStudio({mood, onPickMood, show, showRef, light}: {
  mood: Mood; onPickMood: (m: Mood) => void; show: AutoCycle; showRef: RefObject<HTMLDivElement | null>; light: boolean;
}) {
  const pack = ACCENT_PACKS[show.index];
  const accent = signature(pack);

  return <div ref={showRef} {...show.bind} className={s.studio} role="group" aria-roledescription="slideshow" aria-label="Preview Dock appearance">
    <p className={s.studioLabel}>Pick a mood</p>
    <div className={s.moods}>
      {MOODS.map(m => <button key={m} type="button" aria-pressed={mood === m} className={mood === m ? s.moodActive : ""} onClick={() => onPickMood(m)}>
        <span className={`${s.moodChip} ${MOOD_PREVIEW[m]}`} aria-hidden="true">{["#3b82f6", "#a855f7", "#f97316", "#22c55e"].map(c => <i key={c} style={{background: `linear-gradient(${c}, ${c}cc)`}}/>)}</span>
        {m}
      </button>)}
    </div>

    <p className={s.studioLabel}>Color</p>
    <div className={s.packStage}>
      <div className={s.packTrack} style={{"--at": show.index} as CSSProperties}>
        {ACCENT_PACKS.map((p, i) => <button key={p.name} type="button" tabIndex={i === show.index ? 0 : -1} aria-label={`${p.name} accents: ${p.mood}`} aria-current={i === show.index} className={`${s.packCard} ${i === show.index ? s.packCardActive : ""}`} onClick={() => show.setIndex(i)}>
          <span className={s.packDots} aria-hidden="true">{p.colors.map(c => <i key={c.name} style={{background: accentHex(c, light)}}/>)}</span>
          <b>{p.name}</b>
          <small>{p.group} · {p.mood}</small>
        </button>)}
      </div>
    </div>
    <div className={s.packMeta} aria-live={show.running ? "off" : "polite"}>
      <span key={pack.name} className={s.swatchRow}>
        {pack.colors.map((c, i) => <i key={c.name} title={c.name} className={c.name === accent.name ? s.swatchActive : ""} style={{background: accentHex(c, light), "--step": i} as CSSProperties}/>)}
      </span>
      <span className={s.packCount}>{accent.name} · {show.index + 1} of {ACCENT_PACKS.length}</span>
    </div>
    <div className={s.progress} aria-hidden="true"><em key={show.index} className={s.progressRun} style={{animationDuration: `${show.duration}ms`, animationPlayState: show.running ? "running" : "paused"}}/></div>
    <p className={s.studioNote}>Color packs adapt to light and dark appearance. Hover to pause.</p>
  </div>;
}
