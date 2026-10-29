'use strict';
const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
const reveals = document.querySelectorAll('.reveal');
if ('IntersectionObserver' in window && !reduced.matches) {
  const observer = new IntersectionObserver(entries => entries.forEach(entry => {
    if (entry.isIntersecting) { entry.target.classList.add('is-visible'); observer.unobserve(entry.target); }
  }), { threshold: 0.08 });
  document.documentElement.classList.add('motion-ready');
  reveals.forEach(el => observer.observe(el));
  reduced.addEventListener('change', e => { if(e.matches) { document.documentElement.classList.remove('motion-ready'); observer.disconnect(); } });
}
const menuButton = document.querySelector('.menu-toggle'), menu = document.querySelector('#mobile-menu');
menuButton.addEventListener('click', () => { const open=menuButton.getAttribute('aria-expanded')!=='true'; menuButton.setAttribute('aria-expanded',String(open));menuButton.setAttribute('aria-label',open?'Close navigation':'Open navigation');menu.hidden=!open; });
menu.querySelectorAll('a').forEach(a=>a.addEventListener('click',()=>{menu.hidden=true;menuButton.setAttribute('aria-expanded','false');menuButton.setAttribute('aria-label','Open navigation');}));
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!menu.hidden){menu.hidden=true;menuButton.setAttribute('aria-expanded','false');menuButton.setAttribute('aria-label','Open navigation');menuButton.focus();}});
const providers = {
  claude:{name:'Claude Code',value:'76',suffix:'%',unit:'5-hour allowance remaining',bar:76,detail:'Weekly and session windows, read locally from Claude Code’s supported status line.',description:'Connect the local status line for supported Claude Pro and Max allowance windows. No browser cookies or account password needed.'},
  codex:{name:'Codex',value:'82',suffix:'%',unit:'Reported allowance remaining',bar:82,detail:'The account windows and reset times supplied by your signed-in Codex app.',description:'Use your existing Codex sign-in to read its reported allowances and reset windows. Ordinary ChatGPT message counts are not included.'},
  gemini:{name:'Gemini CLI',value:'12.4',suffix:'k',unit:'Tokens in the imported session',bar:45,detail:'A local session report. Input, output, cached tokens, and requests by model.',description:'Import a Gemini CLI JSON report, or pipe one through WaveDock’s local capture command. This measures session activity, not remaining Gemini chat quota.'},
  api:{name:'API & teams',value:'148',suffix:'k',unit:'Input tokens · illustrative API report',bar:62,detail:'OpenAI and Claude organization usage, plus Cursor team activity.',description:'Connect provider admin credentials for organization API tokens or Cursor team activity. Keys stay in macOS Keychain and requests go directly to that provider.'}
};
const tabs=[...document.querySelectorAll('[data-provider]')];
function selectProvider(tab){const data=providers[tab.dataset.provider];tabs.forEach(t=>{const active=t===tab;t.setAttribute('aria-selected',String(active));t.tabIndex=active?0:-1;});document.querySelector('#provider-name').textContent=data.name;const value=document.querySelector('#provider-value');value.replaceChildren(document.createTextNode(data.value));const suffix=document.createElement('span');suffix.textContent=data.suffix;value.append(suffix);document.querySelector('#provider-unit').textContent=data.unit;document.querySelector('#provider-detail').textContent=data.detail;document.querySelector('#provider-description').textContent=data.description;document.querySelector('#provider-bar').style.width=data.bar+'%';}
tabs.forEach((tab,i)=>{tab.addEventListener('click',()=>selectProvider(tab));tab.addEventListener('keydown',e=>{let next;if(e.key==='ArrowRight')next=(i+1)%tabs.length;if(e.key==='ArrowLeft')next=(i-1+tabs.length)%tabs.length;if(e.key==='Home')next=0;if(e.key==='End')next=tabs.length-1;if(next!==undefined){e.preventDefault();selectProvider(tabs[next]);tabs[next].focus();}});});
const swatches=[...document.querySelectorAll('[data-color]')];
swatches.forEach(button=>button.addEventListener('click',()=>{document.documentElement.style.setProperty('--accent',button.dataset.color);swatches.forEach(b=>b.setAttribute('aria-pressed',String(b===button)));document.querySelector('#accent-name').textContent=button.getAttribute('aria-label').replace(' accent','')+'. Make it your own.';}));
document.querySelector('#custom-accent').addEventListener('input',e=>{document.documentElement.style.setProperty('--accent',e.target.value);swatches.forEach(b=>b.setAttribute('aria-pressed','false'));document.querySelector('#accent-name').textContent='Your custom accent. '+e.target.value.toUpperCase();});
const timerButton=document.querySelector('#demo-play'), timerText=document.querySelector('#demo-time');let remaining=1500,end=0,ticker=null;
function renderTimer(){if(end)remaining=Math.max(0,Math.ceil((end-Date.now())/1000));timerText.textContent=Math.floor(remaining/60).toString().padStart(2,'0')+':'+(remaining%60).toString().padStart(2,'0');if(!remaining)stopTimer();}
function stopTimer(){clearInterval(ticker);ticker=null;end=0;timerButton.textContent='▶';timerButton.setAttribute('aria-label',remaining?'Start demo focus timer':'Restart demo focus timer');}
timerButton.addEventListener('click',()=>{if(ticker){renderTimer();stopTimer();}else{if(!remaining)remaining=1500;end=Date.now()+remaining*1000;ticker=setInterval(renderTimer,250);timerButton.textContent='Ⅱ';timerButton.setAttribute('aria-label','Pause demo focus timer');renderTimer();}});
const story=document.querySelector('.story'),steps=[...document.querySelectorAll('[data-step]')];const captions=['A familiar place for your favorite apps.','Full screen. Nothing between you and your work.','A place for every window. And room for your ideas.'];
if('IntersectionObserver' in window){const observer=new IntersectionObserver(entries=>{entries.forEach(entry=>{if(entry.isIntersecting){const index=Number(entry.target.dataset.step);story.dataset.active=String(index);document.querySelector('#story-caption').textContent=captions[index];document.querySelectorAll('.story-dots i').forEach((dot,i)=>dot.classList.toggle('active',i===index));}});},{rootMargin:'-25% 0px -35% 0px',threshold:0});steps.forEach(step=>observer.observe(step));}
let scheduled=false;const desktop=document.querySelector('.desktop');
function parallax(){scheduled=false;if(reduced.matches||innerWidth<701){desktop.style.transform='none';return;}const bounds=desktop.getBoundingClientRect();const progress=Math.max(0,Math.min(1,(innerHeight-bounds.top)/innerHeight));desktop.style.transform='rotateX('+((1-progress)*7).toFixed(2)+'deg)';}
window.addEventListener('scroll',()=>{if(!scheduled){scheduled=true;requestAnimationFrame(parallax);}},{passive:true});window.addEventListener('resize',parallax);parallax();

const layoutButtons=[...document.querySelectorAll('[data-layout-choice]')];
layoutButtons.forEach(button=>button.addEventListener('click',()=>{document.querySelector('.layout-demo').dataset.layout=button.dataset.layoutChoice;layoutButtons.forEach(b=>b.setAttribute('aria-pressed',String(b===button)));}));
document.querySelector('#feed-pet').addEventListener('click',()=>{document.querySelector('#pet-reaction').textContent='A happy little purr. Thank you.';});
document.querySelector('#rest-pet').addEventListener('click',e=>{const resting=e.currentTarget.getAttribute('aria-pressed')!=='true';e.currentTarget.setAttribute('aria-pressed',String(resting));e.currentTarget.textContent=resting?'Wake up':'Nap time';document.querySelector('.pet-scene').classList.toggle('is-resting',resting);document.querySelector('#pet-reaction').textContent=resting?'Dreaming of your next good idea.':'A little company. A calmer day.';});
