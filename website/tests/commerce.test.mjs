import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import worker, { verifyWebhook, validateSession, hash } from '../backend/worker.mjs';
import { PRODUCT } from '../backend/product.mjs';
class D1 {
 constructor(){this.db=new DatabaseSync(':memory:');this.db.exec(readFileSync(new URL('../migrations/0001_commerce.sql',import.meta.url),'utf8'));}
 prepare(sql){const db=this.db;return {bind(...args){return {async first(){return db.prepare(sql).get(...args)||null;},async all(){return {results:db.prepare(sql).all(...args)};},async run(){const result=db.prepare(sql).run(...args);return {meta:{changes:result.changes}};},sql,args};}};}
 async batch(queries){this.db.exec('BEGIN');try{const out=queries.map(q=>this.db.prepare(q.sql).run(...q.args));this.db.exec('COMMIT');return out;}catch(e){this.db.exec('ROLLBACK');throw e;}}
}
const encoded = s => new TextEncoder().encode(s);
const base64 = d => Buffer.from(d).toString('base64url');
async function signature(body,secret,stamp=Math.floor(Date.now()/1000)) {
 const key=await crypto.subtle.importKey('raw',encoded(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return `t=${stamp},v1=${Buffer.from(await crypto.subtle.sign('HMAC',key,encoded(`${stamp}.${body}`))).toString('hex')}`;
}
function validSession(id='cs_test_1',purchase='p1') {return {id,client_reference_id:purchase,livemode:false,mode:'payment',currency:'usd',amount_total:999,amount_subtotal:999,payment_status:'paid',status:'complete',customer_details:{email:'buyer@example.test'},payment_intent:{id:`pi_${id}`,latest_charge:{refunded:false,amount_refunded:0,disputed:false}},line_items:{has_more:false,data:[{quantity:1,price:{id:'price_test',product:'prod_test',unit_amount:999,currency:'usd',livemode:false}}]}};}
async function fixture(){
 const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const env={DB:new D1(),SALES_MODE:'test',PUBLIC_ORIGIN:'https://test.example',STRIPE_SECRET_KEY:'sk_test_fixture',STRIPE_PRICE_ID:'price_test',STRIPE_PRODUCT_ID:'prod_test',STRIPE_WEBHOOK_SECRET:'whsec_fixture',LICENSE_KEY_SECRET:'fixture-only-secret-do-not-configure-for-any-real-service',ENTITLEMENT_PRIVATE_JWK:JSON.stringify(await crypto.subtle.exportKey('jwk',pair.privateKey)),ENTITLEMENT_KEY_ID:'test-1',RESEND_API_KEY:'fixture-email',RECOVERY_FROM:'test@example.test',RELEASES:{async head(){return {size:3};},async get(){return {body:new Uint8Array([1,2,3])};}},RELEASE_OBJECT:'test.zip',ASSETS:{fetch(){return new Response('asset');}}};
 const sessions=new Map();let emailText='',checkoutCount=0,emailFailure=false;
 globalThis.fetch=async(url,options)=>{
  if(url==='https://api.resend.com/emails'){emailText=JSON.parse(options.body).text;return Response.json({id:'email'},{status:emailFailure?503:200});}
  if(url==='https://api.stripe.com/v1/prices/price_test')return Response.json({active:true,id:'price_test',product:'prod_test',unit_amount:999,currency:'usd',livemode:false});
  if(url==='https://api.stripe.com/v1/checkout/sessions') {assert.ok(options.headers.Authorization.startsWith('Bearer sk_test_'));const params=new URLSearchParams(options.body);const id=`cs_test_${++checkoutCount}`;const s=validSession(id,params.get('client_reference_id'));s.payment_status='unpaid';s.status='open';sessions.set(id,s);return Response.json({...s,url:'https://checkout.stripe.com/c/pay/cs_test_fixture'});}
  const id=url.match(/checkout\/sessions\/([^?]+)/)?.[1];if(id&&sessions.has(id))return Response.json(sessions.get(id));
  if(url.includes('/v1/charges/')){const latest=[...sessions.values()].at(-1);return Response.json({...latest.payment_intent.latest_charge,payment_intent:latest.payment_intent.id});}
  throw new Error(`Unexpected mock request ${url}`);
 };
 const call=async(path,body,headers={})=>worker.fetch(new Request(`https://test.example${path}`,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json','CF-Connecting-IP':crypto.randomUUID(),...headers},body:body===undefined?undefined:JSON.stringify(body)}),env);
 const event=async(type,s,extra={})=>{const e={id:`evt_${crypto.randomUUID()}`,type,livemode:false,data:{object:s},...extra};const body=JSON.stringify(e);const req=new Request('https://test.example/api/stripe/webhook',{method:'POST',headers:{'Stripe-Signature':await signature(body,env.STRIPE_WEBHOOK_SECRET)},body});return worker.fetch(req,env);};
 const buy=async()=>{const r=await call('/api/checkout',{});assert.equal(r.status,200);const cookie=r.headers.get('Set-Cookie').split(';')[0];const s=[...sessions.values()].at(-1);s.payment_status='paid';s.status='complete';assert.equal((await event('checkout.session.completed',s)).status,200);const p=await call('/api/purchase',undefined,{Cookie:cookie});return {licenseKey:(await p.json()).licenseKey,s,cookie};};
 return {env,pair,call,event,buy,sessions,email:()=>emailText,failEmail:()=>{emailFailure=true;},restoreEmail:()=>{emailFailure=false;}};
}
test('webhook rejects missing, forged, stale, and future signatures; supports rotation',async()=>{
 const body='{"event":true}',secret='fixture';
 await assert.rejects(verifyWebhook(body,null,secret));await assert.rejects(verifyWebhook(body,'t=1,v1='+'0'.repeat(64),secret));
 for(const stamp of [Math.floor(Date.now()/1000)-301,Math.floor(Date.now()/1000)+301])await assert.rejects(verifyWebhook(body,await signature(body,secret,stamp),secret));
 const good=await signature(body,secret);await verifyWebhook(body,good+',v1='+'0'.repeat(64),secret);
 await assert.rejects(verifyWebhook(body+' ',good,secret));
});
test('strict product, amount, environment, price and quantity validation',()=>{
 const env={STRIPE_PRICE_ID:'price_test',STRIPE_PRODUCT_ID:'prod_test'};
 validateSession(validSession(),env);
 for(const [key,value] of [['livemode',true],['mode','subscription'],['currency','eur'],['amount_total',1],['amount_subtotal',1000]]){const s=validSession();s[key]=value;assert.throws(()=>validateSession(s,env));}
 for(const key of ['id','product','unit_amount','currency','livemode','recurring']){const s=validSession();s.line_items.data[0].price[key]=key==='recurring'?{interval:'month'}:'wrong';assert.throws(()=>validateSession(s,env));}
 const s=validSession();s.line_items.data[0].quantity=2;assert.throws(()=>validateSession(s,env));
});
test('complete purchase, activation cap, verified entitlement, deactivation and one-time recovery',async()=>{
 const f=await fixture(), {licenseKey,s,cookie}=await f.buy();assert.match(licenseKey,/^WD1-[\w-]{43}$/);
 assert.equal((await f.call('/api/purchase')).status,401);
 assert.equal((await f.call('/api/checkout',{}, {Origin:'https://evil.test'})).status,403);
 assert.equal((await f.event('checkout.session.completed',s,{id:'evt_duplicate'})).status,200);
 assert.equal((await f.event('checkout.session.completed',s,{id:'evt_duplicate'})).status,200);
 assert.equal(f.env.DB.db.prepare('SELECT COUNT(*) n FROM licenses').get().n,1);
 const devices=Array.from({length:4},()=>crypto.randomUUID());
 const replies=await Promise.all(devices.map(deviceId=>f.call('/api/activate',{licenseKey,deviceId})));
 assert.deepEqual(replies.map(x=>x.status).sort(),[200,200,200,409]);
 const signed=(await replies[0].json()).entitlement;
 assert.equal(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},f.pair.publicKey,Buffer.from(signed.signature,'base64url'),encoded(signed.payload)),true);
 const claims=JSON.parse(Buffer.from(signed.payload,'base64url'));assert.equal(claims.deviceHash,await hash(devices[0]));assert.equal(claims.exp-claims.iat,30*86400);assert.equal(claims.environment,'test');
 assert.equal((await f.call('/api/refresh',{licenseKey,deviceId:devices[0]})).status,200);
 assert.equal((await f.call('/api/deactivate',{licenseKey,deviceId:devices[0]})).status,200);
 assert.equal((await f.call('/api/refresh',{licenseKey,deviceId:devices[0]})).status,409);
 assert.equal((await f.call('/api/activate',{licenseKey,deviceId:devices[3]})).status,200);
 assert.equal((await f.call('/api/activate',{licenseKey,deviceId:devices[0]})).status,409);
 assert.equal((await f.call('/api/recover',{email:'buyer@example.test'})).status,200);
 const token=f.email().match(/#token=([\w-]+)/)[1];
 const recovered=await f.call('/api/recover/complete',{token});assert.equal((await recovered.json()).licenseKey,licenseKey);
 assert.equal((await f.call('/api/recover/complete',{token})).status,401);
 const unknown=await f.call('/api/recover',{email:'unknown@example.test'});assert.equal((await unknown.json()).accepted,true);
 assert.equal((await f.call('/api/download',{licenseKey})).status,200);
 assert.equal((await f.call('/downloads/DockGrove.zip')).status,403);
 assert.equal((await f.call('/api/download',{licenseKey:'invented'})).status,401);
 assert.equal((await f.call('/api/purchase',undefined,{Cookie:cookie})).status,200);
});
test('refund before fulfillment blocks issuance; refund after fulfillment revokes and retries cannot reactivate',async()=>{
 const f=await fixture();const checkout=await f.call('/api/checkout',{});assert.equal(checkout.status,200);const s=[...f.sessions.values()][0];
 assert.equal((await f.event('charge.refunded',{payment_intent:s.payment_intent.id,amount_refunded:999})).status,200);
 s.payment_status='paid';assert.equal((await f.event('checkout.session.completed',s)).status,200);
 assert.equal(f.env.DB.db.prepare('SELECT COUNT(*) n FROM licenses').get().n,0);
 const {licenseKey,s:paid}=await f.buy();const deviceId=crypto.randomUUID();assert.equal((await f.call('/api/activate',{licenseKey,deviceId})).status,200);
 assert.equal((await f.event('charge.refunded',{payment_intent:paid.payment_intent.id,amount_refunded:999})).status,200);
 await f.event('checkout.session.completed',paid);
 assert.equal((await f.call('/api/refresh',{licenseKey,deviceId})).status,403);
 assert.equal((await f.call('/api/download',{licenseKey})).status,403);
});
test('unconfigured and live-key configurations fail closed; rate limits and expiry',async()=>{
 const f=await fixture();f.env.STRIPE_SECRET_KEY='sk_live_forbidden';assert.equal((await f.call('/api/product')).status,200);assert.equal((await (await f.call('/api/product')).json()).available,false);assert.equal((await f.call('/api/checkout',{})).status,503);
 f.env.STRIPE_SECRET_KEY='sk_test_fixture';
 for(let i=0;i<3;i++)assert.equal((await f.call('/api/recover',{email:'nobody@example.test'},{'CF-Connecting-IP':'fixed'})).status,200);
 assert.equal((await f.call('/api/recover',{email:'nobody@example.test'},{'CF-Connecting-IP':'fixed'})).status,429);
 const r=await f.call('/api/checkout',{}),cookie=r.headers.get('Set-Cookie').split(';')[0];const s=[...f.sessions.values()].at(-1);s.status='expired';await f.event('checkout.session.expired',s);
 assert.equal((await (await f.call('/api/purchase',undefined,{Cookie:cookie})).json()).status,'expired');
});

test('delivery failure returns generic acceptance and encrypted outbox retries safely',async()=>{
 const f=await fixture();await f.buy();f.failEmail();
 const result=await f.call('/api/recover',{email:'buyer@example.test'});assert.equal(result.status,200);const known=await result.json();
 assert.deepEqual(known,await (await f.call('/api/recover',{email:'unknown@example.test'})).json());
 const row=f.env.DB.db.prepare('SELECT * FROM email_outbox').get();assert.equal(row.sent,0);assert.ok(!row.ciphertext.includes('buyer@example.test'));assert.ok(!row.ciphertext.includes('#token='));
 f.restoreEmail();await worker.scheduled({},f.env);assert.equal(f.env.DB.db.prepare('SELECT COUNT(*) n FROM email_outbox').get().n,0);
 const token=f.email().match(/#token=([\w-]+)/)[1];assert.equal((await f.call('/api/recover/complete',{token})).status,200);
});

test('dispute closes stay suspended for owner review; delayed expiry does not downgrade paid session',async()=>{
 const f=await fixture(),p=await f.buy(),deviceId=crypto.randomUUID();
 assert.equal((await f.event('checkout.session.expired',p.s)).status,200);
 assert.equal((await (await f.call('/api/purchase',undefined,{Cookie:p.cookie})).json()).status,'paid');
 assert.equal((await f.event('charge.dispute.created',{charge:'ch_test'})).status,200);
 assert.equal((await f.call('/api/activate',{licenseKey:p.licenseKey,deviceId})).status,403);
 assert.equal((await f.event('charge.dispute.closed',{charge:'ch_test',status:'won'})).status,200);
 await f.event('checkout.session.completed',p.s);
 assert.equal((await f.call('/api/activate',{licenseKey:p.licenseKey,deviceId})).status,403);
 assert.equal((await f.event('checkout.session.completed',p.s,{livemode:true})).status,400);
});
test('failed unpaid checkout never grants license',async()=>{
 const f=await fixture(),checkout=await f.call('/api/checkout',{}),s=[...f.sessions.values()][0];
 const cookie=checkout.headers.get('Set-Cookie').split(';')[0];
 assert.equal((await f.event('checkout.session.async_payment_failed',s)).status,200);
 const status=await (await f.call('/api/purchase',undefined,{Cookie:cookie})).json();
 assert.equal(status.status,'failed');assert.equal(status.licenseKey,undefined);
 assert.equal(f.env.DB.db.prepare('SELECT COUNT(*) n FROM licenses').get().n,0);
});

test('checkout readiness rejects malformed signing material and missing download before creating session',async()=>{
 const f=await fixture(),key=f.env.ENTITLEMENT_PRIVATE_JWK;
 f.env.ENTITLEMENT_PRIVATE_JWK='{}';assert.equal((await (await f.call('/api/product')).json()).available,false);assert.equal((await f.call('/api/checkout',{})).status,503);assert.equal(f.sessions.size,0);
 f.env.ENTITLEMENT_PRIVATE_JWK=key;f.env.RELEASES.head=async()=>null;
 assert.equal((await (await f.call('/api/product')).json()).available,false);assert.equal((await f.call('/api/checkout',{})).status,503);assert.equal(f.sessions.size,0);
});
test('recovery address rate limit survives IP rotation',async()=>{
 const f=await fixture();for(let i=0;i<3;i++)assert.equal((await f.call('/api/recover',{email:'target@example.test'})).status,200);
 assert.equal((await f.call('/api/recover',{email:'target@example.test'})).status,429);
});

test('outstanding purchase retains original offer when configured price changes',async()=>{
 const f=await fixture(),checkout=await f.call('/api/checkout',{}),s=[...f.sessions.values()][0];s.payment_status='paid';s.status='complete';
 f.env.STRIPE_PRICE_ID='price_new';f.env.STRIPE_PRODUCT_ID='prod_new';
 assert.equal((await f.event('checkout.session.completed',s)).status,200);
 const cookie=checkout.headers.get('Set-Cookie').split(';')[0];
 const result=await (await f.call('/api/purchase',undefined,{Cookie:cookie})).json();assert.equal(result.status,'paid');assert.match(result.licenseKey,/^WD1-/);
});
