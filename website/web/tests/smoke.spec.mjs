// WebKit smoke test of the static export in website/web/out. Run with `npm run test:smoke`
// after `npm run build`. The name is deliberately not *.test.mjs: `npm test` needs no browser.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import {after,before,test} from 'node:test';
import {fileURLToPath} from 'node:url';
import {webkit} from 'playwright';

const out=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','out');
const routes=['/','/privacy','/terms','/purchase','/recover'];
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript','.css':'text/css','.json':'application/json','.txt':'text/plain; charset=utf-8','.png':'image/png','.jpg':'image/jpeg','.webp':'image/webp','.avif':'image/avif','.svg':'image/svg+xml','.ico':'image/x-icon','.woff2':'font/woff2','.xml':'application/xml'};

assert(fs.existsSync(out),`Missing static export at ${out}; run \`npm run build\` in website/web first`);

/** The `/*` block of out/_headers, so a page that breaks the production CSP fails here too. */
function siteHeaders(){
 const lines=fs.readFileSync(path.join(out,'_headers'),'utf8').split('\n');
 const block=lines.slice(lines.indexOf('/*')+1);
 const end=block.findIndex(line=>!line.startsWith(' '));
 return Object.fromEntries(block.slice(0,end).map(line=>line.trim().split(/:\s*(.*)/s).slice(0,2)));
}

/** Clean URLs as in production: exact file, then `x.html`, then `x/index.html`. */
function resolveFile(pathname){
 const clean=decodeURIComponent(pathname).replace(/^\/+|\/+$/g,'');
 const candidates=clean?[clean,`${clean}.html`,`${clean}/index.html`]:['index.html'];
 return candidates.map(c=>path.join(out,c)).find(f=>f.startsWith(out+path.sep)&&fs.statSync(f,{throwIfNoEntry:false})?.isFile());
}

const headers=siteHeaders();
const server=http.createServer((req,res)=>{
 const file=resolveFile(new URL(req.url,'http://localhost').pathname);
 const served=file??path.join(out,'404.html');
 res.writeHead(file?200:404,{...headers,'Content-Type':types[path.extname(served)]??'application/octet-stream'});
 fs.createReadStream(served).pipe(res);
});

/**
 * Runs in the page: every visible text run must fit the viewport and any box that clips it.
 * aria-hidden subtrees are skipped: the feature cards crop a decorative dock on purpose.
 */
function findTextOverflow(){
 const width=document.documentElement.clientWidth;
 const found=[];
 if(document.documentElement.scrollWidth>width)found.push(`page is ${document.documentElement.scrollWidth}px wide at ${width}px`);
 const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
 for(let node=walker.nextNode();node;node=walker.nextNode()){
  const text=node.textContent.trim();
  const element=node.parentElement;
  if(!text||['SCRIPT','STYLE'].includes(element.tagName)||element.closest('[aria-hidden="true"]')||!element.checkVisibility({visibilityProperty:true}))continue;
  let left=0,right=width,exempt=false;
  for(let box=element;box&&!exempt;box=box.parentElement){
   const overflow=getComputedStyle(box).overflowX;
   if(overflow==='auto'||overflow==='scroll')exempt=true; // A scroller shows the rest on demand.
   if(overflow==='hidden'||overflow==='clip'){
    const rect=box.getBoundingClientRect();
    if(rect.width<=1)exempt=true; // Screen-reader-only text.
    left=Math.max(left,rect.left);
    right=Math.min(right,rect.right);
   }
  }
  if(exempt)continue;
  const range=document.createRange();
  range.selectNodeContents(node);
  for(const rect of range.getClientRects()){
   if(rect.width>0&&(rect.left<left-1||rect.right>right+1)){
    found.push(`<${element.tagName.toLowerCase()}> "${text.slice(0,50)}" spans ${Math.round(rect.left)}-${Math.round(rect.right)}, allowed ${Math.round(left)}-${Math.round(right)}`);
    break;
   }
  }
 }
 return found;
}

