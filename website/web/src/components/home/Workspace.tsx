"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { useReveal } from "@/hooks/useReveal";

type Layout = "focus" | "create" | "unwind";

const LAYOUTS: { key: Layout; label: string }[] = [
  { key: "focus", label: "Focus" },
  { key: "create", label: "Create" },
  { key: "unwind", label: "Unwind" },
];

const APPS: [string, string][] = [
  ["Visual Studio Code", "</>"],
  ["ChatGPT", "✦"],
  ["Google Chrome", "◉"],
  ["GitHub Desktop", "⌘"],
  ["Unity", "◇"],
  ["Finder", "☺"],
  ["Music", "♫"],
  ["Safari", "↗"],
];

const PILL =
  "absolute flex items-center gap-[15px] rounded-[16px] border border-[#ffffff55] bg-[#242e29] p-[12px_18px] text-[#e5ece3] shadow-[0_8px_20px_#182e2922] transition-[top,left,transform] duration-650 ease-[var(--ease)] max-[700px]:gap-[12px] max-[700px]:p-[10px_14px]";
const SATELLITE: Record<Layout, string> = {
  focus: "left-1/2 top-[12px] -translate-x-1/2",
  create: "left-[18px] top-[92px] translate-x-0",
  unwind: "left-[67%] top-[160px] -translate-x-1/2",
};
const CARD = "min-w-0 overflow-hidden rounded-[28px] border border-[#e0e4dd] bg-[#edeeea] p-[30px] max-[700px]:p-[23px]";
const CARD_TITLE = "m-0 text-[1.6875rem] font-bold leading-[1.15] tracking-[-.035em]";
const CARD_BODY = "m-0 mt-[15px] text-[0.9375rem] leading-[1.55] text-[#59625c]";
const CARD_FINE = "m-0 mt-[15px] text-[0.625rem] leading-[1.65] text-[#59625c]";
const TEXT_BUTTON =
  "min-h-[44px] min-w-[44px] cursor-pointer border-0 bg-transparent py-[10px] text-[.8125rem] text-[#344d3a] underline active:brightness-[.92]";

function LayoutDemo() {
  const [layout, setLayout] = useState<Layout>("focus");
  return (
    <>
      <div
        className="relative h-[260px] overflow-hidden rounded-[18px] bg-[linear-gradient(135deg,#bfc9c0,#dce1d8)] max-[700px]:h-[230px]"
        data-layout={layout}
        aria-label="Illustrated multiple Dock layouts"
      >
        <div className="absolute bottom-[70px] left-[45px] right-[45px] top-[50px] flex gap-[8px] rounded-[10px] border border-[#ffffff9f] bg-[#f2f4efc9] p-[20px] shadow-[0_10px_25px_#18352b14] max-[700px]:left-[25px] max-[700px]:right-[25px]">
          <span className="w-1/2 rounded-[5px] bg-[#d5ded2]" />
          <span className="w-1/2 rounded-[5px] bg-[#d5ded2]" />
        </div>
        <div className={`${PILL} text-[1.125rem] ${SATELLITE[layout]}`}>
          <span>◷</span>
          <span>✳</span>
          <span>◉</span>
        </div>
        <div className={`${PILL} bottom-[12px] left-1/2 -translate-x-1/2`}>
          <Image src="/assets/DockGrove-icon.png" width={22} height={22} alt="" unoptimized />
          <span>✉</span>
          <span>♫</span>
          <span>↗</span>
        </div>
      </div>
      <div className="mt-[20px] flex flex-wrap justify-center gap-[8px]" role="group" aria-label="Preview a Dock layout">
        {LAYOUTS.map((item) => {
          const pressed = item.key === layout;
          return (
            <button
              key={item.key}
              type="button"
              aria-pressed={pressed}
              onClick={() => setLayout(item.key)}
              className={`min-h-[44px] min-w-[44px] cursor-pointer rounded-[20px] border p-[10px_17px] text-[0.75rem] active:brightness-[.92] ${
                pressed ? "border-[#29372e] bg-[#29372e] text-white" : "border-[#cdd4ca] bg-transparent text-[#344032]"
              }`}
            >
              {item.label}
            </button>
          );
        })}
      </div>
    </>
  );
}

