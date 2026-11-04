"use client";

import {useEffect, useId, useRef, useState} from "react";
import s from "./RefinedLanding.module.css";

const SAMPLES = [
  {id: "finder", app: "Finder", title: "Current project", minimized: false},
  {id: "notes", app: "Notes", title: "A good idea", minimized: true},
  {id: "safari", app: "Safari", title: "Research", minimized: false},
];

export default function WindowShelfPreview() {
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const searchField = useRef<HTMLInputElement>(null);
  const dialogID = useId();
  const restoreFocus = useRef(false);
  const close = () => { restoreFocus.current = true; setOpen(false); };
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (!open && restoreFocus.current) { restoreFocus.current = false; trigger.current?.focus(); }
  }, [open]);
  useEffect(() => {
    if (!open) return;
    const outside = (event: PointerEvent) => { if (!root.current?.contains(event.target as Node)) setOpen(false); };
    const blur = () => setOpen(false);
    document.addEventListener("pointerdown", outside);
    window.addEventListener("blur", blur);
    return () => { document.removeEventListener("pointerdown", outside); window.removeEventListener("blur", blur); };
  }, [open]);
  const [query, setQuery] = useState("");
  const [minimizedOnly, setMinimizedOnly] = useState(false);
  const [windows, setWindows] = useState(SAMPLES);
  const [notice, setNotice] = useState("");
  const matches = windows.filter(window => (!minimizedOnly || window.minimized) && `${window.app} ${window.title}`.toLowerCase().includes(query.trim().toLowerCase()));
  return <div ref={root} className={s.windowControl} onKeyDown={event => {
    if (open && event.key === "Escape") { event.preventDefault(); close(); }
    // Pointer dismissal is handled separately: macOS may blur an input before
    // firing a button click, so closing on blur would swallow that click.
    if (open && event.key === "Tab") requestAnimationFrame(() => { if (!root.current?.contains(document.activeElement)) setOpen(false); });
  }}>
    <button ref={trigger} type="button" aria-haspopup="dialog" aria-controls={open ? dialogID : undefined} className={s.cubeButton} title="Open and minimized windows" aria-label="Show open and minimized sample windows" aria-expanded={open} onClick={() => setOpen(!open)}>
      <svg viewBox="0 0 32 32" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" aria-hidden="true"><path d="m16 3 11 6v14l-11 6-11-6V9Z M5 9l11 6 11-6 M16 15v14 M5 23l11-6 11 6 M16 3v14"/></svg>
    </button>
    {open && <div id={dialogID} className={s.windowPreview} role="dialog" aria-label="Sample window shelf">
      <header><b>Your windows</b><button type="button" aria-label="Close sample window shelf" onClick={close}>×</button></header>
      <input ref={searchField} aria-label="Search sample windows" placeholder="Search apps or windows" value={query} onChange={event => setQuery(event.target.value)} autoFocus/>
      <div className={s.windowFilters}><button type="button" aria-pressed={!minimizedOnly} onClick={() => setMinimizedOnly(false)}>All</button><button type="button" aria-pressed={minimizedOnly} onClick={() => setMinimizedOnly(true)}>Minimized</button></div>
      <div className={s.windowRows}>{matches.map(window => <button type="button" key={window.id} onClick={() => { setWindows(previous => previous.map(item => item.id === window.id ? {...item, minimized: false} : item)); setNotice(`${window.app} window ${window.minimized ? "restored" : "brought forward"} in this sample.`); searchField.current?.focus(); }}><span><b>{window.title}</b><small>{window.app}</small></span><em>{window.minimized ? "Minimized" : "Open"}</em></button>)}{!matches.length && <p>No matching windows.</p>}</div>
      <p role="status">{notice || "Sample windows. In the app, click to restore."}</p>
    </div>}
  </div>;
}
