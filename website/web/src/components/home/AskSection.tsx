"use client";

import Reveal from "./Reveal";
import {FAQ} from "@/lib/home/faq";
import s from "./Closing.module.scss";

export default function AskSection() {
  return <section id="questions" className={s.ask}>
    <Reveal className={s.askIntro}>
      <p className={s.eyebrow}>GOOD QUESTIONS.</p>
      <h2>A few things to know.</h2>
      <p>DockGrove is an early-access preview on its way to a commercial release. Here is what it does today, and what it doesn’t yet.</p>
      <ul className={s.askLinks}>
        <li><a href="/privacy">Privacy details <span aria-hidden="true">↗</span></a></li>
        <li><a href="/terms">Terms <span aria-hidden="true">↗</span></a></li>
        <li><a href="https://github.com/dylanlasensky/DockGrove/issues">Ask on GitHub <span aria-hidden="true">↗</span></a></li>
      </ul>
    </Reveal>
    <div className={s.askList}>
      {FAQ.map((item, i) => <Reveal key={item.question} step={i % 4}>
        <details className={s.qa} open={i === 0}>
          <summary><span>{item.question}</span><i aria-hidden="true"/></summary>
          <p>{item.answer}</p>
        </details>
      </Reveal>)}
    </div>
  </section>;
}
