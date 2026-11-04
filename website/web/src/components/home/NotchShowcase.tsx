"use client";

import {useState, type DragEvent} from "react";
import Reveal from "./Reveal";
import s from "./Showcase.module.css";

/** An illustrative preview of the native Home/Files shelf. Files never leave the browser. */
export default function NotchShowcase() {
  const [tab, setTab] = useState<"Home" | "Files">("Home");
  const [widgets, setWidgets] = useState(false);
  const [query, setQuery] = useState("");
  const [tray, setTray] = useState(["Brief.pdf", "Moodboard.png"]);
  const [review, setReview] = useState(false);
  const [selection, setSelection] = useState(["Brief.pdf"]);
  const [notice, setNotice] = useState("");
  const [playing, setPlaying] = useState(false);
  function drop(event: DragEvent, destination: "tray" | "airdrop") {
    event.preventDefault();
    const names = Array.from(event.dataTransfer.files, file => file.name).filter(Boolean);
    if (!names.length) return;
    if (destination === "tray") setTray(previous => [...new Set([...previous, ...names])]);
    else { setSelection(names); setReview(true); }
    setNotice("Only file names are used in this preview. Nothing is uploaded.");
  }
  const cards = ["Calendar", "Codex", "Notes"].filter(name => name.toLowerCase().includes(query.toLowerCase()));
  return <section id="notch" className={s.notchSection}>
    <div className={s.notchInner}>
      <Reveal className={s.notchCopy}>
        <p className={s.eyebrow}>THE NOTCH, PUT TO WORK.</p>
        <h2>A shelf above<br/>the everyday.</h2>
        <p>Music, a focus timer, and useful widgets in Home. A place for files in Files. Open your Mac’s notch to bring the little things closer.</p>
        <ul className={s.points}>
          <li><b>A compact shelf.</b> Switch views without growing over your work.</li>
          <li><b>Keep a file close.</b> Save a shortcut, open it, or reveal it in Finder.</li>
          <li><b>Review before sharing.</b> Choose device opens Apple’s AirDrop chooser. You pick the recipient there.</li>
        </ul>
        <p className={s.compatibility}>Opt-in on compatible Macs with a built-in notch. No camera access required.</p>
      </Reveal>
      <Reveal>
        <div className={s.screen} role="group" aria-label="Notch shelf preview with sample data">
          <div className={`${s.notch} ${s.notchOpen} ${s.nativeShelf}`}>
            <div className={s.nativeHeader}>
              {tab === "Home" ? <input aria-label="Find a widget in the notch preview" placeholder="Find a widget" value={query} onChange={event => { setQuery(event.target.value); setWidgets(true); }}/> : <span>{tray.length} files</span>}
              <span className={s.cameraSpace} aria-hidden="true"/>
              <div aria-label="Notch views">{(["Home", "Files"] as const).map(name => <button key={name} type="button" aria-pressed={tab === name} onClick={() => { setTab(name); setNotice(""); }}>{name}</button>)}</div>
            </div>
            <div className={s.nativeContent}>
              {tab === "Home" ? <>
                {!widgets && !query ? <div className={s.nativeHome}>
                  <div className={s.nativeMusic}><span aria-hidden="true">♫</span><div><b>Quiet hours</b><small>Sample playlist</small></div><button type="button" aria-label={playing ? "Pause notch music sample" : "Play notch music sample"} onClick={() => setPlaying(!playing)}>{playing ? "Ⅱ" : "▶"}</button></div>
                  <div className={s.nativeFocus}><small>Focus</small><b>25:00</b></div>
                </div> : <div className={s.nativeWidgets}>{cards.length ? cards.map(name => <div key={name}><small>{name}</small><b>{name === "Calendar" ? "10:30" : name === "Codex" ? "82% left" : "Ship the idea"}</b><small>{name === "Calendar" ? "Design review" : name === "Codex" ? "Sample usage" : "Quick note"}</small></div>) : <p>No matching widgets.</p>}</div>}
                {!query && <button type="button" className={s.shelfPage} aria-label={widgets ? "Show notch home cards" : "Show more notch widgets"} onClick={() => setWidgets(!widgets)}>{widgets ? "‹ Home cards" : "More widgets ›"}</button>}
              </> : <div className={s.nativeFiles}>
                <div onDragOver={event => event.preventDefault()} onDrop={event => drop(event, "tray")} className={s.trayPreview}><b>File tray</b><small>{tray.slice(0, 2).join(" · ") || "Drop files to keep shortcuts"}</small><button type="button" onClick={() => { setTray([]); setNotice("Tray cleared. Original files are unchanged."); }}>Clear tray</button></div>
                <div onDragOver={event => event.preventDefault()} onDrop={event => drop(event, "airdrop")} className={s.airDropPreview}>
                  {review ? <><small>{selection.length} selected · {selection[0] || "No files"}</small><button type="button" disabled={!selection.length} onClick={() => setNotice("In the Mac app, Choose device opens Apple’s AirDrop chooser. This website does not share files.")}>Choose device</button><button type="button" onClick={() => { setReview(false); setNotice(""); }}>Close review</button></> : <button type="button" onClick={() => { setReview(true); setSelection(["Brief.pdf"]); }}>AirDrop <small>Review a sample file</small></button>}
                </div>
              </div>}
            </div>
          </div>
          <div className={s.desktopHint} aria-hidden="true"><span/><span/><span/></div>
          <p className={s.screenNote}>Interactive illustration · Sample data</p>
        </div>
        <p className={s.previewNotice} role="status">{notice || "Try Home, Files, or search for a widget."}</p>
      </Reveal>
    </div>
  </section>;
}