function AppPicker() {
  const [selected, setSelected] = useState("Visual Studio Code");
  const [previous, setPrevious] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("Same position. A different app.");
  const replaceRef = useRef<HTMLButtonElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);
  const resultsRef = useRef<HTMLDivElement>(null);
  // Mirrors app.js: opening the panel focuses the search field once it is shown.
  useEffect(() => {
    if (open) searchRef.current?.focus();
  }, [open]);

  const matches = APPS.filter(([name]) => name.toLowerCase().includes(query.toLowerCase()));
  const icon = APPS.find(([name]) => name === selected)?.[1] ?? "";

  const openPicker = () => {
    setQuery("");
    setOpen(true);
  };
  const closePicker = () => {
    setOpen(false);
    replaceRef.current?.focus();
  };
  const choose = (name: string) => {
    setPrevious(selected);
    setSelected(name);
    setStatus(`Replaced ${selected} with ${name} in the same position.`);
    closePicker();
  };
  const undo = () => {
    if (!previous) return;
    setSelected(previous);
    setPrevious(null);
    setStatus("Replacement undone.");
    replaceRef.current?.focus();
  };

  return (
    <div className="mt-[26px] rounded-[18px] border border-[#cbd0cb] bg-[#f7f8f5] p-[20px] max-[700px]:p-[14px]">
      <div className="flex flex-wrap items-center gap-[12px] rounded-[12px] border border-[#d3d9d2] bg-white p-[12px] max-[700px]:gap-[8px]">
        <span className="rounded-[10px] bg-[#426d90] p-[12px] text-[18px] text-white" id="chosen-icon" aria-hidden="true">
          {icon}
        </span>
        <div className="min-w-[80px] flex-1">
          <small className="block text-[.6875rem] tracking-[.08em] text-[#59625c]">YOUR DOCK</small>
          <strong className="block text-[.875rem] [overflow-wrap:anywhere]" id="chosen-app">
            {selected}
          </strong>
        </div>
        <button
          ref={replaceRef}
          type="button"
          className="min-h-[44px] min-w-[44px] cursor-pointer rounded-[9px] border border-[#81897c] bg-[#eef0eb] p-[9px_12px] text-[.8125rem] text-[#28312a] hover:bg-[#dfe6dd] active:brightness-[.92]"
          id="replace-demo"
          aria-expanded={open}
          aria-controls="picker-panel"
          onClick={openPicker}
        >
          Replace…
        </button>
      </div>
      <div
        id="picker-panel"
        className="mt-[20px]"
        hidden={!open}
        onKeyDown={(event) => {
          if (event.key === "Escape") {
            event.preventDefault();
            closePicker();
          }
          if (event.key === "ArrowDown" && event.target === searchRef.current) {
            event.preventDefault();
            resultsRef.current?.querySelector<HTMLButtonElement>("button:not(:disabled)")?.focus();
          }
        }}
      >
        <label htmlFor="demo-search" className="block text-[.8125rem] font-semibold">
          Find an application
        </label>
        <input
          ref={searchRef}
          id="demo-search"
          type="search"
          placeholder="Search apps…"
          autoComplete="off"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          className="my-[9px] min-h-[44px] w-full min-w-0 rounded-[9px] border border-[#81897c] bg-white p-[12px] text-[#202820] placeholder:text-[#626870] placeholder:opacity-100"
        />
        <p id="results-status" className="m-0 mt-[14px] text-[.8125rem] leading-[1.65] text-[#59625c]" role="status" aria-live="polite">
          {open
            ? matches.length
              ? `${matches.length} sample ${matches.length === 1 ? "app" : "apps"} found. Use Tab or the down arrow to choose.`
              : "No matching sample apps. Try another name."
            : ""}
        </p>
        <div ref={resultsRef} id="demo-results" className="max-h-[240px] overflow-auto">
          {matches.map(([name, symbol]) => (
            <button
              key={name}
              type="button"
              disabled={name === selected}
              onClick={() => choose(name)}
              className="flex min-h-[44px] min-w-[44px] w-full cursor-pointer items-center gap-[10px] border-0 bg-transparent p-[12px] text-left text-[.875rem] leading-[1.55] text-[#263027] hover:rounded-[8px] hover:bg-[#e7ece3] active:brightness-[.92] disabled:cursor-default disabled:opacity-55"
            >
              <span className="w-[25px]">{symbol}</span>
              {name}
            </button>
          ))}
          {!matches.length && <p className="m-0 text-[0.75rem] leading-[1.65] text-[var(--muted)]">No matching sample apps. Try another name.</p>}
        </div>
        <button type="button" className={TEXT_BUTTON} id="cancel-picker" onClick={closePicker}>
          Cancel
        </button>
      </div>
      <p className="m-0 mt-[14px] text-[.8125rem] leading-[1.55] text-[#59625c]" id="picker-status" role="status">
        {status}
      </p>
      <button type="button" className={TEXT_BUTTON} id="undo-picker" hidden={!previous} onClick={undo}>
        Undo replacement
      </button>
    </div>
  );
}

