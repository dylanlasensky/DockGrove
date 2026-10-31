import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {PRODUCT} from '../../backend/product.mjs';
// Safe static preview fallback for /product.json. Availability always comes from the live backend.
const target=fileURLToPath(new URL('../public/product.json',import.meta.url));
fs.mkdirSync(fileURLToPath(new URL('../public/',import.meta.url)),{recursive:true});
fs.writeFileSync(target,JSON.stringify({...PRODUCT,available:false},null,2)+'\n');
console.log('Prepared public product policy; checkout stays disabled without backend configuration.');
