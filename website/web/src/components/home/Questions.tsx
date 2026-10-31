import { FAQ } from "@/lib/home/faq";
import {
  eyebrowClass,
  focusRingClass,
  h2SpanClass,
  pClass,
  sectionClass,
} from "@/lib/home/classes";

/** FAQ: native <details>/<summary> disclosures, exactly like the original (no JS needed). */
export default function Questions() {
  return (
    <section
      id="questions"
      className={`${sectionClass} mx-auto grid max-w-[1440px] grid-cols-[1fr_1.1fr] gap-[100px] max-[1000px]:gap-[50px] max-[700px]:block`}
    >
      <div>
        <p className={eyebrowClass}>A FEW GOOD QUESTIONS</p>
        <h2 className="m-0 text-[clamp(42px,4.6vw,62px)] font-semibold leading-[1.04] tracking-[-.065em]">
          Before you
          <br />
          <span className={h2SpanClass}>make it yours.</span>
        </h2>
      </div>
      <div className="max-[700px]:mt-8">
        {FAQ.map((item) => (
          <details key={item.question} className="group border-b border-[var(--line)]">
            <summary
              className={`relative min-h-[44px] cursor-pointer list-none py-[26px] pr-[30px] text-[1rem] font-[550] leading-[normal] [&::-webkit-details-marker]:hidden after:absolute after:top-[23px] after:right-0 after:text-[1.5rem] after:leading-[normal] after:font-light after:text-[#868e83] after:content-['+'] group-open:after:content-['−'] max-[700px]:pr-[27px] max-[700px]:text-[.9375rem] ${focusRingClass}`}
            >
              {item.question}
            </summary>
            <p className={`${pClass} pr-5 pb-[25px] text-sm text-[#777f73]`}>{item.answer}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
