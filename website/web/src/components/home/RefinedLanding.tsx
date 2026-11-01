"use client";

import {useEffect, useRef, useState, type CSSProperties} from "react";
import Image from "next/image";
import Brand from "@/components/site/Brand";
import {COMPANIONS} from "@/lib/home/companions";
import {useReducedMotion} from "@/hooks/useReducedMotion";
import {useProduct} from "@/lib/home/useProduct";
import s from "./RefinedLanding.module.css";

function Pet({name, moving=false}: {name:string;moving?:boolean}) {
  return <span aria-hidden="true" className={`${s.pet} ${moving?s.walk:""}`} style={{backgroundImage:`url(/assets/companions/${name}.png)`}}/>;
}
function DemoDock({light=false, pet="fox", animate=false, section="all"}: {light?:boolean;pet?:string;animate?:boolean;section?:string}) {
  const [seconds,setSeconds]=useState(1500);
  const [running,setRunning]=useState(false);
  const deadline=useRef(0);
  useEffect(()=>{
    if(!running)return;
    const timer=window.setInterval(()=>{const left=Math.max(0,Math.ceil((deadline.current-Date.now())/1000));setSeconds(left);if(left===0)setRunning(false);},250);
    return ()=>window.clearInterval(timer);
  },[running]);
  const toggle=()=>{if(!running){deadline.current=Date.now()+(seconds||1500)*1000;}setRunning(!running);};
  return <div className={`${s.dock} ${light?s.light:""} ${section!=="all"?s.croppedDock:""}`} data-section={section}>
    <div className={s.apps}>{["finder","safari","notes","calendar"].map(name=><Image key={name} src={`/assets/apps/${name}.png`} alt={name[0].toUpperCase()+name.slice(1)} width={64} height={64} unoptimized/>)}</div>
    <span className={s.divider}/>
    <button type="button" className={`${s.tile} ${s.focus}`} onClick={toggle} aria-label={running?"Pause demo focus timer":"Start demo focus timer"}>
      <svg viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="20" r="16" fill="none" stroke="currentColor" opacity=".16" strokeWidth="5"/><circle cx="20" cy="20" r="16" fill="none" stroke="var(--blue)" strokeWidth="5" strokeDasharray={`${seconds/1500*100} 101`} transform="rotate(-90 20 20)" strokeLinecap="round"/></svg>
      <span><b>{Math.floor(seconds/60)}:{String(seconds%60).padStart(2,"0")}</b><small>{running?"Focusing":"Focus"}</small></span>
    </button>
    <div className={`${s.tile} ${s.calendar}`}><b>10:30</b><span>Design review</span><small>In 12 min</small></div>
    <div className={`${s.tile} ${s.usage}`}><b>Codex</b><span>82% remaining</span><i><em/></i></div>
    <div className={`${s.tile} ${s.music}`}><span className={s.album} aria-hidden="true">♫</span><span><b>Quiet hours</b><small>Demo playlist</small><span aria-hidden="true">◂◂ &nbsp; Ⅱ &nbsp; ▸▸</span></span></div>
    <div className={s.dockPet}><Pet name={pet} moving={animate}/></div>
  </div>;
}
export default function RefinedLanding(){
  const reduced=useReducedMotion();
  const [paused,setPaused]=useState(false);
  const [light,setLight]=useState(false);
  const [pet,setPet]=useState("fox");
  const [menu,setMenu]=useState(false);
  const [allPets,setAllPets]=useState(false);
  const product=useProduct(true);
  const moving=!paused&&!reduced;
  const chosen=COMPANIONS.find(p=>p.file===pet)!;
  const featured=["fox","black-cat","dragon"];
  return <div className={`home-theme ${s.page}`} style={{"--blue":"#3478f6"} as CSSProperties}>
    <a href="#main" className={s.skip}>Skip to content</a>
    <header className={s.header}><nav aria-label="Main navigation"><Brand href="#top"/><div className={`${s.navLinks} ${menu?s.open:""}`}>
      <a href="#features" onClick={()=>setMenu(false)}>Features</a><a href="#widgets" onClick={()=>setMenu(false)}>Widgets</a><a href="#companions" onClick={()=>setMenu(false)}>Companions</a>
    </div><a className={s.button} href="#download">Explore the Dock</a><button className={s.menu} aria-label="Toggle navigation" aria-expanded={menu} onClick={()=>setMenu(!menu)} onKeyDown={e=>{if(e.key==="Escape")setMenu(false);}}>☰</button></nav></header>
    <main id="main">
      <section id="top" className={s.hero}>
        <div className={s.stage} aria-label="Interactive Dock illustration with sample data"><DemoDock animate={moving}/><div className={s.stageCaption}><span>Apps. Widgets. A little company.</span><button onClick={()=>setPaused(!paused)} aria-pressed={paused}>{paused?"Play motion":"Pause motion"}</button></div></div>
        <div className={s.heroCopy}><p className={s.eyebrow}>A LITTLE SPACE. A BETTER EVERYDAY.</p><h1>Your Mac.<br/>Everything within reach.</h1><p className={s.lead}>Apps, live widgets, and AI usage in one beautifully personal Dock.</p><div className={s.actions}><a className={s.button} href="#download">Explore DockGrove</a><a className={s.playLink} href="#widgets"><span aria-hidden="true">▷</span>Try it in action</a></div><p className={s.fine}>For macOS 14 and later · Apple silicon &amp; Intel</p></div>
      </section>
      <section id="features" className={s.features}><div className={s.sectionHeading}><p className={s.eyebrow}>LESS SEARCHING. MORE DOING.</p><h2>A better home for your everyday.</h2></div><div className={s.cards}>
        <article><div className={s.cardImage} inert aria-hidden="true"><DemoDock section="apps"/></div><h3>Your apps. One familiar place.</h3><p>Pin your essentials, search your applications, and arrange things your way.</p></article>
        <article><div className={s.cardImage} inert aria-hidden="true"><DemoDock section="widgets"/></div><h3>Useful widgets, always close.</h3><p>Keep time, events, notes, and your next small task in view.</p></article>
        <article id="intelligence"><div className={s.cardImage} inert aria-hidden="true"><DemoDock section="usage"/></div><h3>Know what’s left.</h3><p>See supported AI usage at a glance. Preview shows sample data.</p></article>
      </div></section>
      <section id="widgets" className={s.workspace}><div className={s.workspaceInner}><div><p className={s.eyebrow}>FEELS LIKE YOUR MAC.</p><h2>Make room for<br/>your way of working.</h2><p>Arrange your apps. Save your layouts. Set your tone.</p><div className={s.themeControls} aria-label="Preview Dock appearance"><button className={!light?s.active:""} aria-pressed={!light} onClick={()=>setLight(false)}><span className={s.darkSwatch}/>Dark</button><button className={light?s.active:""} aria-pressed={light} onClick={()=>setLight(true)}><span className={s.lightSwatch}/>Light</button></div><p className={s.workspaceNote}>The app can follow your Mac’s appearance automatically.</p></div><div className={s.workspaceDocks}><DemoDock light={light} pet={pet} animate={moving}/><p>Click the focus timer to start a session. Sample data.</p><div className={s.secondaryDock} inert aria-hidden="true"><DemoDock light={!light} pet="black-cat"/></div></div></div></section>
      <section id="companions" className={s.companions}><div className={s.companionIntro}><div><p className={s.eyebrow}>SMALL FRIENDS. BIG PERSONALITIES.</p><h2>A little company.<br/>A lot of character.</h2><p>Nine companions to make your Dock feel like yours. More room to roam, with care and details just a click away.</p><button className={s.textButton} onClick={()=>setAllPets(!allPets)} aria-expanded={allPets}>{allPets?"Show favorites":"Meet all nine companions"} <span aria-hidden="true">{allPets?"−":"+"}</span></button></div><div className={s.petChoices}>{(allPets?COMPANIONS.map(p=>p.file):featured).map(name=>{const info=COMPANIONS.find(p=>p.file===name)!;return <button key={name} aria-pressed={pet===name} className={pet===name?s.selectedPet:""} onClick={()=>setPet(name)}><div><Pet name={name} moving={moving&&pet===name}/></div><b>{info.heading}</b></button>;})}</div></div><div className={s.petStatus} aria-live="polite"><span className={s.statusDot}/>{chosen.heading} is in your Dock preview. {chosen.tagline}.</div></section>
      <section className={s.details}><article><span aria-hidden="true">⌘</span><h3>More than a row of apps.</h3><p>Quick app search, saved layouts, window controls, and a handy notch workspace on compatible Macs.</p></article><article><span aria-hidden="true">◈</span><h3>Connect on your terms.</h3><p>Choose the calendars, music players, and usage sources you want. Permissions stay in your control.</p></article><article><span aria-hidden="true">◷</span><h3>Designed for your pace.</h3><p>Gentle motion, keyboard access, and support for Reduce Motion help keep the little things comfortable.</p></article></section>
      <section id="questions" className={s.faq}><h2>A few things to know.</h2><details><summary>Does DockGrove replace the macOS Dock?</summary><p>DockGrove is a customizable companion to your desktop. You can hide the system Dock, but macOS still manages system features such as Mission Control and Spaces.</p></details><details><summary>Which AI usage can I see?</summary><p>Connect supported Codex and Claude Code reports, Gemini CLI sessions, and supported API or team usage sources. Each source reports different information; API spend is separate from a ChatGPT subscription allowance.</p></details><details><summary>Can I download it now?</summary><p>The commercial release is in preparation. Pricing and availability will be confirmed before checkout opens. No payment is taken from this preview.</p></details></section>
      <section id="download" className={s.download}><Image src="/assets/DockGrove-icon.png" width={76} height={76} alt="" unoptimized/><h2>Meet your new Dock.</h2><p>A calmer desktop. A little more you.</p><button id="checkout-button" data-coming-soon="true" className={s.button} disabled>Coming soon</button><p className={s.fine}><span data-price>{product.price}</span> planned one-time price · <span data-devices>{product.devices}</span> personal Macs<br/>Commercial release in preparation. Checkout is not enabled.</p></section>
    </main><footer className={s.footer}><Brand href="#top"/><p>Apps. Widgets. A little company.</p><div><a href="/privacy">Privacy</a><a href="#questions">FAQ</a><a href="/terms">Terms</a><a href="https://github.com/dylanlasensky/DockGrove/issues">Contact</a></div></footer>
  </div>;
}
