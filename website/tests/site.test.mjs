import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';
import {PRODUCT} from '../backend/product.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../public');
const pages=['index.html','purchase.html','recover.html','privacy.html','terms.html'];
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const css=fs.readFileSync(path.join(root,'base.css'),'utf8');
const js=fs.readFileSync(path.join(root,'app.js'),'utf8');
new vm.Script(js);
for(const page of pages){
 const source=fs.readFileSync(path.join(root,page),'utf8');
 const ids=[...source.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);
 assert.equal(new Set(ids).size,ids.length,`${page}: unique identifiers`);
 assert(source.includes('name="viewport"')&&source.includes('lang="en"'),`${page}: responsive/language metadata`);
 for(const match of source.matchAll(/\b(?:href|src)="([^"]+)"/g)){
  const url=match[1];
  if(url.startsWith('#'))assert(ids.includes(url.slice(1)),`${page}: missing anchor ${url}`);
  if(url.startsWith('/')){const clean=url.split('#')[0].split('?')[0];assert(fs.existsSync(path.join(root,clean)),`${page}: missing local asset ${url}`);assert(!url.startsWith('/downloads/'),`${page}: no unprotected commercial download`);}
  if(url.startsWith('http'))assert.equal(new URL(url).protocol,'https:');
 }
 for(const match of source.matchAll(/aria-controls="([^"]+)"/g))assert(ids.includes(match[1]));
 assert(!source.includes('sk_test_')&&!source.includes('sk_live_')&&!source.includes('whsec_'));
}
assert(!fs.existsSync(path.join(root,'assets/companions')),'Pet redesign assets are excluded');
assert(!html.includes('pet-grid')&&!html.includes('assets/companions')&&!js.includes('const pets ='),'No rejected pet gallery or rig claims');
assert(html.includes('SAMPLE')&&html.includes('not a remaining subscription quota'));
assert(html.includes('Coming soon')&&html.includes('Not yet Apple-notarized'));
assert(html.includes('data-coming-soon="true"'),'Marketing CTA cannot initiate checkout');
assert(html.includes('Companion redesign is in progress'));
assert(css.includes('prefers-reduced-motion:reduce')&&css.includes('focus-visible'));
assert(css.includes('prefers-color-scheme:dark')&&css.includes('prefers-contrast:more'));
assert(fs.readFileSync(path.join(root,'recover.html'),'utf8').includes('method="post"'),'Recovery cannot fall back to email in URL');
assert(!js.includes('localStorage')&&!js.includes('sessionStorage'),'Purchase secrets never go into browser storage');
assert(js.includes("history.replaceState(null,'',location.pathname+location.search)"),'Recovery fragment removed');
assert(js.includes("url.hostname!=='checkout.stripe.com'"),'Checkout destination allowlist');
assert(js.includes("api('/api/purchase')"),'Purchase status server verified');
const product=JSON.parse(fs.readFileSync(path.join(root,'product.json'),'utf8'));
assert.deepEqual(product,{...PRODUCT,available:false},'Static product policy generated from central config, disabled by default');
const headers=fs.readFileSync(path.join(root,'_headers'),'utf8');
assert(headers.includes("frame-ancestors 'none'")&&headers.includes('Referrer-Policy: no-referrer'));
assert(headers.includes('/purchase.html\n  Cache-Control: no-store')&&headers.includes('/recover.html\n  Cache-Control: no-store'));
if(process.argv.includes('--release')){
 const downloads=path.join(root,'downloads');
 assert(!fs.existsSync(downloads),'No app binaries in static deployment');
}
console.log('PASS: all public pages/assets, pet redesign exclusion, shared product configuration, payment safety guards, accessibility CSS, and protected-release policy.');

const config=JSON.parse(fs.readFileSync(path.resolve(root,'../wrangler.jsonc'),'utf8'));
assert.equal(config.name,'wavedock-preview');
assert(!config.main&&!config.routes&&!config.d1_databases&&!config.r2_buckets,'Existing static Worker only, no paid service bindings');

new vm.Script(fs.readFileSync(path.join(root,"home.js"),"utf8"));
const homeCSS=fs.readFileSync(path.join(root,"home.css"),"utf8");
assert(homeCSS.includes("prefers-reduced-motion:reduce")&&homeCSS.includes("focus-visible")&&homeCSS.includes("min-height:44px"));
for(const id of ["intelligence","widgets","workspace","personalize","download"])assert(html.includes(`id="${id}"`));
assert(html.includes("Find your <em>flow.</em>")&&!html.includes("Get the free preview"));
