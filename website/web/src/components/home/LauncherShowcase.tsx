"use client";

import {useMemo, useState, type CSSProperties} from "react";
import Image from "next/image";
import Reveal from "./Reveal";
import s from "./Showcase.module.scss";

type App = {name: string; icon?: string; glyph?: string; tint?: string};

const APPS: App[] = [
  {name: "Finder", icon: "finder"}, {name: "Safari", icon: "safari"}, {name: "Notes", icon: "notes"}, {name: "Calendar", icon: "calendar"},
  {name: "Mail", glyph: "✉", tint: "#3d8bf7"}, {name: "Music", glyph: "♫", tint: "#f5435d"}, {name: "Photos", glyph: "✿", tint: "#f2a33a"}, {name: "Maps", glyph: "➤", tint: "#38b26a"},
  {name: "Messages", glyph: "❝", tint: "#34c759"}, {name: "Terminal", glyph: "›_", tint: "#2b2f36"}, {name: "Preview", glyph: "◩", tint: "#5a8de0"}, {name: "Xcode", glyph: "⚒", tint: "#1f6fe0"},
];
const PINNED = ["Finder", "Safari", "Notes", "Calendar"];

type Mode = "launch" | "add" | "replace";
const NOTES: Record<Mode, string> = {launch: "Every app, floating over your work.", add: "The + button opens the same view. Apps in the Dock have a check.", replace: "Replace app… swaps one for another."};
const TITLES: Record<Mode, string> = {launch: "Applications", add: "Add an app to the Dock", replace: "Replace Safari"};

const MENUS = [
  {anchor: "safari", items: ["✓Start Page", "DockGrove — Release notes", "-", ">Options", "Show All Windows", "Hide", "Quit", "-", "Replace app…", "Remove from Dock"], hover: "Options", sub: ["✓Keep in Dock", "Show in Finder"], caption: "Right-click an app: windows, Options, Hide and Quit."},
  {anchor: "safari", items: ["✓Start Page", "DockGrove — Release notes", "-", ">Options", "Show All Windows", "Hide", "Force Quit", "-", "Replace app…", "Remove from Dock"], hover: "Force Quit", sub: [], caption: "Hold Option and Quit becomes Force Quit."},
  {anchor: "", items: ["Turn Hiding On", ">Position on Screen", "-", "Restore Apple Dock…", "Dock Settings…"], hover: "Position on Screen", sub: ["✓Bottom", "Top", "Floating"], caption: "Right-click the Dock: hiding, position, Apple’s Dock and settings."},
];

export default function LauncherShowcase() {
  const [mode, setMode] = useState<Mode>("launch");
  const [menuIndex, setMenuIndex] = useState(0);
  const [query, setQuery] = useState("");
  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? APPS.filter(a => a.name.toLowerCase().includes(q)) : APPS;
  }, [query]);
  const menu = MENUS[menuIndex];

  return <section id="launcher" className={s.launcherSection}>
    <Reveal className={s.sectionHeading}>
      <p className={s.eyebrow}>ONE PLACE FOR EVERY APP.</p>
      <h2>Search, add, or swap.<br/>Right where you left off.</h2>
      <p>A floating glass chooser, just like Apps on your Mac. It opens over your work and never takes over the screen.</p>
    </Reveal>

    <div className={s.launcherGrid}>
      <Reveal>
        <div className={s.launcher} role="group" aria-label="App launcher preview with sample apps">
          <div className={s.launcherTop}>
            <p key={mode} className={`${s.launcherTitle} ${s.titleSwap}`}>{TITLES[mode]}</p>
            <div className={s.segmented} role="group" aria-label="Launcher modes">
              {(["launch", "add", "replace"] as Mode[]).map(m => <button key={m} type="button" aria-current={mode === m} className={mode === m ? s.segActive : ""} onClick={() => { setQuery(""); setMode(m); }}>{m === "launch" ? "Open" : m === "add" ? "+ Add" : "Replace"}</button>)}
            </div>
          </div>
          <form className={s.search} role="search" onSubmit={e => e.preventDefault()}>
            <span aria-hidden="true">⌕</span>
            <input type="search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Search" aria-label="Search applications"/>
            <span className={s.searchMore} aria-hidden="true">•••</span>
          </form>
          <div className={s.appsPanel}>
          <ul className={s.appGrid}>
            {results.map((app, i) => {
              const inDock = mode === "add" && PINNED.includes(app.name);
              const replacing = mode === "replace" && app.name === "Safari";
              return <li key={app.name} style={{"--i": i} as CSSProperties} className={inDock || replacing ? s.inDock : ""}>
                <span className={s.appIcon}>
                  {app.icon ? <Image src={`/assets/apps/${app.icon}.png`} alt="" width={56} height={56} unoptimized/> : <span className={s.glyph} style={{background: app.tint}} aria-hidden="true">{app.glyph}</span>}
                  {inDock && <span className={s.check} aria-hidden="true">✓</span>}
                </span>
                <span className={s.appName}>{app.name}</span>
              </li>;
            })}
            {results.length === 0 && <li className={s.noResults}>No applications match “{query}”.</li>}
          </ul>
          </div>
          <p key={mode} className={`${s.launcherStatus} ${s.titleSwap}`}>{NOTES[mode]}</p>
        </div>
      </Reveal>

      <Reveal className={s.menuDemo} step={1}>
        <div className={s.menuStage} role="group" aria-label={`Menu preview: ${menu.caption}`} tabIndex={0}>
          <div key={menuIndex} className={`${s.menu} ${menu.anchor ? "" : s.barMenu}`} aria-hidden="true">
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
          <div className={s.menuChoices} role="group" aria-label="Menu examples">{MENUS.map((_, i) => <button key={i} type="button" aria-pressed={i === menuIndex} onClick={() => setMenuIndex(i)}>{["App", "Option key", "Dock"][i]}</button>)}</div>
        </div>
        <h3>Menus that feel like a Mac.</h3>
        <p key={menuIndex} className={s.titleSwap}>{menu.caption}</p>
      </Reveal>
    </div>
  </section>;
}
