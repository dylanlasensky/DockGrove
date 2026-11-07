"use client";

import {useEffect, useRef, useState} from "react";
import Image from "next/image";
import Reveal from "./Reveal";
import h from "./NotchHardware.module.scss";

type Preview = "Home" | "Files" | "Closed";

/** One uniformly scaled 1440 × 900 desktop. Native defaults: 760 × 144 shelf, 185 × 32 housing.
 * Controls outside the miniature keep the preview usable on phones without enlarging the shelf.
 * The bottom bar is a capture of the actual app, not a substitute macOS Dock. */
export default function NotchShowcase() {
  const [view, setView] = useState<Preview>("Home");
  const display = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const element = display.current;
    if (!element) return;
    const resize = () => element.style.setProperty("--screen-scale", String(element.getBoundingClientRect().width / 1440));
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  return <section id="notch" className={h.section}>
    <div className={h.inner}>
      <Reveal className={h.copy}>
        <p className={h.eyebrow}>THE NOTCH SHELF</p>
        <h2>Keep it close.</h2>
        <p className={h.description}>Music, focus, and files.<br/>Just a click away.</p>
        <div className={h.controls} role="group" aria-label="Preview notch view">
          {(["Home", "Files", "Closed"] as const).map(name => <button key={name} type="button" aria-pressed={view === name} aria-controls="notch-desktop-preview" onClick={() => setView(name)}>{name}</button>)}
        </div>
        <p className={h.compatibility}>For Macs with a built-in notch.</p>
      </Reveal>
      <Reveal className={h.visual}>
        <div id="notch-desktop-preview" className={h.laptop} role="img" aria-label={`Notch shelf preview: ${view.toLowerCase()}. A compact shelf above the desktop, with the real DockGrove app bar, usage widget, dragon companion and window cube below. Sample data.`}>
          <div className={h.lid}>
            <div className={h.display} ref={display}>
              <div className={h.surface} aria-hidden="true">
                <div className={h.menuBar}><span><b>Finder</b> File <i>Edit</i><i>View</i></span><span>Wi-Fi <em/> Tue 9:41</span></div>
                <div className={h.desktopWindow}>
                  <div className={h.windowHeader}><span><i/><i/><i/></span><b>Ideas for the week</b></div>
                  <div className={h.windowBody}><aside><b>Favorites</b><span>Recents</span><span>Projects</span><span>Downloads</span></aside><div><small>ROOM FOR YOUR NEXT IDEA</small><h3>Make something<br/>you love.</h3><div className={h.swatches}><i/><i/><i/></div></div></div>
                </div>
                <div className={h.realDock}><Image src="/assets/dockgrove-native-bar.png" alt="" width={2312} height={216} sizes="80vw"/></div>
                {view !== "Closed" && <div className={h.shelf} key={view}>
                  <div className={h.shelfHeader}><span>{view === "Home" ? "⌕  Find a widget" : "File tray · 2 files"}</span><span/><div><b data-active={view === "Home"}>Home</b><b data-active={view === "Files"}>Files</b><i>⌃</i></div></div>
                  <div className={h.cards}>
                    {view === "Home" ? <><div className={h.music}><span>♫</span><div><b>Your music</b><small>Sample playlist</small></div><i>▶</i></div><div className={h.focus}><small>◷ &nbsp; Focus</small><b>25:00 <i>▶</i></b></div></> : <><div className={h.files}><b>File tray</b><small>Brief.pdf · Moodboard.png</small></div><div className={h.files}><b>AirDrop</b><small>Drop files to review</small></div></>}
                  </div>
                  <div className={h.pages}><b/><i/><i/><i/><i/></div>
                </div>}
                <div className={h.cameraHousing}><span/></div>
              </div>
            </div>
            <div className={h.chin}/>
          </div>
          <div className={h.base}><span/></div>
        </div>
        <p className={h.caption}>DockGrove in context · Sample preview</p>
      </Reveal>
    </div>
  </section>;
}
