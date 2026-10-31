"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { useReducedMotion } from "@/hooks/useReducedMotion";

const FOCUS_SECONDS = 1500;

function formatTime(seconds: number) {
  return `${Math.floor(seconds / 60)
    .toString()
    .padStart(2, "0")}:${(seconds % 60).toString().padStart(2, "0")}`;
}

function FocusTimer() {
  const [remaining, setRemaining] = useState(FOCUS_SECONDS);
  const [running, setRunning] = useState(false);
  const endRef = useRef(0);

  useEffect(() => {
    if (!running) return;
    const tick = () => {
      const left = Math.max(0, Math.ceil((endRef.current - Date.now()) / 1000));
      setRemaining(left);
      if (!left) setRunning(false);
    };
    const ticker = window.setInterval(tick, 250);
    tick();
    return () => window.clearInterval(ticker);
  }, [running]);

  const toggle = () => {
    if (running) {
      setRemaining(Math.max(0, Math.ceil((endRef.current - Date.now()) / 1000)));
      setRunning(false);
      return;
    }
    const start = remaining || FOCUS_SECONDS;
    if (!remaining) setRemaining(start);
    endRef.current = Date.now() + start * 1000;
    setRunning(true);
  };

  const label = running
    ? "Pause demo focus timer"
    : remaining
      ? "Start demo focus timer"
      : "Restart demo focus timer";

  return (
    <div className="mt-[8px] flex items-center justify-between gap-[16px] max-[700px]:gap-[6px]">
      <strong id="demo-time" className="text-[1.9375rem] font-medium tracking-[-1px] tabular-nums max-[700px]:text-[1.625rem]">
        {formatTime(remaining)}
      </strong>
      <button
        type="button"
        id="demo-play"
        className="h-[44px] w-[44px] min-w-[44px] shrink-0 cursor-pointer rounded-full border-0 bg-[#ffffff18] text-[0.75rem] text-white hover:bg-[#ffffff30] active:brightness-[.92]"
        aria-label={label}
        onClick={toggle}
      >
        {running ? "Ⅱ" : "▶"}
      </button>
    </div>
  );
}

