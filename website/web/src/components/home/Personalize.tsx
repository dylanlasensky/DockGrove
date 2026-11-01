"use client";

import { useState } from "react";
import { useReveal } from "@/hooks/useReveal";
import {
  APPEARANCES,
  DEFAULT_ACCENT,
  DEFAULT_ACCENT_NAME,
  SWATCHES,
  applyAccent,
  applyAppearance,
  customAccentCaption,
  swatchCaption,
  type Appearance,
} from "@/lib/home/accent";
import {
  cardKickerClass,
  eyebrowClass,
  fineMutedClass,
  focusRingClass,
  h2Class,
  sectionClass,
  sectionIntroClass,
  sectionIntroLedeClass,
} from "@/lib/home/classes";
import styles from "./Personalize.module.css";

export default function Personalize() {
  const intro = useReveal<HTMLDivElement>();
  const preview = useReveal<HTMLDivElement>();
  // index of the pressed preset swatch, or null once a custom color is chosen
  const [pressed, setPressed] = useState<number | null>(0);
  const [custom, setCustom] = useState(DEFAULT_ACCENT);
  const [caption, setCaption] = useState(DEFAULT_ACCENT_NAME);
  const [appearance, setAppearance] = useState<Appearance>("auto");

  return (
    <section id="personalize" className={`${sectionClass} overflow-hidden text-center`}>
      <div ref={intro} className={`reveal ${sectionIntroClass}`}>
        <p className={eyebrowClass}>DISTINCTLY YOURS</p>
        <h2 className={h2Class}>Set the tone.</h2>
        <p className={`${sectionIntroLedeClass} mx-auto`}>
          Quietly monochrome. A hint of color.
          <br />
          Or an accent that is entirely you.
        </p>
      </div>

      <div
        ref={preview}
        className="reveal relative mx-auto mt-[30px] grid h-[300px] max-w-[850px] place-items-center max-[700px]:mt-2.5 max-[700px]:h-[230px]"
      >
        <div
          className="absolute h-[150px] w-[80%] -rotate-[15deg] rounded-full border border-[#d7dcd5]"
          aria-hidden="true"
        />
        <div className={styles.dock}>
          {/* eslint-disable-next-line @next/next/no-img-element -- static export, exact original markup */}
          <img src="/assets/DockGrove-icon.png" width={54} height={54} alt="DockGrove" />
          <div className={styles.ring}>
            <span>82</span>
          </div>
          <div>
            <span className={`${cardKickerClass} ${styles.kicker}`}>IN YOUR ELEMENT</span>
            <strong className="mt-[9px] block text-[1.25rem] leading-[normal] font-medium tracking-[-.5px] max-[700px]:text-[.9375rem]">
              Make room for you.
            </strong>
          </div>
          <div className={styles.chart} aria-hidden="true">
            <i />
            <i />
            <i />
            <i />
            <i />
          </div>
        </div>
      </div>

      <div
        className="mb-[25px] flex flex-wrap items-center justify-center gap-[15px] max-[700px]:gap-[17px]"
        role="group"
        aria-label="Preview an accent color"
      >
        {SWATCHES.map((swatch, i) => (
          <button
            key={swatch.color}
            type="button"
            data-color={swatch.color}
            aria-pressed={pressed === i}
            aria-label={swatch.label}
            style={{ "--swatch": swatch.color } as React.CSSProperties}
            className={`h-11 w-11 min-h-[44px] min-w-[44px] cursor-pointer rounded-full border-[3px] border-[var(--paper)] bg-[var(--swatch)] shadow-[0_0_0_1px_#c0c5be] transition-transform duration-200 hover:scale-[1.14] active:brightness-[.92] aria-pressed:shadow-[0_0_0_2px_#3a443c] ${focusRingClass}`}
            onClick={() => {
              applyAccent(swatch.color);
              setPressed(i);
              setCaption(swatchCaption(swatch));
            }}
          />
        ))}
        <label
          className="relative grid h-11 w-11 cursor-pointer place-items-center overflow-hidden rounded-full border border-[#b8c0b6] text-[1.25rem] leading-[normal] text-[#727c6e] focus-within:outline-3 focus-within:outline-[#547cbb] focus-within:outline-offset-[5px]"
          htmlFor="custom-accent"
        >
          ＋
          <input
            id="custom-accent"
            type="color"
            value={custom}
            aria-label="Choose a custom accent color"
            className="absolute inset-0 h-full w-full cursor-pointer opacity-0"
            onChange={(e) => {
              const value = e.currentTarget.value;
              setCustom(value);
              applyAccent(value);
              setPressed(null);
              setCaption(customAccentCaption(value));
            }}
          />
        </label>
      </div>
      <p id="accent-name" className={`${fineMutedClass} text-center`} aria-live="polite">
        {caption}
      </p>

      <fieldset className="m-0 mx-auto mt-7 flex max-w-[380px] min-w-0 flex-wrap justify-center gap-1.5 border-0 p-[5px] max-[700px]:max-w-full">
        <legend className="m-0 mb-3 p-0 text-center text-[.8125rem] leading-[normal] text-[#59625c]">
          Preview Dock appearance
        </legend>
        {APPEARANCES.map((option) => (
          <label key={option.value} className="relative flex-[1_1_5rem]">
            <input
              type="radio"
              name="appearance"
              value={option.value}
              checked={appearance === option.value}
              className="peer absolute inset-0 m-0 h-full w-full cursor-pointer opacity-0"
              onChange={() => {
                setAppearance(option.value);
                applyAppearance(option.value);
              }}
            />
            <span className="flex min-h-[44px] items-center justify-center rounded-3xl border border-[#81897c] p-3 text-[.8125rem] peer-checked:border-[#29372e] peer-checked:bg-[#29372e] peer-checked:text-white peer-focus-visible:outline-3 peer-focus-visible:outline-[#3461a4] peer-focus-visible:outline-offset-4">
              {option.label}
            </span>
          </label>
        ))}
      </fieldset>
      <p className={`${fineMutedClass} mt-[18px] text-center`}>
        Automatic follows your Mac. Native glass where supported, translucent material elsewhere.
        <br />
        These controls change only this illustration.
      </p>
    </section>
  );
}