/** Runs in the page: scrolls to the bottom in screens so lazy images and reveals load. */
async function scrollThrough(){
 for(let y=0;y<document.documentElement.scrollHeight;y+=innerHeight){
  scrollTo(0,y);
  await new Promise(resolve=>setTimeout(resolve,30));
 }
 scrollTo(0,0);
}

let browser,origin;

before(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 origin=`http://127.0.0.1:${server.address().port}`;
 browser=await webkit.launch();
});

after(async()=>{
 await browser?.close();
 server.closeAllConnections();
 await new Promise(resolve=>server.close(resolve));
});

for(const route of routes){
 test(`WebKit ${route}: clean console and network, no overflow at 390px`,async()=>{
  const context=await browser.newContext({viewport:{width:390,height:844},reducedMotion:'reduce'});
  const report={consoleErrors:[],failedRequests:[],crossOrigin:[],overflow:[]};
  const sameOrigin=url=>new URL(url).origin===origin;
  await context.route(url=>/^https?:$/.test(url.protocol)&&url.origin!==origin,request=>request.abort()); // Never leave the machine.
  const page=await context.newPage();
  page.on('console',message=>{if(message.type()==='error')report.consoleErrors.push(`${message.text()} (${message.location().url})`);});
  page.on('pageerror',error=>report.consoleErrors.push(`Uncaught ${error.message}`));
  page.on('request',request=>{if(/^https?:/.test(request.url())&&!sameOrigin(request.url()))report.crossOrigin.push(request.url());});
  page.on('requestfailed',request=>{if(sameOrigin(request.url()))report.failedRequests.push(`${request.url()}: ${request.failure()?.errorText}`);});
  page.on('response',response=>{if(sameOrigin(response.url())&&response.status()>=400)report.failedRequests.push(`${response.url()}: ${response.status()}`);});

  const response=await page.goto(origin+route,{waitUntil:'load'});
  assert.equal(response.status(),200,`${route} status`);
  await page.evaluate(scrollThrough);
  await page.waitForLoadState('networkidle');
  await page.evaluate(()=>document.fonts.ready.then(()=>undefined));
  report.overflow=await page.evaluate(findTextOverflow);
  await context.close();

  const local=value=>value.replaceAll(origin,'');
  assert.deepEqual({...report,consoleErrors:report.consoleErrors.map(local),failedRequests:report.failedRequests.map(local)},{consoleErrors:[],failedRequests:[],crossOrigin:[],overflow:[]});
 });
}

/** The notch section at `viewport`, scrolled into view, with its state read from the Closed button. */
async function openNotchSection(viewport,options={}){
 const context=await browser.newContext({viewport,reducedMotion:'reduce',...options});
 await context.route(url=>/^https?:$/.test(url.protocol)&&url.origin!==origin,request=>request.abort());
 const page=await context.newPage();
 await page.goto(origin+'/',{waitUntil:'load'});
 const button=name=>page.locator('#notch').getByRole('button',{name,exact:true});
 await button('Home').scrollIntoViewIfNeeded();
 await page.locator('#notch-desktop-preview').scrollIntoViewIfNeeded();
 const shelfOpen=()=>page.locator('#notch [class*="shelfHeader"]').count().then(Boolean);
 const until=async expected=>{for(let i=0;i<60&&await shelfOpen()!==expected;i++)await page.waitForTimeout(50);assert.equal(await shelfOpen(),expected,`shelf open is ${expected}`);};
 const box=await page.locator('#notch [class*="cameraHousing"]').boundingBox();
 const point={x:box.x+box.width/2,y:box.y+box.height/2};
 const desktop=await page.locator('#notch-desktop-preview').boundingBox();
 const away={x:desktop.x+desktop.width/2,y:desktop.y+desktop.height*0.75};
 return {context,page,button,shelfOpen,until,point,away};
}

