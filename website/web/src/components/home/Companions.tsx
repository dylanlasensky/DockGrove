"use client";

import { useReveal } from "@/hooks/useReveal";
import { COMPANIONS, companionSprite } from "@/lib/home/companions";
import {
  eyebrowClass,
  fineMutedClass,
  h2Class,
  h2SpanClass,
  pClass,
  sectionClass,
  sectionIntroClass,
  sectionIntroLedeClass,
} from "@/lib/home/classes";
import styles from "./Companions.module.css";

export default function Companions() {
  const intro = useReveal<HTMLDivElement>();
  return (
    <section id="companions" className={`${sectionClass} bg-[var(--paper)]`}>
      <div ref={intro} className={`reveal ${sectionIntroClass}`}>
        <p className={eyebrowClass}>A LITTLE COMPANY</p>
        <h2 className={h2Class}>
          Small companions.
          <br />
          <span className={h2SpanClass}>Plenty of personality.</span>
        </h2>
        <p className={sectionIntroLedeClass}>
          Nine pixel-art animals, each with a shape and rhythm of their own.
          <br />
          They wander, blink, settle down and sleep while you work.
        </p>
      </div>
      <div className="mt-11 mb-6 grid grid-cols-3 gap-5 max-[700px]:grid-cols-2 max-[700px]:gap-3">
        {COMPANIONS.map((companion) => (
          <article
            key={companion.file}
            className={`${styles.card} rounded-3xl border border-[var(--line)] bg-[color-mix(in_srgb,var(--paper),#a3aab5_9%)] px-[18px] py-[26px] text-center max-[700px]:px-2.5 max-[700px]:py-5`}
          >
            <div
              className={`${styles.pet} pixel-pet`}
              role="img"
              aria-label={`${companion.ariaName}, animated pixel-art companion`}
              style={{ backgroundImage: `url(${companionSprite(companion)})` }}
            />
            <h3 className="m-0 text-[1.125rem] font-bold leading-[1.15] tracking-[-.02em]">
              {companion.heading}
            </h3>
            <p className={`${pClass} mt-2 text-[.8125rem] text-[var(--muted)]`}>
              {companion.tagline}
            </p>
          </article>
        ))}
      </div>
      <p className={`${fineMutedClass} text-center`}>
        Walking and flight previews from the app’s actual artwork. Animations pause when you
        prefer reduced motion.
      </p>
    </section>
  );
}
