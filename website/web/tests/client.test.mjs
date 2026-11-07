// Port of website/tests/client.test.mjs: the behavior of app.js, now in src/lib/commerce.ts.
// Node 24 strips TypeScript types, so the client is imported directly with a mocked fetch.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import * as commerce from '../src/lib/commerce.ts';

/** fetch stub: records every call, answers from `replies` keyed by URL. */
function mockFetch(replies={}){
 const calls=[];
 const fetch=async(url,options)=>{
  calls.push([url,options]);
  const data=replies[url];
  if(!data)return {ok:false,json:async()=>({error:'Unavailable'}),blob:async()=>new Blob()};
  return {ok:data.ok!==false,json:async()=>data.body,blob:async()=>new Blob([data.blob??''])};
 };
 return {fetch,calls};
}
const product=(over={})=>({name:'DockGrove',amount:999,currency:'usd',majorVersion:1,deviceLimit:3,mode:'test',offlineDays:30,available:false,...over});

test('api(): GET has no body or content type, POST sends JSON, cookies stay same-origin',async()=>{
 const {fetch,calls}=mockFetch({'/api/purchase':{body:{status:'pending'}},'/api/recover':{body:{accepted:true}}});
 assert.deepEqual(await commerce.api('/api/purchase',undefined,fetch),{status:'pending'});
 assert.deepEqual(calls[0],['/api/purchase',{method:'GET',headers:{},credentials:'same-origin',body:undefined}]);
 await commerce.api('/api/recover',{email:'a@b.c'},fetch);
 assert.deepEqual(calls[1],['/api/recover',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'same-origin',body:'{"email":"a@b.c"}'}]);
});

test('api(): server error message is surfaced, otherwise a generic unavailable message',async()=>{
 const {fetch}=mockFetch({'/api/checkout':{ok:false,body:{error:'Checkout is not configured.'}}});
 await assert.rejects(commerce.api('/api/checkout',{},fetch),{message:'Checkout is not configured.'});
 const broken={fetch:async()=>({ok:false,json:async()=>{throw new Error('not json');}})};
 await assert.rejects(commerce.api('/api/product',undefined,broken.fetch),{message:commerce.UNAVAILABLE_MESSAGE});
 assert.equal(commerce.errorMessage('x'),commerce.GENERIC_ERROR_MESSAGE);
 assert.equal(commerce.errorMessage(new Error('boom')),'boom');
});

test('api(): a malformed error body never reaches the visitor',async()=>{
 for(const body of [{error:{code:'x'}},{error:42},{error:''},null,'nope']){
  const {fetch}=mockFetch({'/api/checkout':{ok:false,body:{}}});
  const reply=async(...args)=>({...(await fetch(...args)),json:async()=>body});
  await assert.rejects(commerce.api('/api/checkout',{},reply),{message:commerce.UNAVAILABLE_MESSAGE});
 }
});

test('NEXT_PUBLIC_API_ENABLED: only the exact value "true" enables the API, and it defaults to off',async()=>{
 const saved=process.env.NEXT_PUBLIC_API_ENABLED;
 try{
  for(const [value,expected] of [[undefined,false],['',false],['false',false],['1',false],['TRUE',false],['true',true]]){
   if(value===undefined)delete process.env.NEXT_PUBLIC_API_ENABLED;else process.env.NEXT_PUBLIC_API_ENABLED=value;
   const fresh=await import(`../src/lib/commerce.ts?flag=${value}`);
   assert.equal(fresh.API_ENABLED,expected,`flag value ${value}`);
   const {fetch,calls}=mockFetch({'/api/product':{body:product()},'/product.json':{body:product()}});
   await fresh.loadProduct(fetch);
   assert.equal(calls[0][0],expected?'/api/product':'/product.json',`first request for flag value ${value}`);
  }
 }finally{
  if(saved===undefined)delete process.env.NEXT_PUBLIC_API_ENABLED;else process.env.NEXT_PUBLIC_API_ENABLED=saved;
 }
});

test('loadProduct() with the flag off reads /product.json and never probes the API',async()=>{
 const a=mockFetch({'/api/product':{body:product({available:true})},'/product.json':{body:product()}});
 assert.equal((await commerce.loadProduct(a.fetch,false)).available,false);
 assert.deepEqual(a.calls.map(c=>c[0]),['/product.json']);
 const missing=mockFetch();
 await assert.rejects(commerce.loadProduct(missing.fetch,false));
 assert.deepEqual(missing.calls.map(c=>c[0]),['/product.json'],'no API attempt even when the file fails');
 assert.equal(commerce.formatPrice(product()),'$9.99');
});

test('loadProduct() with the flag on is API-first: the API decides, /product.json is the fallback, then fails',async()=>{
 const live=mockFetch({'/api/product':{body:product({available:true})},'/product.json':{body:product()}});
 assert.equal((await commerce.loadProduct(live.fetch,true)).available,true);
 assert.deepEqual(live.calls.map(c=>c[0]),['/api/product']);
 const a=mockFetch({'/product.json':{body:product()}});
 assert.equal((await commerce.loadProduct(a.fetch,true)).amount,999);
 assert.deepEqual(a.calls.map(c=>c[0]),['/api/product','/product.json']);
 await assert.rejects(commerce.loadProduct(mockFetch().fetch,true));
});

