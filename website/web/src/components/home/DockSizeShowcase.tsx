"use client";

import {useState} from "react";
import Reveal from "./Reveal";
import s from "./Showcase.module.scss";

/** The Size presets from Studio, with the same lengths and heights. */
const PRESETS = [{name: "Compact", length: 65, height: 88}, {name: "Balanced", length: 85, height: 104}, {name: "Spacious", length: 100, height: 140}];
const ITEMS = 10;
const ITEM_SHARE = 8.5; // percent of the display one tile needs in this miniature

/** Moving the slider or picking a preset sets an explicit length and turns Fit off, as in the app. */
export default function DockSizeShowcase() {
  const [length, setLength] = useState(85);
  const [height, setHeight] = useState(104);
  const [fit, setFit] = useState(false);
  const [hidden, setHidden] = useState(false);
  const fitted = ITEMS * ITEM_SHARE;
  const shown = fit ? Math.min(length, fitted) : length;
  const visible = Math.min(ITEMS, Math.floor(shown / ITEM_SHARE));
  const paged = visible < ITEMS;

  return <section id="dock-size" className={s.sizeSection}>
    <Reveal className={s.sectionHeading}>
      <p className={s.eyebrow}>SIZE IT TO FIT.</p>
      <h2>As long as you like.<br/>Out of sight when you want.</h2>
      <p>Set your Dock from 35 to 100% of your display. Widgets stay whole, and pages hold whatever doesn’t fit.</p>
    </Reveal>
    <Reveal className={s.sizeGrid}>
      <div className={s.sizeStage} role="img" aria-label={`Dock preview at ${Math.round(shown)}% of the display${hidden ? ", hidden" : ""}.${paged ? " Extra items move to another page." : ""}`}>
        <p className={s.sizeHint}>{hidden ? "Move to the screen edge to show it." : "Preview"}</p>
        <div className={s.sizeDock} data-hidden={hidden} style={{width: `${shown}%`, height: height * 0.62}}>
          {Array.from({length: visible}, (_, i) => <i key={i}/>)}
          {paged && <span className={s.sizePages}><b/><b/></span>}
        </div>
      </div>
      <div className={s.sizePanel}>
        <div className={s.sizePresets} role="group" aria-label="Size presets">
          {PRESETS.map(p => <button key={p.name} type="button" aria-pressed={!fit && length === p.length && height === p.height} onClick={() => { setFit(false); setLength(p.length); setHeight(p.height); }}>{p.name}</button>)}
        </div>
        <div>
          <div className={s.sizeRow}><label htmlFor="dock-length">Dock length</label><output htmlFor="dock-length">{length}%</output></div>
          <input id="dock-length" className={s.sizeSlider} type="range" min={35} max={100} value={length} onChange={e => { setFit(false); setLength(Number(e.target.value)); }}/>
        </div>
        <div className={s.sizeRow}>
          <span id="dock-fit">Fit length to content</span>
          <button type="button" role="switch" aria-checked={fit} aria-labelledby="dock-fit" className={s.sizeSwitch} onClick={() => setFit(!fit)}/>
        </div>
        <button type="button" className={s.hideButton} aria-pressed={hidden} onClick={() => setHidden(!hidden)}>{hidden ? "Turn Hiding Off" : "Turn Hiding On"}<kbd>⌥⌘D</kbd></button>
        <p className={s.sizeNote}>Want Apple’s Dock back? Restore Apple Dock is always one click away.</p>
      </div>
    </Reveal>
  </section>;
}
