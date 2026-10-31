"use client";

import type { ReactNode } from "react";
import { useReveal } from "@/hooks/useReveal";

const CARD =
  "reveal min-w-0 overflow-hidden rounded-[25px] border border-[#e4e6e2] bg-[#f9f9f7] p-[34px_34px_38px] max-[1000px]:p-[25px] max-[700px]:p-[24px]";
const VISUAL =
  "mb-[35px] flex h-[215px] max-[700px]:mb-[26px] max-[700px]:h-[185px]";
const TITLE = "m-0 text-[1.5625rem] font-bold leading-[1.15] tracking-[-.035em] max-[700px]:text-[1.5rem]";
const BODY = "m-0 mt-[15px] max-w-[410px] text-[0.9375rem] leading-[1.55] text-[#59625c] max-[700px]:text-[0.875rem]";
const KICKER = "text-[.6875rem] font-semibold tracking-[.08em] text-[#9ca2a8]";

function Card({ children }: { children: ReactNode }) {
  const ref = useReveal<HTMLElement>();
  return (
    <article ref={ref} className={CARD}>
      {children}
    </article>
  );
}

export default function Widgets() {
  const intro = useReveal<HTMLDivElement>();
  const tool =
    "flex h-[110px] min-w-0 max-w-[125px] flex-1 flex-col items-center justify-center rounded-[21px] border border-[#dce1da] bg-[linear-gradient(140deg,#eef1eb,#fafbf9)] text-[1.625rem] tracking-[-1px] shadow-[0_12px_22px_#00000005]";
  const toolLabel = "mt-[16px] text-[0.5rem] tracking-[.1em] text-[#8b9589]";

  return (
    <section
      id="widgets"
      className="scroll-mt-[100px] bg-[#eeefec] p-[125px_max(6vw,24px)] leading-[normal] [overflow-wrap:anywhere] max-[700px]:p-[80px_24px]"
    >
      <div ref={intro} className="reveal mx-auto max-w-[1120px]">
        <p className="m-0 mb-[26px] text-[0.6875rem] font-[650] leading-[1.55] tracking-[.15em]">SMALL TOOLS. REAL DIFFERENCE.</p>
        <h2 className="m-0 text-[clamp(44px,6.3vw,84px)] font-semibold leading-[1.04] tracking-[-.065em]">
          A Dock with
          <br />
          <span className="text-[#737980]">more to give.</span>
        </h2>
      </div>
      <div className="mx-auto mb-[30px] mt-[55px] grid max-w-[1120px] grid-cols-2 gap-[22px] max-[700px]:mt-[35px] max-[700px]:grid-cols-1 max-[700px]:gap-[17px]">
        <Card>
          <div className={`${VISUAL} items-center justify-center gap-[24px] overflow-hidden rounded-[15px] bg-[#e8ebe5]`}>
            <div className="grid h-[155px] w-[155px] shrink-0 place-items-center rounded-full bg-[repeating-radial-gradient(#272d29_0,#272d29_1px,#1d231f_2px,#1d231f_4px)] shadow-[5px_12px_20px_#1223192b] max-[1000px]:h-[120px] max-[1000px]:w-[120px] max-[700px]:h-[130px] max-[700px]:w-[130px]">
              <i className="h-[47px] w-[47px] rounded-full bg-[radial-gradient(#1d231f_6px,#9cab97_7px,#85977f)]" />
            </div>
            <div className="max-w-[150px] pr-[12px]">
              <strong className="block text-[0.875rem]">Your day. Your soundtrack.</strong>
              <span className="mt-[8px] block text-[0.625rem] text-[#848e83]">Spotify + Apple Music</span>
              <div className="mt-[24px] text-[1.0625rem] text-[#5c6b5b]" aria-hidden="true">
                ⏮ &nbsp; ▶ &nbsp; ⏭
              </div>
            </div>
          </div>
          <h3 className={TITLE}>A good day has a soundtrack.</h3>
          <p className={BODY}>
            Album art brings your soundtrack into the Dock. Optional colors sampled from the artwork set the mood, with clear controls for Spotify and Apple Music.
          </p>
        </Card>
        <Card>
          <div className={`${VISUAL} items-center justify-center gap-[20px] rounded-[15px] bg-[#f0eee9]`}>
            <div className="rounded-[13px] border border-[#e1ddd6] bg-[#fafaf9] p-[15px_22px] text-center">
              <span className="text-[0.625rem] tracking-[.09em] text-[#b88072]">WED</span>
              <strong className="block text-[3.1875rem] font-[450] tracking-[-3px]">28</strong>
            </div>
            <div className="max-w-[180px]">
              <span className={KICKER}>UP NEXT</span>
              <strong className="my-[9px] block text-[1rem]">Time to make something.</strong>
              <span className="text-[0.75rem] text-[#8a8f89]">10:00 – 10:30</span>
            </div>
          </div>
          <h3 className={TITLE}>A little ahead of your day.</h3>
          <p className={BODY}>See upcoming events from macOS calendars, including Google calendars connected through Internet Accounts.</p>
        </Card>
        <Card>
          <div className={`${VISUAL} items-center justify-center gap-[13px]`}>
            <span className={tool}>
              25:00<small className={toolLabel}>FOCUS</small>
            </span>
            <span className={tool}>
              ⇄<small className={toolLabel}>CONVERT</small>
            </span>
            <span className={tool}>
              ◉<small className={toolLabel}>RECORD</small>
            </span>
          </div>
          <h3 className={TITLE}>Less switching. More momentum.</h3>
          <p className={BODY}>A timer, a thought, a calculation. Keep notes, tasks, conversions, and local voice memos within reach.</p>
        </Card>
        <Card>
          <div className={`${VISUAL} relative flex-col items-start justify-start rounded-[16px] bg-[#1c2320] p-[24px] text-[#d9e5d9]`}>
            <div>
              <span className={KICKER}>CPU</span>
              <strong className="block text-[2.0625rem] font-medium">
                24<span className="text-[1rem]">%</span>
              </strong>
            </div>
            <svg
              viewBox="0 0 300 80"
              aria-hidden="true"
              className="absolute bottom-[15px] left-[20px] h-[85px] w-[calc(100%-40px)] fill-none stroke-[#aabfac] stroke-2"
            >
              <path d="M0 68L24 60L40 65L61 45L80 51L100 23L121 39L143 34L164 52L187 40L211 48L234 17L258 29L280 21L300 34" />
            </svg>
          </div>
          <h3 className={TITLE}>See how your Mac is doing.</h3>
          <p className={BODY}>Live CPU history, memory, network activity, and system audio controls. Useful information, quietly at hand.</p>
        </Card>
      </div>
      <p className="m-0 text-center text-[0.75rem] leading-[1.65] text-[var(--muted)]">
        Illustrations use sample data. Explore the full, current feature list in the{" "}
        <a href="https://github.com/dylanlasensky/DockGrove#readme" className="m-0 no-underline underline underline-offset-[3px]">
          project guide ↗
        </a>
        .
      </p>
    </section>
  );
}
