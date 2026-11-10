"use client";

import {useCallback, useEffect, useRef, useState} from "react";
import type {PointerEvent, ReactNode} from "react";
import Image from "next/image";
import Reveal from "./Reveal";
import h from "./NotchHardware.module.scss";

type Tab = "Home" | "Files";

/** NotchHoverState's timings: the pause before hover opens, and the grace period after leaving. */
const HOVER_OPEN_MS = 180;
const HOVER_CLOSE_MS = 700;

/** NotchDropZone's resting copy. The miniature takes no files, so hovering changes only the styling;
 * the app's "Release to…" lines belong to a real drag. */
const dropZones: {title: string; prompt: string; action: string; icon: ReactNode}[] = [
  {title: "File tray", prompt: "Drop files to keep them here", action: "or click to choose files", icon: <path d="M3 17h7l2 3h4l2-3h7v7H3zM14 3v11m-4.5-4.5L14 14l4.5-4.5"/>},
  {title: "AirDrop", prompt: "Drop files to share nearby", action: "or click to open AirDrop", icon: <path d="M7 20a10 10 0 1 1 14 0m-3.5-3.5a5 5 0 1 0-7 0M14 18l5 7H9z"/>},
];

const previewNames = {
  Home: "open on Home, with music and focus cards",
  Files: "open on Files, with File tray and AirDrop drop zones",
  Closed: "closed, leaving only the camera housing",
};

/** One uniformly scaled 1440 × 900 desktop. Native defaults: 760 × 144 shelf, 185 × 32 housing.
 * Controls outside the miniature keep the preview usable on phones without enlarging the shelf.
 * The bottom bar is a capture of the actual app, not a substitute macOS Dock.
 *
 * Pointer behaviour follows NotchHoverState and NotchController. Only a shelf the pointer opened
 * closes when it leaves; a click, Esc or a Home/Files/Closed button takes ownership from the pointer.
 * The Home/Files/Closed buttons are the keyboard and touch path, so the miniature itself stays hidden
 * from assistive technology and out of the tab order. */
