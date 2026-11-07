// Run `npm run build` first; these checks read the generated home page only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';

const web=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const html=fs.readFileSync(path.join(web,'out/index.html'),'utf8');

test('static home does not guess the visitor appearance',()=>{
 assert(!html.includes('right now'),'light or dark is only named after mount');
 assert(/class="[^"]*autoLight[^"]*"/.test(html),'Automatic Dock is left to prefers-color-scheme');
});

test('static home names its groups and has no slideshow left',()=>{
 assert(/role="group" aria-label="Interactive Dock illustration with sample data"/.test(html));
 assert(/role="group" aria-label="Widget previews with sample data"/.test(html));
 assert(!html.includes('aria-roledescription="slideshow"'));
 assert(!/aria-live="[^"]*"[^>]*class="[^"]*petCaption/.test(html)&&!/class="[^"]*petCaption[^"]*"[^>]*aria-live/.test(html),'live region is not on the keyed caption');
});