export default function Workspace() {
  const intro = useReveal<HTMLDivElement>();
  return (
    <section
      id="workspace"
      className="scroll-mt-[100px] bg-[#f7f7f4] p-[125px_max(6vw,24px)] leading-[normal] [overflow-wrap:anywhere] max-[700px]:p-[80px_24px]"
    >
      <div ref={intro} className="reveal mx-auto max-w-[1120px]">
        <p className="m-0 mb-[26px] text-[0.6875rem] font-[650] leading-[1.55] tracking-[.15em]">YOUR DOCK. YOUR RHYTHM.</p>
        <h2 className="m-0 text-[clamp(44px,6.3vw,84px)] font-semibold leading-[1.04] tracking-[-.065em]">
          More room
          <br />
          <span className="text-[#737980]">to be you.</span>
        </h2>
        <p className="m-0 mt-[24px] max-w-[510px] text-[1.25rem] leading-[1.55] text-[#59625c] max-[700px]:text-[1.0625rem]">
          A workspace for focus. A space for music.
          <br />
          Built around the way you work.
        </p>
      </div>
      <div className="mx-auto mt-[55px] grid max-w-[1120px] grid-cols-[1.2fr_1fr] gap-[24px] max-[700px]:mt-[30px] max-[700px]:grid-cols-1">
        <article className={CARD}>
          <LayoutDemo />
          <h3 className={`${CARD_TITLE} mt-[25px]`}>One Mac. Your spaces.</h3>
          <p className={CARD_BODY}>
            Keep up to four independent docks, each with its own widgets, display, theme and position. Choose a bottom edge, top edge, or a floating home.
          </p>
          <p className={CARD_FINE}>Interactive illustration · Sample layouts</p>
        </article>
        <article className={CARD}>
          <h3 className={CARD_TITLE}>The right app. Right there.</h3>
          <p className={CARD_BODY}>Search installed applications. Replace an app in the same position, and undo a change when you need to.</p>
          <AppPicker />
          <p className={CARD_FINE}>Interactive sample · This example does not change your Mac.</p>
        </article>
      </div>
      <div className="mx-auto mt-[65px] flex max-w-[900px] items-center gap-[30px] max-[700px]:mt-[40px] max-[700px]:gap-[18px]">
        <span className="text-[2.8125rem] text-[#718d7b]">↗</span>
        <div>
          <h3 className="m-0 text-[1.5625rem] font-bold leading-[1.15] tracking-[-.035em] max-[700px]:text-[1.4375rem]">A place for every window.</h3>
          <p className="m-0 mt-[12px] text-[1rem] leading-[1.55] text-[#59625c] max-[700px]:text-[0.875rem]">
            Enable snapping, hold Option and drag a title bar to an edge. See the placement before you release. Halves, quarters, maximize, and Undo.
          </p>
        </div>
      </div>
    </section>
  );
}
