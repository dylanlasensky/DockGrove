"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";

const NAV_LINKS = [
  ["#experience", "Experience"],
  ["#intelligence", "AI usage"],
  ["#widgets", "Widgets"],
  ["#questions", "FAQ"],
] as const;

export default function SiteHeader() {
  const [open, setOpen] = useState(false);
  const toggleRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
        toggleRef.current?.focus();
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <header className="fixed left-1/2 top-[20px] z-50 w-[min(1120px,calc(100%-40px))] -translate-x-1/2 leading-[normal] max-[700px]:top-[12px] max-[700px]:w-[calc(100%-24px)]">
      <nav
        aria-label="Main navigation"
        className="flex flex-wrap items-center gap-[30px] rounded-[40px] border border-[#ffffffb5] bg-[#f9f9f9db] py-[10px] pl-[16px] pr-[13px] shadow-[0_4px_35px_#11121407] backdrop-blur-[24px] max-[1000px]:gap-[20px] max-[700px]:flex-nowrap max-[700px]:gap-[12px] max-[700px]:p-[9px_12px] max-[360px]:gap-[8px] max-[360px]:p-[10px]"
      >
        <a
          className="no-underline flex items-center gap-[10px] text-[1.1875rem] font-[650] tracking-[-.6px] max-[700px]:gap-[7px] max-[700px]:text-[1rem] max-[420px]:mr-auto max-[360px]:gap-[6px]"
          href="#top"
          aria-label="DockGrove home"
        >
          <Image
            className="h-[40px] w-[168px] shrink-0 rounded-[5px] bg-white object-contain max-[700px]:h-[33px] max-[700px]:w-[138px]"
            src="/assets/DockGrove-wordmark.png"
            width={168}
            height={40}
            alt="DockGrove"
            priority
            unoptimized
          />
        </a>
        <div className="m-auto flex gap-[27px] text-[0.75rem] text-[#52555b] max-[1000px]:gap-[18px] max-[700px]:hidden">
          {NAV_LINKS.map(([href, label]) => (
            <a key={href} href={href} className="m-0 no-underline hover:text-black">
              {label}
            </a>
          ))}
        </div>
        <a
          className="no-underline inline-flex min-h-[44px] items-center justify-center gap-[18px] rounded-[30px] border-0 bg-[var(--ink)] px-[18px] py-[11px] text-center text-[0.75rem] font-[550] text-white transition-[transform,background] duration-250 hover:-translate-y-[2px] hover:bg-[#3a3d43] active:brightness-[.92] max-[700px]:ml-auto max-[700px]:gap-[10px] max-[700px]:px-[13px] max-[700px]:py-[10px] max-[700px]:text-[0.6875rem] max-[420px]:hidden"
          href="#download"
        >
          Get DockGrove <span aria-hidden="true" className="text-[1.1875rem]">↗</span>
        </a>
        <button
          ref={toggleRef}
          type="button"
          className="hidden min-h-[44px] min-w-[44px] shrink-0 cursor-pointer border-0 bg-transparent text-[1.25rem] max-[700px]:block max-[420px]:w-[44px]"
          aria-label={open ? "Close navigation" : "Open navigation"}
          aria-expanded={open}
          aria-controls="mobile-menu"
          onClick={() => setOpen((value) => !value)}
        >
          ☰
        </button>
      </nav>
      <div
        className="mt-[10px] rounded-[20px] bg-[#f7f7f7f5] p-[20px] backdrop-blur-[20px]"
        id="mobile-menu"
        hidden={!open}
      >
        {[...NAV_LINKS, ["#download", "Release & pricing"] as const].map(([href, label]) => (
          <a key={href} href={href} className="m-0 no-underline block p-[12px]" onClick={() => setOpen(false)}>
            {label}
          </a>
        ))}
      </div>
    </header>
  );
}
