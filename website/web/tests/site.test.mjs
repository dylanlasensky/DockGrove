// Port of website/tests/site.test.mjs for the Next.js static export in website/web/out.
// Run `npm run build` first; these checks read the generated files only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';
import {PRODUCT} from '../../backend/product.mjs';

const web=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const out=path.join(web,'out');
const pages={'/':'index.html','/purchase':'purchase.html','/recover':'recover.html','/privacy':'privacy.html','/terms':'terms.html','/404':'404.html'};

assert(fs.existsSync(out),`Missing static export at ${out}; run \`npm run build\` in website/web first`);

/** Resolve a site URL to a file in out/, accepting both `x.html` and `x/index.html` layouts. */
function resolveLocal(url){
 const clean=url.split('#')[0].split('?')[0];
 const candidates=clean==='/'?['index.html']:[clean.slice(1),`${clean.slice(1)}.html`,`${clean.slice(1)}/index.html`];
 return candidates.map(c=>path.join(out,c)).find(f=>fs.existsSync(f)&&fs.statSync(f).isFile());
}
function read(route){const file=resolveLocal(route);assert(file,`missing page ${route}`);return fs.readFileSync(file,'utf8');}
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(d=>d.isDirectory()?walk(path.join(dir,d.name)):[path.join(dir,d.name)]);}

const html=read('/');
const purchase=read('/purchase');
const recover=read('/recover');
const files=walk(out);
const css=files.filter(f=>f.endsWith('.css')).map(f=>fs.readFileSync(f,'utf8')).join('\n');
const js=files.filter(f=>f.endsWith('.js')).map(f=>fs.readFileSync(f,'utf8')).join('\n');
const ws=s=>new RegExp(s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&').replace(/:/g,'\\s*:\\s*'));

for(const [route] of Object.entries(pages)){
 test(`page ${route}: structure, links and safety`,()=>{
  const source=read(route);
  const ids=[...source.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);
  assert.equal(new Set(ids).size,ids.length,`${route}: unique identifiers`);
  assert(source.includes('name="viewport"')&&source.includes('lang="en"'),`${route}: responsive/language metadata`);
  for(const match of source.matchAll(/<(?:a|link|img|script)\b[^>]*?\b(?:href|src)="([^"]+)"/g)){
   const url=match[1].replace(/&amp;/g,'&');
   if(url.startsWith('#'))assert(ids.includes(url.slice(1)),`${route}: missing anchor ${url}`);
   if(url.startsWith('/')){
    assert(resolveLocal(url),`${route}: missing local asset ${url}`);
    assert(!url.startsWith('/downloads/'),`${route}: no unprotected commercial download`);
   }
   if(url.startsWith('http'))assert.equal(new URL(url).protocol,'https:',`${route}: ${url}`);
  }
  for(const match of source.matchAll(/aria-controls="([^"]+)"/g))assert(ids.includes(match[1]),`${route}: aria-controls ${match[1]}`);
  assert(!source.includes('sk_test_')&&!source.includes('sk_live_')&&!source.includes('whsec_'),`${route}: no secrets`);
 });
}

test('page titles and metadata',()=>{
 assert.match(purchase,/<title>Your purchase — DockGrove<\/title>/);
 assert.match(recover,/<title>Restore purchase — DockGrove<\/title>/);
 for(const source of [html,purchase,recover])assert(source.includes('color-scheme')&&source.includes('DockGrove-icon.png'),'color-scheme meta and icon');
});

test('purchase page copy, ids and server-authority notice',()=>{
 for(const id of ['purchase-offer','checkout-button','checkout-status','purchase-status'])assert(purchase.includes(`id="${id}"`),id);
 assert(purchase.includes('Your next little upgrade.')&&purchase.includes('Checking test checkout…')&&purchase.includes('No live payments are being accepted.'));
 assert(purchase.includes('Checking server-confirmed purchase status…'),'status is server-verified, not read from the URL');
 assert(purchase.includes('not proof of payment'));
 assert(/<button[^>]*id="checkout-button"[^>]*\bdisabled\b/.test(purchase),'checkout disabled until the product policy loads');
 assert(!purchase.includes('id="license-section"'),'no license markup before server verification');
 for(const href of ['/terms','/recover','/privacy','/'])assert(purchase.includes(`href="${href}"`),`link ${href}`);
 assert(purchase.includes('https://github.com/dylanlasensky/DockGrove/issues'));
});

