import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../public');
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const css=fs.readFileSync(path.join(root,'style.css'),'utf8');
const js=fs.readFileSync(path.join(root,'app.js'),'utf8');
new vm.Script(js);
const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(m=>m[1]);assert.equal(new Set(ids).size,ids.length,'Unique HTML identifiers');
for(const match of html.matchAll(/\b(?:href|src)="([^"]+)"/g)){
  const url=match[1];if(url.startsWith('#'))assert(ids.includes(url.slice(1)),`Missing anchor ${url}`);
  if(url.startsWith('/')&&!url.startsWith('/downloads/'))assert(fs.existsSync(path.join(root,url)),`Missing asset ${url}`);
  if(url.startsWith('http'))assert.equal(new URL(url).protocol,'https:');
}
for(const match of html.matchAll(/aria-controls="([^"]+)"/g))assert(ids.includes(match[1]));
assert(html.includes('SAMPLE')&&html.includes('not a remaining subscription quota'));
assert(css.includes('prefers-reduced-motion:reduce')&&css.includes('focus-visible'));
assert(!html.includes('stripe.com')&&!js.includes('fetch(')&&!js.includes('localStorage'),'No billing, tracking or remote API in demos');
assert(!fs.existsSync(path.join(root,'_worker.js')),'Static-only hosting');
const config=JSON.parse(fs.readFileSync(path.resolve(root,'../wrangler.jsonc'),'utf8'));
assert(!config.main&&!config.assets.run_worker_first&&!config.routes&&!config.d1_databases&&!config.r2_buckets,'No dynamic/paid service configuration');
assert.equal(config.assets.directory,'./public');
const headers=fs.readFileSync(path.join(root,'_headers'),'utf8');assert(headers.includes("frame-ancestors 'none'"));
if(process.argv.includes('--release')){const zip=fs.readFileSync(path.join(root,'downloads/WaveDock-0.6.0.zip'));assert(zip.length>1_000_000&&zip.length<25_000_000);assert.equal(zip.readUInt32LE(0),0x04034b50);}
console.log('PASS: site syntax, all local links/assets, unique IDs, controls, sample labels, motion/accessibility safeguards, static-only free-hosting configuration'+(process.argv.includes('--release')?', release ZIP':''));
