// Byte budgets over the Next.js static export in website/web/out.
// Run `npm run build` first; these checks measure the generated files only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';

const KB=1000;
const MB=1000*KB;
const ASSETS_LIMIT=2*MB;
const IMAGE_LIMIT=200*KB;
// 692 KB when set, plus about 10%. Raising it should be a deliberate choice, not a reflex.
const JS_LIMIT=760*KB;

const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','out');
assert(fs.existsSync(out),`Missing static export at ${out}; run \`npm run build\` in website/web first`);

function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(d=>d.isDirectory()?walk(path.join(dir,d.name)):[path.join(dir,d.name)]);}
const sized=dir=>walk(dir).map(file=>({file:path.relative(out,file),bytes:fs.statSync(file).size}));
const total=files=>files.reduce((sum,f)=>sum+f.bytes,0);
const largest=files=>[...files].sort((a,b)=>b.bytes-a.bytes).slice(0,5).map(f=>`${f.file} ${f.bytes}`).join(', ');

const files=sized(out);

test(`out/assets totals at most ${ASSETS_LIMIT} bytes`,()=>{
 const assets=sized(path.join(out,'assets'));
 assert(assets.length>0,'out/assets is empty');
 assert(total(assets)<=ASSETS_LIMIT,`out/assets is ${total(assets)} bytes; largest: ${largest(assets)}`);
});

test(`no image in out/ is over ${IMAGE_LIMIT} bytes`,()=>{
 const images=files.filter(f=>/\.(?:png|jpe?g|gif|webp|avif|svg|ico)$/i.test(f.file));
 assert(images.length>0,'no images found in out/');
 const over=images.filter(f=>f.bytes>IMAGE_LIMIT).sort((a,b)=>b.bytes-a.bytes);
 assert.deepEqual(over,[],`${over.length} of ${images.length} images are over budget`);
});

test(`JavaScript in out/ totals at most ${JS_LIMIT} bytes`,()=>{
 const scripts=files.filter(f=>f.file.endsWith('.js'));
 assert(scripts.length>0,'no JavaScript found in out/');
 assert(total(scripts)<=JS_LIMIT,`JavaScript is ${total(scripts)} bytes; largest: ${largest(scripts)}`);
});
