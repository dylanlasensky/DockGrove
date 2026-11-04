"use client";

import {useState} from "react";
import s from "./RefinedLanding.module.css";

const SAMPLES = [
  {id: "finder", app: "Finder", title: "Current project", minimized: false},
  {id: "notes", app: "Notes", title: "A good idea", minimized: true},
  {id: "safari", app: "Safari", title: "Research", minimized: false},
];

export default function WindowShelfPreview() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [minimizedOnly, setMinimizedOnly] = useState(false);
  const [windows, setWindows] = useState(SAMPLES);
  const [notice, setNotice] = useState("");
  const matches = windows.filter(window => (!minimizedOnly || window.minimized) && `${window.app} ${window.title}`.toLowerCase().includes(query.toLowerCase()));
  return <div className={s.windowControl} onKeyDown={event => { if (event.key === "Escape") setOpen(false); }} onBlur={event => { if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false); }}>
    <button type="button" className={s.cubeButton} title="Open and minimized windows" aria-label="Show open and minimized sample windows" aria-expanded={open} onClick={() => setOpen(!open)}>
      <svg viewBox="0 0 32 32" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" aria-hidden="true"><path d="m16 3 11 6v14l-11 6-11-6V9Z M5 9l11 6 11-6 M16 15v14 M5 23l11-6 11 6 M16 3v14"/></svg>
    </button>
    {open && <div className={s.windowPreview} role="dialog" aria-label="Sample window shelf">
      <header><b>Your windows</b><button type="button" aria-label="Close sample window shelf" onClick={() => setOpen(false)}>×</button></header>
      <input aria-label="Search sample windows" placeholder="Search apps or windows" value={query} onChange={event => setQuery(event.target.value)} autoFocus/>
      <div className={s.windowFilters}><button type="button" aria-pressed={!minimizedOnly} onClick={() => setMinimizedOnly(false)}>All</button><button type="button" aria-pressed={minimizedOnly} onClick={() => setMinimizedOnly(true)}>Minimized</button></div>
      <div className={s.windowRows}>{matches.map(window => <button type="button" key={window.id} onClick={() => { setWindows(previous => previous.map(item => item.id === window.id ? {...item, minimized: false} : item)); setNotice(`${window.app} window restored in this sample.`); }}><span><b>{window.title}</b><small>{window.app}</small></span><em>{window.minimized ? "Minimized" : "Open"}</em></button>)}{!matches.length && <p>No matching windows.</p>}</div>
      <p role="status">{notice || "Sample windows. In the app, click to restore."}</p>
    </div>}
  </div>;
}
