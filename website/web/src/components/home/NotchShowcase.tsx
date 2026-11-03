"use client";

import {useState, type CSSProperties, type DragEvent} from "react";
import Reveal from "./Reveal";
import {useAutoCycle} from "@/hooks/useAutoCycle";
import {useSeen} from "@/hooks/useSectionFocus";
import s from "./Showcase.module.css";

const SLIDES = ["Home", "Widgets", "File tray", "AirDrop"] as const;
const SAMPLE_FILES = ["Brief.pdf", "Moodboard.png", "Notes.md"];

function fileLabel(count: number) {
  return `File tray · ${count} ${count === 1 ? "file" : "files"}`;
}

/** The notch shelf plays itself like a product film: it springs open on arrival, then steps through its pages. */
export default function NotchShowcase({playing}: {playing: boolean}) {
  const [sectionRef, seen] = useSeen<HTMLElement>();
  const [showRef, show] = useAutoCycle<HTMLDivElement>(SLIDES.length, 4200, playing && seen);
  const slide = show.index;
  const [dropped, setDropped] = useState<string[]>([]);
  const [over, setOver] = useState(false);
  const files = [...SAMPLE_FILES, ...dropped];

  // Files dropped on the preview stay in this page: only their names are read.
  const dragProps = {
    onDragOver: (e: DragEvent) => { e.preventDefault(); setOver(true); },
    onDragLeave: () => setOver(false),
    onDrop: (e: DragEvent) => {
      e.preventDefault(); setOver(false);
      const names = Array.from(e.dataTransfer.files, f => f.name).filter(n => n && !files.includes(n));
      if (names.length) { setDropped(d => [...d, ...names]); show.setIndex(2); }
    },
  };

  return <section id="notch" ref={sectionRef} className={s.notchSection}>
    <div className={s.notchInner}>
      <Reveal className={s.notchCopy}>
        <p className={s.eyebrow}>THE NOTCH, PUT TO WORK.</p>
        <h2>A shelf that lives<br/>above your work.</h2>
        <p>On Macs with a notch, hover the camera housing and DockGrove opens a small shelf with your music, a focus timer, widgets and a file tray. Pages slide past like this, and dragging a file up opens it.</p>
        <ul className={s.points}>
          {["Slides, not scrolling.|Each page fits the shelf. Pills show where you are.", "A tray for files in transit.|Park files and see the count at a glance.", "AirDrop from the top.|Drop files on the AirDrop zone to share them.", "Search widgets by name|right from the shelf."].map((line, i) => {
            const [bold, rest] = line.split("|");
            return <li key={bold} className={[0, 3, 1, 2][slide] === i ? s.pointActive : ""} style={{"--step": i} as CSSProperties}><b>{bold}</b> {rest}</li>;
          })}
        </ul>
      </Reveal>

      <div ref={showRef} {...show.bind} className={s.screen} aria-label="Notch shelf preview with sample data" role="group" aria-roledescription="slideshow">
        <div className={`${s.notch} ${seen ? s.notchOpen : ""}`}>
          {seen && <div className={s.shelf}>
            <div className={s.slideViewport} aria-live={show.running ? "off" : "polite"}>
              <div key={slide} className={s.slide} role="group" aria-roledescription="slide" aria-label={`Notch slide ${slide + 1} of ${SLIDES.length}: ${SLIDES[slide]}`}>
                {slide === 0 && <div className={s.row}>
                  <div className={`${s.card} ${s.musicCard}`}><span className={`${s.cover} ${s.spin}`} aria-hidden="true">♫</span><span><b>Quiet hours</b><small>Demo playlist</small><span className={s.eq} aria-hidden="true"><i/><i/><i/><i/><i/></span></span></div>
                  <div className={`${s.card} ${s.timerCard}`}><b className={s.ticking}>24:59</b><small>Focusing</small><i className={s.timerBar}><em/></i></div>
                </div>}
                {slide === 1 && <div className={s.row}>
                  <div className={s.card}><b>10:30</b><span>Design review</span><small>In 12 min</small></div>
                  <div className={s.card}><b>Codex</b><span>82% remaining</span><i className={s.meter}><em/></i></div>
                  <div className={s.card}><b>Notes</b><span>Ship the shelf</span><small>2 items left</small></div>
                </div>}
                {slide === 2 && <div className={s.trayWrap}>
                  <div className={s.trayHeader}><span>{fileLabel(files.length)}</span></div>
                  <div className={`${s.row} ${s.trayRow} ${over ? s.dropOver : ""}`} {...dragProps}>
                    {files.map((name, i) => <span key={name} className={`${s.fileChip} ${s.flyIn}`} style={{"--step": i} as CSSProperties}><span aria-hidden="true">▤</span>{name}</span>)}
                  </div>
                </div>}
                {slide === 3 && <div className={s.airDrop}>
                  <span className={s.airDropRings} aria-hidden="true"><i/><i/><i/></span>
                  <span className={s.airDropIcon} aria-hidden="true">◎</span>
                  <b>AirDrop</b>
                  <small className={s.sending}>Sending Brief.pdf to a nearby Mac…</small>
                </div>}
              </div>
            </div>
            <div className={s.pills} aria-label="Notch slides">
              {SLIDES.map((name, i) => <button key={name} type="button" aria-current={slide === i} aria-label={`Show notch slide ${i + 1} of ${SLIDES.length}: ${name}`} className={slide === i ? s.pillActive : ""} onClick={() => show.setIndex(i)}>
                {slide === i && <em className={s.pillFill} style={{animationDuration: `${show.duration}ms`, animationPlayState: show.running ? "running" : "paused"}}/>}
              </button>)}
            </div>
          </div>}
        </div>
        <p className={s.screenNote}>{show.running ? "Hover to pause. Drop a file here to add it to the tray — it stays on this page." : "Paused. Drop a file here to add it to the tray — it stays on this page."}</p>
      </div>
    </div>
  </section>;
}
