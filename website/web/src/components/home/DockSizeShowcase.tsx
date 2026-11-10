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
  /** The slider speaks its own value, so this carries only what changes around it. */
  const [status, setStatus] = useState("");
  const moveLength = (next: number) => {
    const nextPaged = Math.floor(next / ITEM_SHARE) < ITEMS;
    if (fit) setStatus("Fit length to content is off.");
    else if (nextPaged !== (Math.floor(length / ITEM_SHARE) < ITEMS)) setStatus(nextPaged ? "Extra items move to another page." : "All items fit on one page.");
    setFit(false);
    setLength(next);
  };

  return <section id="dock-size" className={s.sizeSection}>
    <Reveal className={s.sectionHeading}>
      <p className={s.eyebrow}>SIZE IT TO FIT.</p>
      <h2>As long as you like.<br/>Out of sight when you want.</h2>
      <p>Set your Dock from 35 to 100% of your display. Widgets stay whole, and pages hold whatever doesn’t fit.</p>
    </Reveal>
    <Reveal className={s.sizeGrid}>
      <div className={s.sizeStage} role="img" aria-label={`Dock preview at ${Math.round(shown)}% of the display${hidden ? ", hidden" : ""}.${paged ? " Extra items move to another page." : ""}`}>
        <p className={s.sizeHint}>{hidden ? "Move the pointer to the screen edge to show the Dock." : "Preview"}</p>
        <div className={s.sizeDock} data-hidden={hidden} style={{width: `${shown}%`, height: height * 0.62}}>
          {Array.from({length: visible}, (_, i) => <i key={i}/>)}
          {paged && <span className={s.sizePages}><b/><b/></span>}
        </div>
      </div>
      <div className={s.sizePanel}>
        <div className={s.sizePresets} role="group" aria-label="Size presets">
          {PRESETS.map(p => <button key={p.name} type="button" aria-pressed={!fit && length === p.length && height === p.height} onClick={() => { setFit(false); setLength(p.length); setHeight(p.height); setStatus(`${p.name} size: Dock length ${p.length}%.`); }}>{p.name}</button>)}
        </div>
        <div>
          <div className={s.sizeRow}><label htmlFor="dock-length">Dock length</label><span>{length}%</span></div>
          <input id="dock-length" className={s.sizeSlider} type="range" min={35} max={100} value={length} aria-valuetext={`${length}% of the display`} onChange={e => moveLength(Number(e.target.value))}/>
        </div>
        <button type="button" role="switch" aria-checked={fit} className={s.sizeToggle} onClick={() => { setStatus(`Fit length to content is ${fit ? "off" : "on"}.`); setFit(!fit); }}>
          Fit length to content
          <span className={s.sizeSwitch} aria-hidden="true"/>
        </button>
        {fit && <p className={s.sizeNote}>The Dock is only as long as its items need, up to the Dock length. Moving the Dock length slider turns this off.</p>}
        <button type="button" className={s.hideButton} onClick={() => { setStatus(hidden ? "Hiding is off. The Dock is showing." : "Hiding is on. The Dock is out of sight."); setHidden(!hidden); }}>{hidden ? "Turn Hiding Off" : "Turn Hiding On"}<kbd>⌥⌘D</kbd></button>
        <p className={s.sizeStatus} role="status">{status}</p>
        <p className={s.sizeNote}>Want Apple’s Dock back? Restore Apple Dock is always one click away.</p>
      </div>
    </Reveal>
  </section>;
}
