"use client";

import type {CSSProperties, ReactNode} from "react";
import Image from "next/image";
import Reveal from "./Reveal";
import {WIDGETS} from "@/lib/home/widgets";
import s from "./Closing.module.css";

/** Small widget faces in the Dock's own style. Sample data, like everything else on the page. */
const FACES: {title: string; body: ReactNode}[] = [
  {title: "World clocks", body: <><b>09:41</b><small>Tokyo · London 01:41</small></>},
  {title: "Weather", body: <><b>72°</b><small>Partly cloudy</small></>},
  {title: "Drink water", body: <><b>5 of 8</b><span className={s.bar}><em style={{width: "62%"}}/></span></>},
  {title: "Habits", body: <><b>Read · Walk</b><span className={s.habitDots}><i className={s.on}/><i className={s.on}/><i className={s.on}/><i/><i/></span></>},
  {title: "Stopwatch", body: <><b className={s.mono}>00:12.48</b><small>Lap 3</small></>},
  {title: "GitHub", body: <><b>2 reviews</b><small>waiting on you</small></>},
  {title: "Currency", body: <><b>€92.40</b><small>from $100.00</small></>},
  {title: "Time progress", body: <><b>64%</b><span className={s.bar}><em style={{width: "64%"}}/></span></>},
  {title: "Reminders", body: <><b>Call the studio</b><small>Today, 4:00</small></>},
  {title: "System", body: <><b>CPU 18%</b><small>Memory 9.2 GB</small></>},
  {title: "Clipboard", body: <><b>“Ship Friday”</b><small>Copied 2 min ago</small></>},
  {title: "Quick note", body: <><b>Ideas for Friday</b><small>3 lines</small></>},
];
// Each looping copy must be wider than the window, so both rows carry every face, in different orders.
const ROWS = [FACES, [...FACES.slice(6), ...FACES.slice(0, 6)].reverse()];
const ICONS = ["finder", "safari", "notes", "calendar"];

function MiniDock({icons, widgets = 0, className = ""}: {icons: string[]; widgets?: number; className?: string}) {
  return <span className={`${s.miniDock} ${className}`}>
    {icons.map((n, i) => <Image key={`${n}${i}`} src={n === "dockgrove" ? "/assets/DockGrove-icon.png" : `/assets/apps/${n}.png`} alt="" width={28} height={28} unoptimized/>)}
    {Array.from({length: widgets}, (_, i) => <i key={i} className={s.miniTile}/>)}
  </span>;
}

export default function MoreSection() {
  return <section id="more" className={s.more}>
    <div className={s.moreHead}>
      <Reveal><h2>More than a<br/>row of apps.</h2></Reveal>
      <Reveal step={1}><p>{WIDGETS.length} widgets live alongside your apps — clocks, weather, habits, a stopwatch, your clipboard and more. Pick the ones you want and leave the rest.</p></Reveal>
    </div>

    <Reveal step={1}>
      <div className={s.wall} role="img" aria-label={`Sample widgets: ${FACES.map(f => f.title).join(", ")}`}>
        {ROWS.map((row, r) => <div key={r} className={`${s.wallRow} ${r ? s.reverse : ""}`} aria-hidden="true">
          {[0, 1].map(copy => <div key={copy} className={s.wallTrack}>
            {row.map(f => <span key={f.title} className={s.face}><small className={s.faceTitle}>{f.title}</small>{f.body}</span>)}
          </div>)}
        </div>)}
      </div>
    </Reveal>

    <div className={s.bento}>
      <Reveal className={`${s.tile} ${s.tileLayouts}`}>
        <div className={s.copy}><h3>A layout for every part of your day.</h3><p>Save your apps, widgets, colours and size as a layout. Switch from deep work to the evening in one click.</p></div>
        <div className={s.layoutStage} aria-hidden="true">
          <div className={s.segmentedMac}>{["Work", "Studio", "Evening"].map((name, i) => <span key={name} style={{"--step": i} as CSSProperties}>{name}</span>)}</div>
          <div className={s.layoutDocks}>
            <MiniDock icons={["finder", "safari", "notes", "calendar"]} widgets={2} className={s.layoutA}/>
            <MiniDock icons={["finder", "dockgrove", "safari"]} widgets={3} className={s.layoutB}/>
            <MiniDock icons={["notes", "calendar"]} widgets={1} className={s.layoutC}/>
          </div>
        </div>
      </Reveal>

      <Reveal step={1} className={`${s.tile} ${s.tileWallpaper}`}>
        <div className={s.copy}><h3>Bottom, top or floating.</h3><p>Put the Dock on any edge, or let it float.</p></div>
        <div className={s.desk} aria-hidden="true"><MiniDock icons={ICONS} className={s.glide}/></div>
      </Reveal>

      <Reveal step={2} className={`${s.tile} ${s.tileDark}`}>
        <div className={s.shapeStage} aria-hidden="true">
          <span className={s.shapeWidget}><b>72°</b><small>Cloudy</small></span>
        </div>
        <div className={s.copy}><h3>Card, square, circle or pill.</h3><p>Small shapes show a summary. Click for the full widget.</p></div>
      </Reveal>

      <Reveal step={0} className={`${s.tile} ${s.tileTwo}`}>
        <div className={s.copy}><h3>More than one Dock.</h3><p>Add extra Docks, each with its own apps, widgets and position.</p></div>
        <div className={s.twoDocks} aria-hidden="true">
          <span className={s.monitor}><MiniDock icons={["finder", "safari", "notes"]}/></span>
          <span className={s.monitor}><MiniDock icons={["calendar", "dockgrove"]} widgets={2}/></span>
        </div>
      </Reveal>

      <Reveal step={1} className={`${s.tile} ${s.tilePlain}`}>
        <ul className={s.promises}>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="10" width="14" height="10" rx="2.5"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg><span><b>Personal by design.</b> Notes and voice memos stay on your Mac, and API keys stay in Keychain. <a href="/privacy">Privacy details</a></span></li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h10M4 17h7"/></svg><span><b>Connect on your terms.</b> Choose the calendars, music players and usage sources you want.</span></li>
          <li><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8"/><path d="M12 8v4l2.5 2"/></svg><span><b>Designed for your pace.</b> Keyboard access and Reduce Motion support throughout.</span></li>
        </ul>
      </Reveal>
    </div>
  </section>;
}