test('with the flag off, other API calls still go out and fail politely',async()=>{
 await assert.rejects(commerce.requestRecovery('you@example.com',mockFetch().fetch),{message:'Unavailable'});
 const notFound={fetch:async()=>({ok:false,json:async()=>{throw new Error('html 404');}})};
 await assert.rejects(commerce.requestRecovery('you@example.com',notFound.fetch),{message:commerce.UNAVAILABLE_MESSAGE});
 await assert.rejects(commerce.completeRecovery('t',notFound.fetch),{message:commerce.UNAVAILABLE_MESSAGE});
 await assert.rejects(commerce.startCheckout(notFound.fetch),{message:commerce.UNAVAILABLE_MESSAGE});
 await assert.rejects(commerce.getPurchase(notFound.fetch),{message:commerce.UNAVAILABLE_MESSAGE});
});

test('unavailable product disables checkout with the "not enabled" notice',()=>{
 const s=commerce.checkoutButtonState(product({available:false}));
 assert.equal(s.disabled,true);assert.match(s.status,/not enabled/);
});

test('candidate never enables live checkout',()=>{
 assert.equal(commerce.checkoutButtonState(product({mode:'live',available:true})).disabled,true);
 const s=commerce.checkoutButtonState(product({mode:'test',available:true}));
 assert.equal(s.disabled,false);assert.equal(s.label,'Try test checkout');assert.match(s.status,/No real payment/);
});

test('coming-soon marketing gate wins over an available product',()=>{
 const s=commerce.checkoutButtonState(product({available:true}),true);
 assert.equal(s.disabled,true);assert.equal(s.label,'Coming soon');
});

test('checkout redirect destination is allowlisted to https://checkout.stripe.com',async()=>{
 const evil=mockFetch({'/api/checkout':{body:{url:'https://checkout.stripe.com.evil.example/steal'}}});
 await assert.rejects(commerce.startCheckout(evil.fetch),{message:commerce.CHECKOUT_DESTINATION_ERROR});
 assert.throws(()=>commerce.checkoutDestination('http://checkout.stripe.com/c/pay/x'),/unexpected destination/);
 const good=mockFetch({'/api/checkout':{body:{url:'https://checkout.stripe.com/c/pay/test_fixture'}}});
 assert.equal(await commerce.startCheckout(good.fetch),'https://checkout.stripe.com/c/pay/test_fixture');
 assert.deepEqual(good.calls[0],['/api/checkout',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'same-origin',body:'{}'}]);
});

test('success URL cannot create a license; only a paid server record does',async()=>{
 assert.equal(commerce.returnMode('?status=success&paid=true'),'verify');
 const failed=mockFetch({'/api/purchase':{body:{status:'failed'}}});
 const r=await commerce.getPurchase(failed.fetch);
 assert.equal(r.licenseKey,undefined);assert.match(commerce.purchaseStatusMessage(r.status),/failed/);
 assert.throws(()=>commerce.assertLicense(undefined),{message:commerce.NO_LICENSE_ERROR});
 const paid=mockFetch({'/api/purchase':{body:{status:'paid',licenseKey:'fixture-license'}}});
 assert.equal(commerce.assertLicense((await commerce.getPurchase(paid.fetch)).licenseKey),'fixture-license');
 assert.equal(commerce.purchaseStatusMessage('mystery'),commerce.PURCHASE_STATUS_UNKNOWN);
 assert.equal(commerce.PURCHASE_POLL_ATTEMPTS,8);
});

test('default purchase offer makes no API call and is shown without a status query',()=>{
 assert.equal(commerce.returnMode(''),'offer');
 assert.equal(commerce.returnMode('?status=cancelled'),'cancelled');
 assert.match(commerce.PURCHASE_DEFAULT_MESSAGE,/Choose test checkout/);
});

test('recovery token is read from the fragment and completed server-side',async()=>{
 assert.equal(commerce.recoveryToken('#token=one-time-test'),'one-time-test');
 assert.equal(commerce.recoveryToken(''),null);
 assert.equal(commerce.recoveryToken('#other=1'),null);
 const {fetch,calls}=mockFetch({'/api/recover/complete':{body:{licenseKey:'recovered-fixture'}}});
 assert.equal((await commerce.completeRecovery('one-time-test',fetch)).licenseKey,'recovered-fixture');
 assert.deepEqual(calls[0],['/api/recover/complete',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'same-origin',body:'{"token":"one-time-test"}'}]);
});

test('recovery request trims the email and posts it',async()=>{
 const {fetch,calls}=mockFetch({'/api/recover':{body:{accepted:true}}});
 await commerce.requestRecovery('  you@example.com ',fetch);
 assert.equal(calls[0][1].body,'{"email":"you@example.com"}');
});

test('download posts the license and reports unavailability without losing it',async()=>{
 const ok=mockFetch({'/api/download':{body:{},blob:'zip'}});
 const blob=await commerce.downloadApp('fixture-license',ok.fetch);
 assert.equal(await blob.text(),'zip');
 assert.deepEqual(ok.calls[0],['/api/download',{method:'POST',headers:{'Content-Type':'application/json'},credentials:'same-origin',body:'{"licenseKey":"fixture-license"}'}]);
 await assert.rejects(commerce.downloadApp('fixture-license',mockFetch().fetch),{message:'Unavailable'});
 const silent={fetch:async()=>({ok:false,json:async()=>{throw new Error('no body');}})};
 await assert.rejects(commerce.downloadApp('x',silent.fetch),{message:commerce.DOWNLOAD_UNAVAILABLE_MESSAGE});
});
