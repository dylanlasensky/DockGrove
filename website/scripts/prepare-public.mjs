import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {PRODUCT} from '../backend/product.mjs';
// Safe static preview fallback. Availability always comes from the live backend.
fs.writeFileSync(fileURLToPath(new URL('../public/product.json',import.meta.url)),JSON.stringify({...PRODUCT,available:false},null,2)+'\n');
console.log('Prepared public product policy; checkout stays disabled without backend configuration.');
