"use client";

import { useReveal } from "@/hooks/useReveal";
import {
  eyebrowClass,
  focusRingClass,
  pClass,
  sectionClass,
  textLinkClass,
} from "@/lib/home/classes";

export default function PrivacySection() {
  const section = useReveal<HTMLElement>();
  return (
    <section ref={section} className={`reveal ${sectionClass} bg-[#e8ece5] text-center`}>
      <span className="mb-[27px] block text-[3.75rem] text-[#687d63]" aria-hidden="true">
        ⌁
      </span>
      <p className={eyebrowClass}>YOUR MAC. YOUR CONTROL.</p>
      <h2 className="m-0 text-[clamp(40px,5vw,65px)] font-semibold leading-[1.04] tracking-[-.065em]">
        Personal by design.
      </h2>
      <p
        className={`${pClass} mx-auto mt-[25px] mb-[30px] max-w-[600px] text-[1.125rem] text-[#73806d] max-[700px]:text-base`}
      >
        Notes and voice memos stay on your Mac. API keys stay in Keychain. Connect only the
        widgets you want, and grant permissions when a feature needs them.
      </p>
      <a className={`${textLinkClass} ${focusRingClass}`} href="/privacy">
        Read the privacy details <span aria-hidden="true">↗</span>
      </a>
    </section>
  );
}
