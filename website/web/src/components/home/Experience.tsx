"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { useReveal } from "@/hooks/useReveal";

const CAPTIONS = [
  "A familiar place for your favorite apps.",
  "Full screen. Nothing between you and your work.",
  "A place for every window. And room for your ideas.",
];

const STEPS = [
  {
    number: "01",
    title: "At home on your Mac.",
    body: "Search and pin your favorite apps. Keep useful widgets beside them. Turn on replacement mode to put DockGrove at the bottom edge, where your Dock belongs.",
  },
  {
    number: "02",
    title: "Space for the bigger picture.",
    body: "Go full screen and DockGrove steps out of view. Come back to your desktop and your tools are right where you left them.",
  },
  {
    number: "03",
    title: "Put windows in their place.",
    body: "Halves, quarters, a little more room, or the whole display. Arrange a window in a click, with Undo when you change your mind.",
  },
];

export default function Experience() {
  const intro = useReveal<HTMLDivElement>();
  const [active, setActive] = useState(0);
  const stepsRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = stepsRef.current;
    if (!container || !("IntersectionObserver" in window)) return;
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setActive(Number((entry.target as HTMLElement).dataset.step));
          }
        });
      },
      { rootMargin: "-25% 0px -35% 0px", threshold: 0 },
    );
    container.querySelectorAll<HTMLElement>("[data-step]").forEach((step) => observer.observe(step));
    return () => observer.disconnect();
  }, []);

  return (
    <section
      id="experience"
      className="mx-auto scroll-mt-[100px] p-[125px_max(6vw,24px)] pb-[50px] leading-[normal] [overflow-wrap:anywhere] max-[700px]:p-[80px_24px]"
    >
      <div ref={intro} className="reveal mx-auto max-w-[1120px]">
        <p className="m-0 mb-[26px] text-[0.6875rem] font-[650] leading-[1.55] tracking-[.15em]">A PLACE FOR WHAT MATTERS</p>
        <h2 className="m-0 text-[clamp(44px,6.3vw,84px)] font-semibold leading-[1.04] tracking-[-.065em]">
          Everything close.
          <br />
          <span className="text-[#737980]">Nothing in your way.</span>
        </h2>
        <p className="m-0 mt-[24px] max-w-[510px] text-[1.25rem] leading-[1.55] text-[#59625c] max-[700px]:text-[1.0625rem]">
          A native home for the little things that make a day feel effortless.
        </p>
      </div>
      <div
        className="mx-auto mt-[65px] grid max-w-[1120px] grid-cols-2 items-start gap-[90px] *:min-w-0 max-[1000px]:gap-[45px] max-[700px]:mt-[30px] max-[700px]:block"
        data-active={active}
      >
        <div className="sticky top-[170px] pt-[50px] max-[700px]:relative max-[700px]:top-auto max-[700px]:pt-0">
          <div
            className={`relative h-[320px] overflow-hidden rounded-[16px] border border-[#cdd1cf] shadow-[0_30px_55px_#1112140c] transition-[background] duration-600 max-[1000px]:h-[280px] max-[700px]:h-[270px] ${
              active === 1 ? "bg-[#d4ddd4]" : "bg-[#e7e8e5]"
            }`}
          >
            <div className="flex gap-[5px] border-b border-[#00000008] p-[13px]">
              <i className="h-[5px] w-[5px] rounded-full bg-[#c1c4bf]" />
              <i className="h-[5px] w-[5px] rounded-full bg-[#c1c4bf]" />
              <i className="h-[5px] w-[5px] rounded-full bg-[#c1c4bf]" />
            </div>
            <div
              className={`absolute left-[38px] top-[90px] transition-[width] duration-700 ease-[var(--ease)] ${
                active === 2 ? "w-[35%]" : "w-1/2"
              }`}
            >
              <span className="my-[20px] block h-[6px] w-[90%] rounded-[5px] bg-[#b8bfba]" />
              <span className="my-[20px] block h-[6px] w-[65%] rounded-[5px] bg-[#b8bfba]" />
              <span className="my-[20px] block h-[6px] w-[90%] rounded-[5px] bg-[#b8bfba]" />
              <span className="my-[20px] block h-[6px] w-[45%] rounded-[5px] bg-[#b8bfba]" />
            </div>
            <div
              className={`absolute bottom-[18px] right-[18px] top-[52px] overflow-hidden rounded-[9px] bg-[#c8d1c8] p-0 transition-all duration-700 ease-[var(--ease)] ${
                active === 2 ? "w-[44%] opacity-100" : "w-0 opacity-0"
              }`}
            >
              <span className="m-[25px_17px] block text-[0.875rem]">Space to focus.</span>
              <i className="m-[14px_17px] block h-[6px] w-[60%] rounded-[3px] bg-[#b0bdb1]" />
              <i className="m-[14px_17px] block h-[6px] w-[60%] rounded-[3px] bg-[#b0bdb1]" />
            </div>
            <div
              className={`absolute bottom-[15px] left-1/2 flex items-center gap-[7px] rounded-[15px] bg-[#23262b] p-[9px] transition-[transform,opacity] duration-[700ms,600ms] ease-[var(--ease),ease] ${
                active === 1 ? "translate-x-[-50%] translate-y-[90px] opacity-0" : "-translate-x-1/2"
              }`}
            >
              <Image src="/assets/DockGrove-icon.png" width={38} height={38} alt="DockGrove" unoptimized />
              <span className="h-[36px] w-[42px] rounded-[8px] border border-[#ffffff15] bg-[#ffffff0d]" />
              <span className="h-[36px] w-[42px] rounded-[8px] border border-[#ffffff15] bg-[#ffffff0d]" />
              <span className="h-[36px] w-[42px] rounded-[8px] border border-[#ffffff15] bg-[#ffffff0d]" />
              <span className="h-[36px] w-[42px] rounded-[8px] border border-[#ffffff15] bg-[#ffffff0d]" />
            </div>
          </div>
          <p className="m-0 mt-[27px] min-h-[36px] text-center text-[0.75rem] leading-[1.55] text-[#59625c]" id="story-caption">
            {CAPTIONS[active]}
          </p>
          <div className="mt-[10px] flex justify-center gap-[6px]" aria-hidden="true">
            {CAPTIONS.map((_, index) => (
              <i
                key={index}
                className={`h-[5px] transition-[width] duration-400 ${
                  index === active ? "w-[24px] rounded-[4px] bg-[#343b36]" : "w-[5px] rounded-full bg-[#c6cbc7]"
                }`}
              />
            ))}
          </div>
        </div>
        <div ref={stepsRef} className="max-[700px]:mt-[40px] max-[700px]:grid max-[700px]:gap-[28px]">
          {STEPS.map((step, index) => (
            <article key={step.number} data-step={index} className="min-h-[380px] py-[95px] max-[700px]:min-h-0 max-[700px]:p-[15px_0_25px]">
              <span className="mb-[24px] block text-[0.625rem] tabular-nums text-[#59625c] max-[700px]:mb-[14px]">{step.number}</span>
              <h3 className="m-0 text-[1.6875rem] font-bold leading-[1.15] tracking-[-.035em] max-[700px]:text-[1.625rem]">{step.title}</h3>
              <p className="m-0 mt-[20px] max-w-[390px] text-[1.0625rem] leading-[1.55] text-[#59625c] max-[700px]:max-w-none max-[700px]:text-[1rem]">
                {step.body}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