export default function NotchShowcase() {
  const [tab, setTab] = useState<Tab>("Home");
  const [open, setOpen] = useState(true);
  const view = open ? tab : "Closed";
  const section = useRef<HTMLElement>(null);
  const display = useRef<HTMLDivElement>(null);
  const controls = useRef<HTMLDivElement>(null);
  const shelf = useRef<HTMLDivElement>(null);
  const housing = useRef<HTMLDivElement>(null);
  const hoverOwned = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  /** A click, Esc or button changed the shelf: the pointer no longer owns it. */
  const setManually = useCallback((value: boolean) => {
    clearTimeout(timer.current);
    hoverOwned.current = false;
    setOpen(value);
  }, []);

  const hover = (value: boolean, delay: number) => {
    timer.current = setTimeout(() => {
      hoverOwned.current = value;
      setOpen(value);
    }, delay);
  };
  // Touch has no hover: a tap reports enter and leave around its click, and only the click counts.
  const pointerEnteredHousing = (event: PointerEvent) => {
    if (event.pointerType === "touch") return;
    clearTimeout(timer.current);
    if (!open) hover(true, HOVER_OPEN_MS);
  };
  const pointerEnteredShelf = (event: PointerEvent) => {
    if (event.pointerType !== "touch") clearTimeout(timer.current);
  };
  const pointerLeft = (event: PointerEvent) => {
    if (event.pointerType === "touch") return;
    clearTimeout(timer.current);
    if (hoverOwned.current) hover(false, HOVER_CLOSE_MS);
  };

  useEffect(() => {
    const element = display.current;
    if (!element) return;
    const resize = () => element.style.setProperty("--screen-scale", String(element.getBoundingClientRect().width / 1440));
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  useEffect(() => () => clearTimeout(timer.current), []);

  // "Outside" stops at this section: the shelf starts open, and a click elsewhere on the page says
  // nothing about the preview. Click rather than pointerdown, because a swipe to scroll starts with one.
  useEffect(() => {
    const element = section.current;
    if (!open || !element) return;
    const onClick = (event: MouseEvent) => {
      const target = event.target as Node;
      if (![shelf, housing, controls].some(inside => inside.current?.contains(target))) setManually(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setManually(false);
    };
    element.addEventListener("click", onClick);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      element.removeEventListener("click", onClick);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open, setManually]);

  const choose = (name: Tab | "Closed") => {
    if (name !== "Closed") setTab(name);
    setManually(name !== "Closed");
  };

  return <section id="notch" className={h.section} ref={section}>
    <div className={h.inner}>
      <Reveal className={h.copy}>
        <p className={h.eyebrow}>THE NOTCH SHELF</p>
        <h2>Keep it close.</h2>
        <p className={h.description}>Music, focus, and files.{" "}<br/>Hover or click to open.</p>
        <div className={h.controls} role="group" aria-label="Preview notch view" ref={controls}>
          {(["Home", "Files", "Closed"] as const).map(name => <button key={name} type="button" aria-pressed={view === name} aria-controls="notch-desktop-preview" onClick={() => choose(name)}>{name}</button>)}
        </div>
        <ul className={h.notchPoints}>
          <li><b>Open it your way.</b> Reach the notch or click it. Turn either behavior off in Settings.</li>
          <li><b>Gone when you are.</b> Move away, press Esc, or click outside. Clicked open, it stays until you close it.</li>
          <li><b>Drop anything on it.</b> Drag files to the File tray, or send them with AirDrop.</li>
        </ul>
        <p className={h.compatibility}>For Macs with a built-in notch.</p>
      </Reveal>
      <Reveal className={h.visual}>
        <div id="notch-desktop-preview" className={h.laptop} role="img" aria-label={`Notch shelf preview: ${previewNames[view]}. The real DockGrove app bar, usage widget, dragon companion and window cube sit below. Sample data.`}>
          <div className={h.lid}>
            <div className={h.display} ref={display}>
              <div className={h.surface} aria-hidden="true">
                <div className={h.menuBar}><span><b>Finder</b> File <i>Edit</i><i>View</i></span><span>Wi-Fi <em/> Tue 9:41</span></div>
                <div className={h.desktopWindow}>
                  <div className={h.windowHeader}><span><i/><i/><i/></span><b>Ideas for the week</b></div>
                  <div className={h.windowBody}><aside><b>Favorites</b><span>Recents</span><span>Projects</span><span>Downloads</span></aside><div><small>ROOM FOR YOUR NEXT IDEA</small><h3>Make something<br/>you love.</h3><div className={h.swatches}><i/><i/><i/></div></div></div>
                </div>
                <div className={h.realDock}><Image src="/assets/dockgrove-native-bar.png" alt="" width={2312} height={216} sizes="80vw"/></div>
                {open && <div className={h.shelf} ref={shelf} onPointerEnter={pointerEnteredShelf} onPointerLeave={pointerLeft}>
                  <div className={h.shelfHeader}>
                    <span>{tab === "Home" ? "⌕  Find a widget" : "File tray · 2 files"}</span>
                    <span/>
                    <div>
                      {(["Home", "Files"] as const).map(name => <button key={name} type="button" tabIndex={-1} data-active={tab === name} onClick={() => setTab(name)}>{name}</button>)}
                      <button type="button" tabIndex={-1} className={h.collapse} onClick={() => setManually(false)}>⌃</button>
                    </div>
                  </div>
                  {tab === "Home"
                    ? <div className={h.cards}><div className={h.music}><span>♫</span><div><b>Your music</b><small>Sample playlist</small></div><i>▶</i></div><div className={h.focus}><small>◷ &nbsp; Focus</small><b>25:00 <i>▶</i></b></div></div>
                    : <div className={`${h.cards} ${h.fileCards}`}>{dropZones.map(zone => <div className={h.dropZone} key={zone.title}>
                      <svg viewBox="0 0 28 28" width="27" height="27">{zone.icon}</svg>
                      <div><b>{zone.title}</b><small>{zone.prompt}</small><em>{zone.action}</em></div>
                    </div>)}</div>}
                  {/* The two sample files fill a second page, as saved cards do in the app. */}
                  <div className={h.pages}><b/><i/>{tab === "Home" && <><i/><i/><i/></>}</div>
                </div>}
                {/* Pointer only, like the rest of the miniature. It sits above the shelf, as the real camera does. */}
                <div className={h.cameraHousing} ref={housing} onPointerEnter={pointerEnteredHousing} onPointerLeave={pointerLeft} onClick={() => setManually(!open)}><span/></div>
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
