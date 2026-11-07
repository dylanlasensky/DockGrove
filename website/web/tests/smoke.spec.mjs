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
