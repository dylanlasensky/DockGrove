"use client";

import {useMemo, useState, type CSSProperties} from "react";
import Image from "next/image";
import Reveal from "./Reveal";
import {useAutoCycle} from "@/hooks/useAutoCycle";
import s from "./Showcase.module.css";

type App = {name: string; icon?: string; glyph?: string; tint?: string};

const APPS: App[] = [
  {name: "Finder", icon: "finder"}, {name: "Safari", icon: "safari"}, {name: "Notes", icon: "notes"}, {name: "Calendar", icon: "calendar"},
  {name: "Mail", glyph: "✉", tint: "#3d8bf7"}, {name: "Music", glyph: "♫", tint: "#f5435d"}, {name: "Photos", glyph: "✿", tint: "#f2a33a"}, {name: "Maps", glyph: "➤", tint: "#38b26a"},
  {name: "Messages", glyph: "❝", tint: "#34c759"}, {name: "Terminal", glyph: "›_", tint: "#2b2f36"}, {name: "Preview", glyph: "◩", tint: "#5a8de0"}, {name: "Xcode", glyph: "⚒", tint: "#1f6fe0"},
];
const PINNED = ["Finder", "Safari", "Notes", "Calendar"];

type Mode = "launch" | "add" | "replace";
type Step = {mode: Mode; query: string; press?: string; added?: string; note: string; ms?: number};

/** The launcher demo plays like a screen recording: typing, picking, adding and swapping on its own. */
const SCRIPT: Step[] = [
  {mode: "launch", query: "", note: "Every app in one view.", ms: 2200},
  {mode: "launch", query: "m", note: "Start typing to filter.", ms: 500},
  {mode: "launch", query: "ma", note: "Start typing to filter.", ms: 500},
  {mode: "launch", query: "map", note: "Start typing to filter.", ms: 900},
  {mode: "launch", query: "map", press: "Maps", note: "Return opens the top result.", ms: 1500},
  {mode: "add", query: "", note: "The + button opens the same view. Apps in the Dock have a check.", ms: 2600},
  {mode: "add", query: "mu", note: "The + button opens the same view. Apps in the Dock have a check.", ms: 700},
  {mode: "add", query: "mu", press: "Music", note: "Click to add.", ms: 1100},
  {mode: "add", query: "", added: "Music", note: "Music is in the Dock.", ms: 2200},
  {mode: "replace", query: "", note: "Replace app… swaps one for another.", ms: 2200},
  {mode: "replace", query: "xc", note: "Replace app… swaps one for another.", ms: 700},
  {mode: "replace", query: "xc", press: "Xcode", note: "Safari becomes Xcode.", ms: 1800},
];
const TITLES: Record<Mode, string> = {launch: "Applications", add: "Add an app to the Dock", replace: "Replace Safari"};
const MODE_START: Record<Mode, number> = {launch: 0, add: 5, replace: 9};

const MENUS = [
  {anchor: "safari", items: ["✓Start Page", "DockGrove — Release notes", "-", ">Options", "Show All Windows", "Hide", "Quit", "-", "Replace app…", "Remove from Dock"], hover: "Options", sub: ["✓Keep in Dock", "Show in Finder"], caption: "Right-click an app: windows, Options, Hide and Quit."},
  {anchor: "safari", items: ["✓Start Page", "DockGrove — Release notes", "-", ">Options", "Show All Windows", "Hide", "Force Quit", "-", "Replace app…", "Remove from Dock"], hover: "Force Quit", sub: [], caption: "Hold Option and Quit becomes Force Quit."},
  {anchor: "", items: ["Turn Hiding On", ">Position on Screen", "-", "Dock Settings…"], hover: "Position on Screen", sub: ["✓Bottom", "Top", "Floating"], caption: "Right-click the Dock: hiding, position and settings."},
];

