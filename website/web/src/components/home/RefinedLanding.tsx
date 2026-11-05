"use client";

import {useEffect, useRef, useState, useSyncExternalStore, type CSSProperties} from "react";
import Image from "next/image";
import Brand from "@/components/site/Brand";
import {COMPANIONS} from "@/lib/home/companions";
import {useReducedMotion} from "@/hooks/useReducedMotion";
import AppearanceStudio, {accentHex, signature, type Mood} from "./AppearanceStudio";
import {useAutoCycle} from "@/hooks/useAutoCycle";
import LauncherShowcase from "./LauncherShowcase";
import NotchShowcase from "./NotchShowcase";
import WindowShelfPreview from "./WindowShelfPreview";
import Reveal from "./Reveal";
import MoreSection from "./MoreSection";
import AskSection from "./AskSection";
import ReleaseSection from "./ReleaseSection";
import {useSectionFocus} from "@/hooks/useSectionFocus";
import {ACCENT_PACKS} from "@/lib/home/palette";
import s from "./RefinedLanding.module.css";

const DARK_QUERY="(prefers-color-scheme: dark)";
function usePrefersDark(){
  return useSyncExternalStore(cb=>{const m=window.matchMedia(DARK_QUERY);m.addEventListener("change",cb);return ()=>m.removeEventListener("change",cb);},()=>window.matchMedia(DARK_QUERY).matches,()=>true);
}
const NAV=[{id:"features",label:"Overview"},{id:"widgets",label:"Make it yours"},{id:"companions",label:"Companions"}] as const;