test('WebKit notch preview: hover opens and closes, a click keeps it open',async()=>{
 const {context,page,button,shelfOpen,until,point,away}=await openNotchSection({width:1280,height:800});
 const {mouse}=page;

 // A shelf opened by a button ignores the pointer leaving.
 assert.equal(await shelfOpen(),true,'starts open on Home');
 await mouse.move(point.x,point.y);
 await mouse.move(away.x,away.y);
 await page.waitForTimeout(900);
 assert.equal(await shelfOpen(),true,'button-opened shelf stays open');

 // Hover opens after a pause and closes after the grace period; the shelf itself counts as inside.
 await button('Closed').click();
 assert.equal(await shelfOpen(),false);
 await mouse.move(point.x,point.y);
 await until(true);
 await mouse.move(point.x,point.y+(await page.locator('#notch [class*="shelfHeader"]').boundingBox()).height);
 await page.waitForTimeout(900);
 assert.equal(await shelfOpen(),true,'pointer inside the shelf keeps it open');
 await mouse.move(away.x,away.y);
 await until(false);

 // Esc closes a hover-opened shelf, and hover cannot reopen it until the pointer leaves and returns.
 await mouse.move(point.x,point.y);
 await until(true);
 await page.keyboard.press('Escape');
 assert.equal(await shelfOpen(),false);
 await page.waitForTimeout(400);
 assert.equal(await shelfOpen(),false,'no reopen while the pointer rests on the notch');
 await mouse.move(away.x,away.y);

 // As in the app, clicking the housing of an open shelf closes it, even one hover opened.
 await mouse.move(point.x,point.y);
 await until(true);
 await mouse.click(point.x,point.y);
 assert.equal(await shelfOpen(),false,'click closes a hover-opened shelf');

 // Clicking the resting notch keeps it open past the grace period, until something closes it.
 await mouse.click(point.x,point.y);
 assert.equal(await shelfOpen(),true,'click opens');
 await mouse.move(away.x,away.y);
 await page.waitForTimeout(900);
 assert.equal(await shelfOpen(),true,'clicked-open shelf stays open');
 await mouse.click(away.x,away.y);
 assert.equal(await shelfOpen(),false,'click outside closes');

 await mouse.click(point.x,point.y);
 await mouse.move(away.x,away.y);
 await page.keyboard.press('Escape');
 assert.equal(await shelfOpen(),false,'Esc closes');
 await context.close();
});

test('WebKit notch preview: the buttons work by keyboard and touch, without hover',async()=>{
 const keyboard=await openNotchSection({width:1280,height:800});
 await keyboard.button('Files').focus();
 await keyboard.page.keyboard.press('Enter');
 const zones=keyboard.page.locator('#notch [class*="dropZone"]');
 assert.deepEqual(await zones.locator('b').allTextContents(),['File tray','AirDrop']);
 const [tray,airDrop]=await zones.evaluateAll(all=>all.map(zone=>zone.getBoundingClientRect().width));
 const scale=await keyboard.page.locator('#notch [class*="shelfHeader"]').evaluate(header=>header.getBoundingClientRect().width/760);
 assert(Math.abs(tray-359*scale)<1&&Math.abs(airDrop-359*scale)<1,`half-width drop zones at ${scale}`);
 assert.match(await keyboard.page.locator('#notch-desktop-preview').getAttribute('aria-label'),/^Notch shelf preview: open on Files.*Sample data\.$/);
 await keyboard.button('Closed').focus();
 await keyboard.page.keyboard.press('Space');
 assert.equal(await keyboard.shelfOpen(),false);
 assert.match(await keyboard.page.locator('#notch-desktop-preview').getAttribute('aria-label'),/^Notch shelf preview: closed.*Sample data\.$/);
 await keyboard.context.close();

 const touch=await openNotchSection({width:390,height:844},{hasTouch:true});
 await touch.button('Closed').tap();
 assert.equal(await touch.shelfOpen(),false);
 await touch.button('Files').tap();
 assert.equal(await touch.shelfOpen(),true);
 await touch.page.waitForTimeout(900);
 assert.equal(await touch.shelfOpen(),true,'stays open without a pointer');
 const desktop=await touch.page.locator('#notch-desktop-preview').boundingBox(); // Tapping may have scrolled.
 await touch.page.touchscreen.tap(desktop.x+desktop.width/2,desktop.y+desktop.height*0.75);
 assert.equal(await touch.shelfOpen(),false,'a tap outside closes');
 await touch.context.close();
});