export default function LauncherShowcase({playing}: {playing: boolean}) {
  const [demoRef, demo] = useAutoCycle<HTMLDivElement>(SCRIPT.length, i => SCRIPT[i].ms ?? 1500, playing);
  const [menusRef, menus] = useAutoCycle<HTMLDivElement>(MENUS.length, 3200, playing);
  const [typed, setTyped] = useState<string | null>(null);
  const step = SCRIPT[demo.index];
  const query = typed ?? step.query;
  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? APPS.filter(a => a.name.toLowerCase().includes(q)) : APPS;
  }, [query]);
  const pinned = step.added ? [...PINNED, step.added] : PINNED;
  const menu = MENUS[menus.index];

  return <section id="launcher" className={s.launcherSection}>
    <Reveal className={s.sectionHeading}>
      <p className={s.eyebrow}>ONE PLACE FOR EVERY APP.</p>
      <h2>Search, add, or swap.<br/>Same view every time.</h2>
      <p>The Applications folder, the + button, Replace app… and the App search widget all open one full-screen launcher. Start typing to filter, press Return for the top result.</p>
    </Reveal>

    <div className={s.launcherGrid}>
      <Reveal>
        <div ref={demoRef} {...demo.bind} className={s.launcher} role="group" aria-roledescription="slideshow" aria-label="App launcher preview with sample apps">
          <div className={s.launcherTop}>
            <p key={step.mode} className={`${s.launcherTitle} ${s.titleSwap}`}>{TITLES[step.mode]}</p>
            <div className={s.segmented} aria-label="Launcher modes">
              {(["launch", "add", "replace"] as Mode[]).map(m => <button key={m} type="button" aria-current={step.mode === m} className={step.mode === m ? s.segActive : ""} onClick={() => { setTyped(null); demo.setIndex(MODE_START[m]); }}>{m === "launch" ? "Open" : m === "add" ? "+ Add" : "Replace"}</button>)}
            </div>
          </div>
          <form className={s.search} role="search" onSubmit={e => e.preventDefault()}>
            <span aria-hidden="true">⌕</span>
            <input type="search" value={query} onChange={e => setTyped(e.target.value)} onBlur={() => setTyped(null)} placeholder="Search applications" aria-label="Search applications"/>
            {typed === null && step.query && <span className={s.caret} aria-hidden="true"/>}
          </form>
          <ul className={s.appGrid}>
            {results.map((app, i) => {
              const inDock = step.mode === "add" && pinned.includes(app.name);
              const replacing = step.mode === "replace" && app.name === "Safari";
              const pressed = step.press === app.name;
              return <li key={app.name} style={{"--i": i} as CSSProperties} className={`${inDock || replacing ? s.inDock : ""} ${pressed ? s.pressed : ""} ${step.added === app.name ? s.justAdded : ""}`}>
                <span className={s.appIcon}>
                  {app.icon ? <Image src={`/assets/apps/${app.icon}.png`} alt="" width={56} height={56} unoptimized/> : <span className={s.glyph} style={{background: app.tint}} aria-hidden="true">{app.glyph}</span>}
                  {inDock && <span className={s.check} aria-hidden="true">✓</span>}
                </span>
                <span className={s.appName}>{app.name}</span>
              </li>;
            })}
            {results.length === 0 && <li className={s.noResults}>No applications match “{query}”.</li>}
          </ul>
          <p key={step.note} className={`${s.launcherStatus} ${s.titleSwap}`}>{step.note}</p>
          <div className={s.progress} aria-hidden="true"><em style={{width: `${(demo.index + 1) / SCRIPT.length * 100}%`}}/></div>
        </div>
      </Reveal>

      <Reveal className={s.menuDemo} step={1}>
        <div ref={menusRef} {...menus.bind} className={s.menuStage} role="group" aria-roledescription="slideshow" aria-label={`Menu preview: ${menu.caption}`} tabIndex={0}>
          <div key={menus.index} className={`${s.menu} ${menu.anchor ? "" : s.barMenu}`} aria-hidden="true">
            {menu.items.map((item, i) => item === "-" ? <hr key={i}/> : (() => {
              const label = item.replace(/^[✓>]/, "");
              const hot = label === menu.hover;
              return <span key={i} className={`${s.menuItem} ${hot ? s.menuHover : ""}`}>
                {item.startsWith("✓") && <span className={s.tick}>✓</span>}{label}{label === "Force Quit" && <kbd className={s.optionKey}>⌥</kbd>}
                {item.startsWith(">") && <span className={s.chevron}>›</span>}
                {hot && menu.sub.length > 0 && <span className={`${s.menu} ${s.submenu}`}>{menu.sub.map(subItem => <span key={subItem} className={s.menuItem}>{subItem.startsWith("✓") && <span className={s.tick}>✓</span>}{subItem.replace("✓", "")}</span>)}</span>}
              </span>;
            })())}
          </div>
          {menu.anchor ? <Image className={s.menuAnchor} src={`/assets/apps/${menu.anchor}.png`} alt="" width={56} height={56} unoptimized/> : <span className={s.miniDock} aria-hidden="true"/>}
          <div className={s.dots} aria-hidden="true">{MENUS.map((_, i) => <i key={i} className={i === menus.index ? s.dotActive : ""}/>)}</div>
        </div>
        <h3>Menus that feel like a Mac.</h3>
        <p key={menus.index} className={s.titleSwap}>{menu.caption}</p>
      </Reveal>
    </div>
  </section>;
}
