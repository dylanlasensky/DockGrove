"use client";

import type {ReactNode} from "react";
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

const DETAILS = [
  ["A layout for every mood.", "Save your apps, widgets, colors and size. Switch from work to the weekend in a click."],
  ["Find your favorite spot.", "Keep your Dock on an edge or let it float. Add another Dock when you need more room."],
  ["Small shape. Full story.", "Choose cards, squares, circles or pills. See a summary, then click for the full widget."],
  ["Personal by design.", "Notes and voice memos stay on your Mac. API keys stay in Keychain. You choose what to connect."],
];

export default function MoreSection() {
  return <section id="more" className={s.more}>
    <div className={s.moreHead}>
      <Reveal><p className={s.eyebrow}>ONLY WHAT YOU NEED.</p><h2>A little space.<br/>So many possibilities.</h2></Reveal>
      <Reveal step={1}><p>{WIDGETS.length} widgets, ready for your day. Keep the useful things close and leave the rest out of the way.</p></Reveal>
    </div>
    <Reveal>
      <div className={s.widgetGallery} aria-label="Widget previews with sample data">
        {[FACES[0], FACES[1], FACES[5], FACES[8], FACES[9], FACES[11]].map(f => <div key={f.title} className={s.widgetPreview}><span className={s.face}><small className={s.faceTitle}>{f.title}</small>{f.body}</span></div>)}
      </div>
      <p className={s.sampleNote}>Widget previews use sample data.</p>
      <details className={s.widgetDirectory}><summary>Explore all {WIDGETS.length} widgets <span aria-hidden="true">+</span></summary><ul>{WIDGETS.map(w => <li key={w.name}>{w.name}</li>)}</ul><p>Some widgets need a connected account or permission. AI availability depends on the source; API spend is separate from subscription limits.</p></details>
    </Reveal>
    <div className={s.detailGrid}>{DETAILS.map(([title, text]) => <Reveal key={title}><article><h3>{title}</h3><p>{text}</p></article></Reveal>)}</div>
    <p className={s.privacyLink}><a href="/privacy">Your privacy, explained ↗</a></p>
  </section>;
}
