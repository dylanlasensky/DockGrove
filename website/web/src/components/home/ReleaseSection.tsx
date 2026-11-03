"use client";

import type {CSSProperties} from "react";
import Image from "next/image";
import Reveal from "./Reveal";
import {useProduct} from "@/lib/home/useProduct";
import s from "./Closing.module.css";

export default function ReleaseSection() {
  const product = useProduct(true);
  const perks = [
    {big: product.price, label: "once", note: "No subscription. Major version 1 and its maintenance updates."},
    {big: product.devices, label: "Macs", note: "Use one licence on up to three of your personal Macs."},
    {big: "14+", label: "macOS", note: "Universal app for Apple silicon and Intel Macs."},
  ];
  return <section id="download" className={s.release}>
    <Reveal className={s.launchDock}>
      <div className={s.dockRow} aria-hidden="true">
        {["finder", "safari"].map(n => <Image key={n} src={`/assets/apps/${n}.png`} width={52} height={52} alt="" unoptimized/>)}
        <span className={s.bouncer}><Image src="/assets/DockGrove-icon.png" width={64} height={64} alt="" unoptimized/><i className={s.runDot}/></span>
        {["notes", "calendar"].map(n => <Image key={n} src={`/assets/apps/${n}.png`} width={52} height={52} alt="" unoptimized/>)}
      </div>
    </Reveal>
    <Reveal step={1} className={s.releaseHead}>
      <h2>Meet your new Dock.</h2>
      <p>A calmer desktop. A little more you.</p>
    </Reveal>
    <div className={s.perks}>
      {perks.map((perk, i) => <Reveal key={perk.label} step={i + 1}>
        <div className={s.perk} style={{"--step": i} as CSSProperties}>
          <b><span data-price={perk.label === "once" ? "" : undefined} data-devices={perk.label === "Macs" ? "" : undefined}>{perk.big}</span> <small>{perk.label}</small></b>
          <p>{perk.note}</p>
        </div>
      </Reveal>)}
    </div>
    <Reveal step={2} className={s.releaseCta}>
      <button id="checkout-button" data-coming-soon="true" className={s.cta} disabled>Coming soon</button>
      <p className={s.fine}>Planned one-time price · Commercial release in preparation. Checkout is not enabled.<br/>Signing, notarization and customer terms are still being finished.</p>
    </Reveal>
  </section>;
}
