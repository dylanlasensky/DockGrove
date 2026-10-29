import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../public/app.js',import.meta.url),'utf8');
function element(){return {textContent:'',hidden:false,disabled:false,value:'',events:{},addEventListener(type,fn){this.events[type]=fn;},setAttribute(){},append(){},replaceChildren(){},focus(){}};}
function browser(ids,replies,{search='',hash=''}={}){
 const els=Object.fromEntries(ids.map(id=>[id,element()])),calls=[],timers=[],order=[];
 const location={search,hash,pathname:'/purchase.html',assign(url){calls.push(['redirect',url]);}};
 const context={console,URL,URLSearchParams,Intl,Error,setTimeout(fn){timers.push(fn);},clearTimeout(){},location,
 history:{replaceState(_a,_b,url){order.push('clear-fragment');location.hash='';calls.push(['replace',url]);}},
 window:{location},navigator:{clipboard:{writeText:async()=>{}}},
 document:{querySelector:s=>els[s]??null,querySelectorAll:s=>[],createElement:()=>element(),createTextNode:s=>s,documentElement:{dataset:{},removeAttribute(){}}},
 async fetch(url,options){calls.push([url,options]);order.push('fetch:'+url);const data=replies[url];if(!data)return {ok:false,json:async()=>({error:'Unavailable'})};return {ok:data.ok!==false,json:async()=>data.body};}
 };
 vm.runInNewContext(source,context);return {els,calls,timers,order,location};
}
const settle=()=>new Promise(r=>setImmediate(r));
{
 const b=browser(['#checkout-button','#checkout-status'],{'/api/product':{body:{amount:999,currency:'usd',deviceLimit:3,mode:'test',available:false}}});await settle();
 assert.equal(b.els['#checkout-button'].disabled,true);assert.match(b.els['#checkout-status'].textContent,/not enabled/);
}
{
 const b=browser(['#checkout-button','#checkout-status'],{'/api/product':{body:{amount:999,currency:'usd',deviceLimit:3,mode:'live',available:true}}});await settle();
 assert.equal(b.els['#checkout-button'].disabled,true,'Candidate never enables live checkout');
}
{
 const b=browser(['#checkout-button','#checkout-status'],{'/api/product':{body:{amount:999,currency:'usd',deviceLimit:3,mode:'test',available:true}},'/api/checkout':{body:{url:'https://checkout.stripe.com.evil.example/steal'}}});await settle();
 await b.els['#checkout-button'].events.click();assert(!b.calls.some(c=>c[0]==='redirect'));assert.match(b.els['#checkout-status'].textContent,/unexpected destination/);
}
{
 const b=browser(['#checkout-button','#checkout-status'],{'/api/product':{body:{amount:999,currency:'usd',deviceLimit:3,mode:'test',available:true}},'/api/checkout':{body:{url:'https://checkout.stripe.com/c/pay/test_fixture'}}});await settle();
 await b.els['#checkout-button'].events.click();assert(b.calls.some(c=>c[0]==='redirect'&&c[1]==='https://checkout.stripe.com/c/pay/test_fixture'));
}
{
 const b=browser(['#purchase-status','#purchase-offer','#license-output','#license-section'],{'/api/purchase':{body:{status:'failed'}}},{search:'?status=success&paid=true'});await settle();
 assert.equal(b.els['#license-output'].textContent,'','Success URL cannot create a license');assert.match(b.els['#purchase-status'].textContent,/failed/);
}
{
 const b=browser(['#purchase-status','#purchase-offer','#license-output','#license-section'],{'/api/purchase':{body:{status:'paid',licenseKey:'fixture-license'}}},{search:'?status=success'});await settle();
 assert.equal(b.els['#license-output'].textContent,'fixture-license');assert.equal(b.els['#purchase-offer'].hidden,true);
}
{
 const b=browser(['#purchase-status'],{},{});assert.match(b.els['#purchase-status'].textContent,/Choose test checkout/);assert.equal(b.calls.length,0);
}
{
 const b=browser(['#recovery-form','#recovery-status','#license-output','#license-section'],{'/api/recover/complete':{body:{licenseKey:'recovered-fixture'}}},{hash:'#token=one-time-test'});await settle();
 assert.equal(b.order[0],'clear-fragment');assert.equal(b.location.hash,'');assert.equal(b.els['#license-output'].textContent,'recovered-fixture');
}
{
 const b=browser(['#checkout-button','#checkout-status'],{'/api/product':{body:{amount:999,currency:'usd',deviceLimit:3,mode:'test',available:true}}});b.els['#checkout-button'].dataset={comingSoon:'true'};await settle();assert.equal(b.els['#checkout-button'].disabled,true);assert.equal(b.els['#checkout-button'].textContent,'Coming soon');await b.els['#checkout-button'].events.click();assert(!b.calls.some(c=>c[0]==='/api/checkout'),'Marketing page cannot initiate checkout');
}
console.log('PASS: 9 frontend behavior checks: coming-soon marketing gate, unavailable/live gating, redirect validation, server payment authority, default purchase offer, and recovery-token clearing.');