test('recover page posts email, never in the URL',()=>{
 assert(recover.includes('method="post"')&&recover.includes('action="/api/recover"'),'Recovery cannot fall back to email in URL');
 assert(/<input[^>]*type="email"[^>]*\brequired\b/.test(recover)||/<input[^>]*\brequired\b[^>]*type="email"/.test(recover));
 assert(/maxlength="254"/i.test(recover)&&/autocomplete="email"/i.test(recover),'email field limits and autofill');
 for(const id of ['recovery-form','recovery-email','recover-button','recovery-status'])assert(recover.includes(`id="${id}"`),id);
 assert(recover.includes('Back to your space.')&&recover.includes('expire after 15 minutes'));
});

test('home page content, approved artwork and marketing checkout gate',()=>{
 assert.equal(fs.readdirSync(path.join(out,'assets/companions')).length,9,'All nine approved pixel pets');
 assert.equal((html.match(/class="[^"]*\bpixel-pet\b[^"]*"/g)||[]).length,9,'All nine pets have visible previews');
 assert(html.includes('SAMPLE')&&html.includes('not a remaining subscription quota'));
 assert(html.includes('Coming soon')&&html.includes('Not yet Apple-notarized'));
 assert(html.includes('data-coming-soon="true"'),'Marketing CTA cannot initiate checkout');
 assert(html.includes('https://dockgrove.com/')&&html.includes('DockGrove-wordmark.png'));
 for(const id of ['intelligence','widgets','workspace','personalize','download'])assert(html.includes(`id="${id}"`),id);
 assert(/Find your(?:<!-- -->)?\s*<em[^>]*>flow\.<\/em>/.test(html)&&!html.includes('Get the free preview'));
});

test('stylesheet keeps accessibility and theming media rules',()=>{
 assert(css.length>0,'built stylesheet present');
 assert.match(css,ws('prefers-reduced-motion:reduce'));
 assert(css.includes('focus-visible'));
 assert.match(css,ws('prefers-color-scheme:dark'));
 assert.match(css,ws('prefers-contrast:more'));
 assert(css.includes('min-height:44px')||css.includes('min-height: 44px'),'44px hit targets');
});

test('client bundle keeps payment safety guards',()=>{
 assert(js.includes('checkout.stripe.com'),'Checkout destination allowlist is shipped');
 assert(js.includes('/api/purchase'),'Purchase status is server verified');
 assert(js.includes('/api/recover/complete'),'Recovery completion goes to the server');
 assert(!js.includes('sk_test_')&&!js.includes('sk_live_')&&!js.includes('whsec_'),'no secrets in bundles');
 const commerce=fs.readFileSync(path.join(web,'src/lib/commerce.ts'),'utf8');
 assert(!commerce.includes('localStorage')&&!commerce.includes('sessionStorage'),'Purchase secrets never go into browser storage');
 const recovery=fs.readFileSync(path.join(web,'src/components/commerce/RecoveryFlow.tsx'),'utf8');
 assert(recovery.includes('history.replaceState(null, "", window.location.pathname + window.location.search)'),'Recovery fragment removed');
});

test('static product policy comes from central config, disabled by default',()=>{
 const product=JSON.parse(fs.readFileSync(path.join(out,'product.json'),'utf8'));
 assert.deepEqual(product,{...PRODUCT,available:false});
});

test('security headers for the static deployment',()=>{
 const headers=fs.readFileSync(path.join(out,'_headers'),'utf8');
 assert(headers.includes("frame-ancestors 'none'")&&headers.includes('Referrer-Policy: no-referrer'));
 assert(/\/purchase(?:\.html)?\n\s+Cache-Control: no-store/.test(headers)&&/\/recover(?:\.html)?\n\s+Cache-Control: no-store/.test(headers));
});

test('no app binaries in the static export',()=>{
 assert(!fs.existsSync(path.join(out,'downloads')),'No app binaries in static deployment');
});

test('Worker config serves the export without paid bindings',()=>{
 const config=JSON.parse(fs.readFileSync(path.resolve(web,'../wrangler.jsonc'),'utf8'));
 assert.equal(config.name,'wavedock-preview');
 assert(!config.main&&!config.d1_databases&&!config.r2_buckets,'Existing static Worker only, no paid service bindings');
 assert.deepEqual(config.routes,[{pattern:'dockgrove.com',custom_domain:true},{pattern:'www.dockgrove.com',custom_domain:true}]);
});