function Desktop() {
  const reduced = useReducedMotion();
  const desktopRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const desktop = desktopRef.current;
    if (!desktop) return;
    let scheduled = false;
    const parallax = () => {
      scheduled = false;
      if (reduced || window.innerWidth < 701) {
        desktop.style.transform = "none";
        return;
      }
      const bounds = desktop.getBoundingClientRect();
      const progress = Math.max(0, Math.min(1, (window.innerHeight - bounds.top) / window.innerHeight));
      desktop.style.transform = `rotateX(${((1 - progress) * 7).toFixed(2)}deg)`;
    };
    const onScroll = () => {
      if (!scheduled) {
        scheduled = true;
        requestAnimationFrame(parallax);
      }
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", parallax);
    parallax();
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", parallax);
    };
  }, [reduced]);

  const dockCard =
    "rounded-[17px] border border-[#ffffff13] bg-[linear-gradient(135deg,#35383bd9,#232628d9)] p-[14px_17px] text-[#f5f5f7] max-[700px]:rounded-[12px] max-[700px]:p-[11px]";
  const kicker = "text-[.6875rem] font-semibold tracking-[.08em] text-[#9ca2a8]";
  const appIcon =
    "grid h-[32px] w-[32px] place-items-center rounded-[8px] text-[1.4375rem] shadow-[inset_0_0_0_1px_#ffffff2f]";

  return (
    <div
      ref={desktopRef}
      className="relative h-[460px] origin-bottom overflow-hidden rounded-t-[26px] border border-[#60656a] bg-[linear-gradient(135deg,#21252a,#0f1114_55%,#282e32)] shadow-[0_25px_80px_#1b273836] [transform:rotateX(5deg)] before:absolute before:left-[-20%] before:top-[32%] before:h-[90%] before:w-[115%] before:rotate-[-20deg] before:rounded-full before:border before:border-[#afbdb331] before:shadow-[0_-16px_80px_#aac4b119] before:content-[''] after:absolute after:left-[30%] after:top-[45%] after:h-[90%] after:w-[115%] after:rotate-[23deg] after:rounded-full after:border after:border-[#c7d8ef1c] after:shadow-[0_-30px_90px_#91a8c022] after:content-[''] max-[1000px]:h-[410px] max-[700px]:h-[340px] max-[700px]:rounded-t-[16px] motion-reduce:[transform:none]"
    >
      <div className="relative z-[1] flex justify-between bg-[#ffffff06] p-[15px_21px] text-[0.625rem] text-[#c2c4c6] max-[700px]:p-[11px_14px] max-[700px]:text-[0.5rem]">
        <span className="flex items-center gap-[8px]">
          <Image src="/assets/DockGrove-icon.png" alt="" width={18} height={18} unoptimized /> DockGrove
        </span>
        <span>Wednesday&nbsp; 9:41</span>
      </div>
      <div className="absolute left-[70px] top-[100px] text-[3.4375rem] leading-[1.05] tracking-[-3px] text-[#f2f4f1] max-[1000px]:left-[45px] max-[1000px]:top-[90px] max-[1000px]:text-[2.8125rem] max-[700px]:left-[27px] max-[700px]:top-[77px] max-[700px]:text-[2.25rem] max-[700px]:tracking-[-2px]">
        Less searching.
        <br />
        <span className="text-[#6b7279]">More doing.</span>
      </div>
      <div
        className="absolute bottom-[42px] left-1/2 z-[2] flex w-[calc(100%-64px)] max-w-[1050px] -translate-x-1/2 items-stretch justify-center gap-[10px] rounded-[26px] border border-[#ffffff2c] bg-[#111315dc] p-[11px] shadow-[0_10px_35px_#0009] backdrop-blur-[20px] max-[1000px]:max-w-[650px] max-[700px]:bottom-[34px] max-[700px]:w-[calc(100%-22px)] max-[700px]:gap-[6px] max-[700px]:rounded-[18px] max-[700px]:p-[7px]"
        id="hero-dock"
      >
        <div
          className="grid grid-cols-[repeat(2,32px)] content-center gap-[6px] p-[10px_7px] max-[700px]:hidden"
          aria-hidden="true"
        >
          <span className={`${appIcon} bg-[linear-gradient(90deg,#8eabc0_50%,#cbd7dd_50%)] text-[#23394b]`}>◒</span>
          <span className={`${appIcon} bg-[linear-gradient(140deg,#bdd2e3,#3b637b)] text-white`}>↗</span>
          <span className={`${appIcon} bg-[linear-gradient(135deg,#ba7b82,#64454d)] text-white`}>♫</span>
          <span className={`${appIcon} bg-[linear-gradient(140deg,#67716e,#1e2825)] text-[#d6e2dc]`}>⌘</span>
        </div>
        <div className={`${dockCard} min-w-[145px] flex-1 max-[700px]:min-w-0`}>
          <span className={kicker}>◷ &nbsp; FOCUS</span>
          <FocusTimer />
        </div>
        <div className={`${dockCard} min-w-[150px] flex-1 max-[700px]:min-w-0`}>
          <span className={kicker}>✳ &nbsp; CLAUDE CODE</span>
          <div className="mt-[6px] flex items-center gap-[16px] max-[700px]:gap-[10px]">
            <strong className="text-[1.8125rem] font-[550] tracking-[-1px] max-[700px]:text-[1.5625rem]">
              76<span className="text-[0.8125rem]">%</span>
            </strong>
            <span className="text-[.5625rem] text-[#a5abb1] max-[700px]:text-[.6875rem]">
              remaining
              <br />
              5-hour window
            </span>
          </div>
          <div className="mt-[8px] h-[4px] overflow-hidden rounded-[10px] bg-[#ffffff15]">
            <i className="block h-full rounded-[10px] bg-[#c0d7c7] transition-[width] duration-600 ease-[var(--ease)]" style={{ width: "76%" }} />
          </div>
        </div>
        <div className={`${dockCard} flex min-w-0 flex-[1.6] items-center gap-[14px] max-[1000px]:hidden`}>
          <div
            className="grid h-[57px] w-[57px] shrink-0 place-items-center rounded-[9px] bg-[linear-gradient(135deg,#b1bfb3,#425f59_55%,#263f39)]"
            aria-hidden="true"
          >
            <span className="mt-[6px] block [font-family:Georgia] text-[0.625rem] italic text-[#a4a9ae]">G</span>
          </div>
          <div>
            <strong className="block text-[0.75rem] leading-[1.3]">A quieter kind of focus</strong>
            <span className="mt-[6px] block text-[0.625rem] text-[#a4a9ae]">Made for this moment</span>
          </div>
          <span className="ml-auto text-[1.375rem] text-[#a3b6aa]" aria-hidden="true">
            ♫
          </span>
        </div>
      </div>
      <span className="absolute bottom-[16px] left-0 w-full text-center text-[.6875rem] tracking-[.1em] text-[#b5bdc5]">
        INTERACTIVE ILLUSTRATION · SAMPLE DATA
      </span>
    </div>
  );
}