function Pet({name}: {name:string}) {
  const ref = useRef<HTMLSpanElement>(null);
  const [active, setActive] = useState(false);
  useEffect(() => {
    let visible = false;
    const refresh = () => setActive(visible && !document.hidden);
    const observer = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; refresh(); });
    if (ref.current) observer.observe(ref.current);
    document.addEventListener("visibilitychange", refresh);
    return () => { observer.disconnect(); document.removeEventListener("visibilitychange", refresh); };
  }, []);
  return <span ref={ref} data-active={active} aria-hidden="true" className={`${s.pet} ${name==="dragon"?s.dragon:""}`} style={{backgroundImage:`url(/assets/companions/${name}.png)`}}/>;
}
function DemoDock({light=false, graphite=false, accent, pet="dragon", section="all"}: {light?:boolean;graphite?:boolean;accent?:string;pet?:string;section?:string}) {
  const petName=COMPANIONS.find(companion=>companion.file===pet)?.ariaName??"Companion";
  const [musicPlaying,setMusicPlaying]=useState(true);
  const [seconds,setSeconds]=useState(1500);
  const [running,setRunning]=useState(false);
  const deadline=useRef(0);
  useEffect(()=>{
    if(!running)return;
    if(!deadline.current)deadline.current=Date.now()+1500*1000;
    const timer=window.setInterval(()=>{const left=Math.max(0,Math.ceil((deadline.current-Date.now())/1000));setSeconds(left);if(left===0)setRunning(false);},250);
    return ()=>window.clearInterval(timer);
  },[running]);
  const toggle=()=>{if(!running){deadline.current=Date.now()+(seconds||1500)*1000;}setRunning(!running);};
  return <div className={`${s.dock} ${light?s.light:""} ${graphite?s.graphite:""} ${section!=="all"?s.croppedDock:""}`} data-section={section} style={accent?{"--accent":accent} as CSSProperties:undefined}>
    <div className={s.apps}>{["finder","messages","safari","discord","vscode"].map(name=><Image key={name} src={`/assets/apps/${name}.png`} alt={name==="vscode"?"Visual Studio Code":name[0].toUpperCase()+name.slice(1)} width={64} height={64} unoptimized/>)}</div>
    <span className={s.divider}/>
    {section==="widgets"&&<><button type="button" className={`${s.tile} ${s.focus}`} onClick={toggle} aria-label={running?"Pause demo focus timer":"Start demo focus timer"}>
      <svg viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="20" r="16" fill="none" stroke="currentColor" opacity=".16" strokeWidth="5"/><circle cx="20" cy="20" r="16" fill="none" stroke="var(--blue)" strokeWidth="5" strokeDasharray={`${seconds/1500*100} 101`} transform="rotate(-90 20 20)" strokeLinecap="round"/></svg>
      <span><b>{Math.floor(seconds/60)}:{String(seconds%60).padStart(2,"0")}</b><small>{running?"Focusing":"Focus"}</small></span>
    </button>
    <div className={`${s.tile} ${s.calendar}`}><b>10:30</b><span>Design review</span><small>In 12 min</small></div></>}
    <div className={`${s.tile} ${s.usage}`}><b>Codex</b><span className={s.usageRow}>5h <span>82% left</span></span><i><em/></i><span className={s.usageRow}>Week <span>64% left</span></span><i><em style={{width:"64%"}}/></i></div>
    <div className={`${s.tile} ${s.music}`}><Image src="/assets/apps/spotify.png" alt="Spotify" width={44} height={44} unoptimized/><span><b>Deep focus</b><small>Spotify · Sample playlist</small><button className={s.musicControl} onClick={()=>setMusicPlaying(!musicPlaying)} aria-label={musicPlaying?"Pause Spotify preview":"Play Spotify preview"} aria-pressed={musicPlaying}><span aria-hidden="true">{musicPlaying?"Ⅱ":"▶"}</span> {musicPlaying?"Playing":"Paused"}</button></span></div>
    <div className={`${s.tile} ${s.cpu}`}><span className={s.usageRow}><b>CPU</b><span>18%</span></span><svg viewBox="0 0 100 28" aria-hidden="true"><path d="M0 24 L8 22 L14 23 L20 16 L26 19 L32 10 L38 16 L44 13 L50 17 L56 8 L62 14 L68 12 L74 19 L80 15 L86 20 L92 17 L100 19" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round"/></svg><small>System activity</small></div>
    <div key={pet} className={`${s.tile} ${s.dockPet}`} role="img" aria-label={`${petName} in a companion widget`}><Pet name={pet}/></div>
    <WindowShelfPreview/>
  </div>;
}
export default function RefinedLanding(){
  const reduced=useReducedMotion();
  const [paused,setPaused]=useState(false);
  const [mood,setMoodPick]=useState<Mood>("Automatic");
  const moving=!paused&&!reduced;
  const [lookRef,look]=useAutoCycle<HTMLDivElement>(ACCENT_PACKS.length,3000,false);
  const accent=signature(ACCENT_PACKS[look.index]);
  const [petsRef,pets]=useAutoCycle<HTMLDivElement>(COMPANIONS.length,2800,false);
  const prefersDark=usePrefersDark();
  const focus=useSectionFocus([...NAV.map(n=>n.id),"more","questions","download"]);
  const light=mood==="Pearl"||(mood==="Automatic"&&!prefersDark);
  const accentColor=accentHex(accent,light);
  const [menu,setMenu]=useState(false);
  const chosen=COMPANIONS[pets.index];
  const pet=chosen.file;
  return <div className={`home-theme ${s.page}`} data-motion={moving?"on":"off"} style={{"--blue":"#3478f6"} as CSSProperties}>
    <a href="#main" className={s.skip}>Skip to content</a>
    <header className={s.header}><nav aria-label="Main navigation"><Brand href="#top"/><div className={`${s.navLinks} ${menu?s.open:""}`}>
      {NAV.map(n=><a key={n.id} href={`#${n.id}`} className={focus===n.id?s.navActive:""} aria-current={focus===n.id?"location":undefined} onClick={()=>setMenu(false)}>{n.label}</a>)}
    </div><a className={s.button} href="#download">Explore the Dock</a><button className={s.menu} aria-label="Toggle navigation" aria-expanded={menu} onClick={()=>setMenu(!menu)} onKeyDown={e=>{if(e.key==="Escape")setMenu(false);}}>☰</button></nav></header>
    <main id="main">
      <section id="top" className={s.hero}>
        <div className={s.stage} aria-label="Interactive Dock illustration with sample data"><DemoDock/><div className={s.stageCaption}><span>Click the cube to find a window. <small>Interactive sample data.</small></span><button onClick={()=>setPaused(!paused)} aria-pressed={paused}>{paused?"Play motion":"Pause motion"}</button></div></div>
        <div className={s.heroCopy}><p className={s.eyebrow}>A LITTLE SPACE. A BETTER EVERYDAY.</p><h1>Your Mac.<br/>Everything within reach.</h1><p className={s.lead}>Apps, live widgets, and AI usage in one beautifully personal Dock.</p><div className={s.actions}><a className={s.button} href="#download">Explore DockGrove</a><a className={s.playLink} href="#widgets"><span aria-hidden="true">▷</span>Try it in action</a></div><p className={s.fine}>For macOS 14 and later · Apple silicon &amp; Intel</p></div>
      </section>
      <section id="features" className={s.features}><Reveal className={s.sectionHeading}><p className={s.eyebrow}>LESS SEARCHING. MORE DOING.</p><h2>Less switching. More living.</h2><p className={s.sectionLead}>Your everyday essentials, together in a space that feels like you.</p></Reveal><div className={s.cards}>
        <Reveal step={0}><article><div className={s.cardImage} inert aria-hidden="true"><DemoDock section="apps"/></div><h3>Your apps. One familiar place.</h3><p>Pin your essentials, search your applications, and arrange things your way.</p></article></Reveal>
        <Reveal step={1}><article><div className={s.cardImage} inert aria-hidden="true"><DemoDock section="widgets"/></div><h3>Useful widgets, always close.</h3><p>Keep time, events, notes, and your next small task in view.</p></article></Reveal>
        <Reveal step={2}><article id="intelligence"><div className={s.cardImage} inert aria-hidden="true"><DemoDock section="usage"/></div><h3>Know what’s left.</h3><p>See supported AI usage at a glance. Preview shows sample data.</p></article></Reveal>
      </div></section>
      <NotchShowcase/>
      <LauncherShowcase playing={false}/>
      <section id="widgets" className={s.workspace}><div className={s.workspaceInner}><Reveal><p className={s.eyebrow}>FEELS LIKE YOUR MAC.</p><h2>Make room for<br/>your way of working.</h2><p>A quiet look for deep work. A little color for everything else. Try your own combination.</p><div style={{"--accent":accentColor} as CSSProperties}><AppearanceStudio mood={mood} onPickMood={setMoodPick} show={look} showRef={lookRef} light={light}/></div></Reveal><Reveal step={1} className={s.workspaceDocks}><DemoDock light={light} graphite={mood==="Graphite"} accent={accentColor} pet={pet}/><p>{mood}{mood==="Automatic"?` (${light?"light":"dark"} right now)`:""} · {accent.name} · {chosen.heading}. Sample data.</p></Reveal></div></section>
      <section id="companions" className={s.companions}><div className={s.companionIntro}><Reveal><p className={s.eyebrow}>SMALL FRIENDS. BIG PERSONALITIES.</p><h2>A little company.<br/>A lot of character.</h2><p>Nine companions to make your Dock feel like yours. More room to roam, with care and details just a click away.</p><p className={s.meetAll}>Meet all nine companions <span aria-hidden="true">→</span></p></Reveal>
        <Reveal step={1}><div ref={petsRef} {...pets.bind} className={s.petShow} role="group" aria-label="Choose a companion">
          <div className={s.petSpotlight}><div key={pet} className={s.petHero}><Pet name={pet}/></div><div key={pet+"-text"} className={s.petCaption} aria-live={pets.running?"off":"polite"}><b>{chosen.heading}</b><span>{chosen.tagline}</span></div></div>
          <div className={s.petStrip}>{COMPANIONS.map((c,i)=><button key={c.file} type="button" aria-label={`Show ${c.heading}`} aria-current={i===pets.index} className={i===pets.index?s.selectedPet:""} onClick={()=>pets.setIndex(i)}><div><Pet name={c.file}/></div>{i===pets.index&&<em className={s.petProgress} style={{animationDuration:`${pets.duration}ms`,animationPlayState:pets.running?"running":"paused"}}/>}</button>)}</div>
        </div></Reveal></div><div className={s.petStatus}><span className={s.statusDot}/>{chosen.heading} is in your Dock preview. Choose a friend above.</div></section>
      <MoreSection/>
      <AskSection/>
      <ReleaseSection/>
    </main><Reveal><footer className={s.footer}><Brand href="#top"/><p>Apps. Widgets. A little company.</p><div><a href="/privacy">Privacy</a><a href="#questions">FAQ</a><a href="/terms">Terms</a><a href="https://github.com/dylanlasensky/DockGrove/issues">Contact</a></div></footer></Reveal>
  </div>;
}
