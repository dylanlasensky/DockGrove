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

test('loadProduct(): falls back to the static /product.json, then fails',async()=>{
 const a=mockFetch({'/product.json':{body:product()}});
 assert.equal((await commerce.loadProduct(a.fetch)).amount,999);
 assert.deepEqual(a.calls.map(c=>c[0]),['/api/product','/product.json']);
 await assert.rejects(commerce.loadProduct(mockFetch().fetch));
 assert.equal(commerce.formatPrice(product()),'$9.99');
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