export default function Hero() {
  return (
    <section
      className="relative scroll-mt-[100px] overflow-hidden bg-[radial-gradient(ellipse_at_50%_66%,#e7e8e5_0,transparent_55%)] pt-[156px] leading-[normal] max-[700px]:pt-[140px]"
      id="top"
    >
      <div className="relative z-[2] text-center min-[1500px]:pt-[20px]">
        <p className="m-0 mb-[26px] text-[0.6875rem] font-[650] leading-[1.55] tracking-[.15em] max-[700px]:mb-[22px] max-[700px]:text-[.6875rem]">
          <span className="mr-[8px] inline-block h-[6px] w-[6px] rounded-full bg-[#5a806b] align-[2px]" /> MADE FOR YOUR MAC
        </p>
        <h1 className="m-0 mx-0 mb-[25px] mt-[15px] text-[clamp(70px,10.7vw,155px)] font-semibold leading-[1.04] tracking-[-.065em] max-[1000px]:text-[6.25rem] max-[700px]:mb-[22px] max-[700px]:text-[clamp(3.5rem,13vw,5.625rem)] max-[700px]:tracking-[-.06em]">
          Find your{" "}
          <em className="ml-[.09em] [font-family:Georgia,'Times_New_Roman',serif] font-normal not-italic tracking-[-.07em] text-[#898e93]">
            flow.
          </em>
        </h1>
        <p className="m-0 text-[clamp(19px,2.1vw,27px)] leading-[1.35] tracking-[-.6px] text-[#70747a] max-[700px]:text-[1.3125rem]">
          Your apps. Your tools.
          <br />A little more room to think.
        </p>
        <div className="mx-0 mb-[18px] mt-[30px] flex items-center justify-center gap-[28px] max-[700px]:flex-col max-[700px]:gap-[20px]">
          <a
            className="no-underline inline-flex min-h-[44px] items-center justify-center gap-[32px] rounded-[30px] border-0 bg-[var(--ink)] px-[25px] py-[17px] text-center text-[0.875rem] font-[550] text-white transition-[transform,background] duration-250 hover:-translate-y-[2px] hover:bg-[#3a3d43] active:brightness-[.92]"
            href="#experience"
          >
            Explore DockGrove <span aria-hidden="true" className="text-[1.1875rem]">↗</span>
          </a>
          <a
            className="no-underline inline-flex items-center gap-[16px] text-[0.875rem] font-[550] hover:underline hover:underline-offset-[5px]"
            href="#experience"
          >
            Meet your new Dock <span aria-hidden="true">↓</span>
          </a>
        </div>
        <p className="m-0 text-[0.75rem] leading-[1.65] text-[var(--muted)]">macOS 14+ · Apple silicon & Intel · Release candidate</p>
      </div>
      <div
        className="relative mx-auto mt-[74px] max-w-[1440px] px-[70px] [perspective:1400px] min-[1500px]:max-w-[1400px] max-[1000px]:px-[35px] max-[700px]:mt-[45px] max-[700px]:px-[14px]"
        aria-label="Illustrated DockGrove preview with sample data"
      >
        <div className="pointer-events-none absolute left-[-35%] top-[-130px] h-[700px] w-[1300px] rotate-[-20deg] rounded-full border border-[#d6dad4]" />
        <div className="pointer-events-none absolute left-[30%] top-[-90px] h-[700px] w-[1300px] rotate-[22deg] rounded-full border border-[#d6dad4]" />
        <div className="mx-[12px] mb-[14px] flex justify-between text-[.6875rem] tracking-[.14em] text-[#59625c] max-[700px]:mx-[5px] max-[700px]:mb-[10px] max-[700px]:text-[.6875rem]">
          <span>THOUGHTFULLY AT HAND.</span>
          <span className="max-[700px]:hidden">01 / YOUR EVERYDAY</span>
        </div>
        <Desktop />
      </div>
      <div className="mx-auto flex max-w-[1200px] items-center justify-between p-[25px_35px_35px] text-[0.75rem] text-[#7b8086] max-[700px]:p-[22px_25px] max-[700px]:text-[.6875rem]">
        <span>A small space. A better rhythm.</span>
        <a
          href="#experience"
          aria-label="Scroll to the experience"
          className="grid h-[37px] w-[37px] place-items-center rounded-full border border-[#d5d7d7] max-[700px]:h-[44px] max-[700px]:w-[44px]"
        >
          ↓
        </a>
      </div>
    </section>
  );
}
