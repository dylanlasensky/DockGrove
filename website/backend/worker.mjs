import { PRODUCT } from './product.mjs';
const encoder = new TextEncoder();
const now = () => Math.floor(Date.now()/1000);
const b64 = data => btoa(String.fromCharCode(...new Uint8Array(data))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
const unhex = value => Uint8Array.from(value.match(/.{2}/g) || [], x => parseInt(x,16));
export const hash = async value => b64(await crypto.subtle.digest('SHA-256',encoder.encode(value)));
const random = () => b64(crypto.getRandomValues(new Uint8Array(32)));
function fail(message, status=400) { throw Object.assign(new Error(message), {status}); }
const json = (data,status=200,headers={}) => Response.json(data,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...headers}});
async function hmac(secret, text) {
 const key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return crypto.subtle.sign('HMAC',key,encoder.encode(text));
}
export async function verifyWebhook(body, header, secret, time=now()) {
 if (!secret || !header) fail('Invalid webhook signature',400);
 const parts=header.split(',').map(x=>x.split('='));
 const stamp=parts.find(x=>x[0]==='t')?.[1];
 if (!/^\d+$/.test(stamp||'') || Math.abs(time-Number(stamp))>300) fail('Invalid webhook timestamp');
 const signatures=parts.filter(x=>x[0]==='v1' && /^[a-f0-9]{64}$/i.test(x[1])).map(x=>unhex(x[1]));
 const key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['verify']);
 for (const signature of signatures) if (await crypto.subtle.verify('HMAC',key,signature,encoder.encode(`${stamp}.${body}`))) return;
 fail('Invalid webhook signature');
}
async function bodyText(request,limit=65536) {
 if(Number(request.headers.get('Content-Length'))>limit) fail('Request too large',413);
 if(!request.body) return '';
 const reader=request.body.getReader(); let size=0, chunks=[];
 while(true) {const {done,value}=await reader.read(); if(done) break; size+=value.length; if(size>limit){await reader.cancel();fail('Request too large',413);}chunks.push(value);}
 const all=new Uint8Array(size);let offset=0;for(const chunk of chunks){all.set(chunk,offset);offset+=chunk.length;}
 return new TextDecoder().decode(all);
}
async function bodyJSON(request) { try{return JSON.parse(await bodyText(request,16384));}catch(error){if(error.status)throw error;fail('Invalid JSON');} }
const stmt = (env,sql,...args) => env.DB.prepare(sql).bind(...args);
const one = (env,sql,...args) => stmt(env,sql,...args).first();
async function ready(env) {
 try {
  if(!(env.SALES_MODE==='test' && env.STRIPE_SECRET_KEY?.startsWith('sk_test_') && /^price_/.test(env.STRIPE_PRICE_ID||'') && /^prod_/.test(env.STRIPE_PRODUCT_ID||'') && env.STRIPE_WEBHOOK_SECRET?.startsWith('whsec_') && env.LICENSE_KEY_SECRET?.length>=32 && env.ENTITLEMENT_KEY_ID && env.RESEND_API_KEY && env.RECOVERY_FROM && env.DB))return false;
  const host=new URL(origin(env)).hostname;if(host.endsWith('.invalid'))return false;
  const jwk=JSON.parse(env.ENTITLEMENT_PRIVATE_JWK);if(jwk.kty!=='EC'||jwk.crv!=='P-256'||!jwk.d)return false;
  await crypto.subtle.importKey('jwk',jwk,{name:'ECDSA',namedCurve:'P-256'},false,['sign']);
  return true;
 }catch{return false;}
}
async function checkoutReady(env){
 if(!await ready(env)||!env.RELEASES||!env.RELEASE_OBJECT)return false;
 try{const object=await env.RELEASES.head(env.RELEASE_OBJECT);return !!object&&object.size>0;}catch{return false;}
}
async function requireReady(env){if(!await ready(env))fail('Test checkout is not configured yet',503);}
function origin(env){const url=new URL(env.PUBLIC_ORIGIN);if(url.protocol!=='https:' && url.hostname!=='localhost' && url.hostname!=='127.0.0.1')fail('Invalid service origin',503);return url.origin;}
async function stripe(env,path,method='GET',params) {
 const response=await fetch(`https://api.stripe.com/v1/${path}`,{method,headers:{Authorization:`Bearer ${env.STRIPE_SECRET_KEY}`,'Stripe-Version':'2025-02-24.acacia',...(params?{'Content-Type':'application/x-www-form-urlencoded'}:{}),...(params?.get('client_reference_id')?{'Idempotency-Key':`wd-checkout-${params.get('client_reference_id')}`}:{})},body:params?.toString()});
 if(!response.ok) fail('Payment service temporarily unavailable',503);
 return response.json();
}
async function limit(env,request,category,identifier='') {
 const window=Math.floor(now()/60), ip=request.headers.get('CF-Connecting-IP') || 'local';
 const bucket=await hash(`${category}:${category==='recover-email'?'address':ip}:${identifier}:${window}`);
 const row=await stmt(env,'INSERT INTO request_limits(bucket,count,expires_at) VALUES(?,1,?) ON CONFLICT(bucket) DO UPDATE SET count=count+1 RETURNING count',bucket,now()+120).first();
 if(row.count>(category.startsWith('recover')?3:30))fail('Too many requests. Try again shortly.',429);
}
async function licenseKey(env,purchaseId) {return `WD1-${b64(await hmac(env.LICENSE_KEY_SECRET,`purchase:${purchaseId}`))}`;}
async function session(env,id) { if(!/^cs_test_[A-Za-z0-9_]+$/.test(id||''))fail('Invalid test session');return stripe(env,`checkout/sessions/${id}?expand[]=line_items.data.price&expand[]=payment_intent.latest_charge`); }
export function validateSession(s,env,offer=PRODUCT) {
 const items=s.line_items?.data;
 if(s.livemode!==false || s.mode!=='payment' || s.currency!==offer.currency || s.amount_total!==offer.amount || s.amount_subtotal!==offer.amount || s.line_items?.has_more || items?.length!==1 || items[0].quantity!==1 || items[0].price?.id!==env.STRIPE_PRICE_ID || items[0].price?.product!==env.STRIPE_PRODUCT_ID || items[0].price?.unit_amount!==offer.amount || items[0].price?.currency!==offer.currency || items[0].price?.livemode!==false || items[0].price?.recurring) fail('Payment does not match the configured test product');
}
async function fulfill(env,s,event) {
 const p=await one(env,'SELECT * FROM purchases WHERE id=? AND (session_id=? OR session_id IS NULL)',s.client_reference_id,s.id);
 if(!p) fail('Unknown purchase');
 validateSession(s,{STRIPE_PRICE_ID:p.price_id,STRIPE_PRODUCT_ID:p.product_id},{amount:p.amount,currency:p.currency});
 const pi=typeof s.payment_intent==='string'?s.payment_intent:s.payment_intent?.id;
 const charge=s.payment_intent?.latest_charge;
 const blocked=pi && (await one(env,'SELECT 1 FROM payment_blocks WHERE payment_intent=?',pi));
 const revoked=blocked || charge?.refunded || charge?.amount_refunded>0 || charge?.disputed;
 const status=revoked?'revoked':s.payment_status==='paid'?'paid':s.status==='expired'?'expired':'pending';
 const email=(s.customer_details?.email||'').trim().toLowerCase();
 const queries=[stmt(env,"UPDATE purchases SET session_id=?,payment_intent=?,email=?,status=CASE WHEN status='revoked' THEN status ELSE ? END WHERE id=?",s.id,pi||null,email,status,p.id)];
 if(status==='paid' && p.status!=='revoked') queries.push(stmt(env,"INSERT INTO licenses(id,purchase_id,key_hash,status,created_at) SELECT ?,?,?,'active',? WHERE NOT EXISTS(SELECT 1 FROM payment_blocks WHERE payment_intent=?) ON CONFLICT(purchase_id) DO NOTHING",p.id,p.id,await hash(await licenseKey(env,p.id)),now(),pi||''));
 if(status==='revoked') queries.push(stmt(env,"UPDATE licenses SET status='revoked' WHERE purchase_id=?",p.id));
 if(event)queries.push(stmt(env,'INSERT OR IGNORE INTO stripe_events(id,type,processed_at) VALUES(?,?,?)',event.id,event.type,now()));
 await env.DB.batch(queries);
}
async function webhook(request,env){
 await requireReady(env);const text=await bodyText(request,1048576);await verifyWebhook(text,request.headers.get('Stripe-Signature'),env.STRIPE_WEBHOOK_SECRET);
 let e;try{e=JSON.parse(text);}catch{fail('Invalid event');}
 if(e.livemode!==false || typeof e.id!=='string' || !e.id.startsWith('evt_'))fail('Wrong event environment');
 if(await one(env,'SELECT id FROM stripe_events WHERE id=?',e.id))return json({received:true});
 const object=e.data?.object;
 if(['checkout.session.completed','checkout.session.async_payment_succeeded','checkout.session.async_payment_failed','checkout.session.expired'].includes(e.type)){
  const s=await session(env,object.id);await fulfill(env,s,e);
  if(e.type==='checkout.session.async_payment_failed' && s.payment_status!=='paid')await stmt(env,"UPDATE purchases SET status='failed' WHERE session_id=? AND status='pending'",s.id).run();
 }else if(['charge.refunded','charge.dispute.created','charge.dispute.closed'].includes(e.type)){
  let charge=object;
  if(e.type.startsWith('charge.dispute.'))charge=await stripe(env,`charges/${encodeURIComponent(typeof object.charge==='string'?object.charge:object.charge?.id)}`);
  const pi=typeof charge.payment_intent==='string'?charge.payment_intent:charge.payment_intent?.id;
  if(pi && (e.type.startsWith('charge.dispute.') || charge.refunded || charge.amount_refunded>0))await env.DB.batch([
   stmt(env,'INSERT OR IGNORE INTO payment_blocks(payment_intent,reason,created_at) VALUES(?,?,?)',pi,e.type,now()),
   stmt(env,"UPDATE purchases SET status='revoked' WHERE payment_intent=?",pi),
   stmt(env,"UPDATE licenses SET status='revoked' WHERE purchase_id IN (SELECT id FROM purchases WHERE payment_intent=?)",pi),
   stmt(env,'INSERT OR IGNORE INTO stripe_events(id,type,processed_at) VALUES(?,?,?)',e.id,e.type,now())]);
  else await stmt(env,'INSERT OR IGNORE INTO stripe_events(id,type,processed_at) VALUES(?,?,?)',e.id,e.type,now()).run();
 }else await stmt(env,'INSERT OR IGNORE INTO stripe_events(id,type,processed_at) VALUES(?,?,?)',e.id,e.type,now()).run();
 return json({received:true});
}
async function findLicense(env,key){
 if(!/^WD1-[A-Za-z0-9_-]{43}$/.test(key||''))fail('Invalid license',401);
 const l=await one(env,'SELECT l.*,p.payment_intent,p.major_version,p.device_limit FROM licenses l JOIN purchases p ON p.id=l.purchase_id WHERE l.key_hash=?',await hash(key));
 if(!l)fail('Invalid license',401);
 if(l.status!=='active'||(l.payment_intent&&await one(env,'SELECT 1 FROM payment_blocks WHERE payment_intent=?',l.payment_intent)))fail('License revoked',403);
 return l;
}
async function entitlement(env,l,deviceHash){
 const claims={iss:'wavedock',aud:'com.dylan.wavedock',licenseId:l.id,deviceHash,majorVersion:l.major_version,environment:'test',iat:now(),exp:now()+PRODUCT.offlineDays*86400};
 const payload=b64(encoder.encode(JSON.stringify(claims)));
 const key=await crypto.subtle.importKey('jwk',JSON.parse(env.ENTITLEMENT_PRIVATE_JWK),{name:'ECDSA',namedCurve:'P-256'},false,['sign']);
 const signature=b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},key,encoder.encode(payload)));
 return {payload,signature,keyId:env.ENTITLEMENT_KEY_ID||'test-1'};
}

const deb64 = value => Uint8Array.from(atob(value.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0));
async function outboxKey(env){
 const base=await crypto.subtle.importKey('raw',encoder.encode(env.LICENSE_KEY_SECRET),'HKDF',false,['deriveKey']);
 return crypto.subtle.deriveKey({name:'HKDF',hash:'SHA-256',salt:encoder.encode('wavedock-email-v1'),info:encoder.encode('recovery-outbox')},base,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
async function deliverRecovery(env,id){
 try{
  const row=await stmt(env,'UPDATE email_outbox SET attempts=attempts+1 WHERE id=? AND sent=0 AND attempts<6 AND expires_at>? RETURNING *',id,now()).first();
  if(!row)return;
  const message=await crypto.subtle.decrypt({name:'AES-GCM',iv:deb64(row.iv)},await outboxKey(env),deb64(row.ciphertext));
  const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${env.RESEND_API_KEY}`,'Content-Type':'application/json','Idempotency-Key':`recovery-${id}`},body:new TextDecoder().decode(message)});
  if(response.ok)await stmt(env,'UPDATE email_outbox SET sent=1 WHERE id=?',id).run();
 }catch{ /* Durable outbox retries; never expose delivery state in recovery response. */ }
}

async function api(request,env,path,ctx){
 if(path==='/api/product' && request.method==='GET')return json({...PRODUCT,available:await checkoutReady(env)});
 if(path==='/api/stripe/webhook' && request.method==='POST')return webhook(request,env);
 await requireReady(env);
 const requestOrigin=request.headers.get('Origin');if(requestOrigin && requestOrigin!==origin(env))fail('Origin not allowed',403);
 await limit(env,request,path==='/api/recover'?'recover':'api');
 if(path==='/api/checkout' && request.method==='POST'){
  await bodyJSON(request);
  if(!await checkoutReady(env))fail('The release download is not ready for checkout',503);
  const price=await stripe(env,`prices/${encodeURIComponent(env.STRIPE_PRICE_ID)}`);
  if(price.active!==true || price.id!==env.STRIPE_PRICE_ID || price.product!==env.STRIPE_PRODUCT_ID || price.unit_amount!==PRODUCT.amount || price.currency!==PRODUCT.currency || price.livemode!==false || price.recurring)fail('The checkout price does not match this release',503);
  const token=random(),id=crypto.randomUUID();
  await stmt(env,'INSERT INTO purchases(id,token_hash,price_id,product_id,amount,currency,major_version,device_limit,created_at) VALUES(?,?,?,?,?,?,?,?,?)',id,await hash(token),env.STRIPE_PRICE_ID,env.STRIPE_PRODUCT_ID,PRODUCT.amount,PRODUCT.currency,PRODUCT.majorVersion,PRODUCT.deviceLimit,now()).run();
  const params=new URLSearchParams({mode:'payment','line_items[0][price]':env.STRIPE_PRICE_ID,'line_items[0][quantity]':'1',client_reference_id:id,success_url:`${origin(env)}/purchase.html?status=success`,cancel_url:`${origin(env)}/purchase.html?status=cancelled`,'payment_method_types[0]':'card'});
  const s=await stripe(env,'checkout/sessions','POST',params);
  if(s.livemode!==false || !s.url?.startsWith('https://checkout.stripe.com/'))fail('Invalid checkout response',503);
  await stmt(env,'UPDATE purchases SET session_id=? WHERE id=?',s.id,id).run();
  return json({url:s.url},200,{'Set-Cookie':`wd_purchase=${token}; HttpOnly; Secure; SameSite=Strict; Path=/api; Max-Age=604800`});
 }
 if(path==='/api/purchase' && request.method==='GET'){
  const token=request.headers.get('Cookie')?.match(/(?:^|;\s*)wd_purchase=([A-Za-z0-9_-]{43})(?:;|$)/)?.[1];if(!token)fail('Purchase session unavailable. Use purchase recovery.',401);
  let p=await one(env,'SELECT * FROM purchases WHERE token_hash=?',await hash(token));if(!p)fail('Purchase unavailable',404);
  if(p.session_id && ['pending','paid'].includes(p.status)){await fulfill(env,await session(env,p.session_id));p=await one(env,'SELECT * FROM purchases WHERE id=?',p.id);}
  const l=await one(env,"SELECT id FROM licenses WHERE purchase_id=? AND status='active'",p.id);
  return json({status:p.status,...(p.status==='paid'&&l?{licenseKey:await licenseKey(env,p.id)}:{})});
 }
 if(['/api/activate','/api/refresh','/api/deactivate'].includes(path) && request.method==='POST'){
  const input=await bodyJSON(request),l=await findLicense(env,input.licenseKey);
  if(!/^[A-Za-z0-9-]{32,64}$/.test(input.deviceId||''))fail('Invalid device identity');const deviceHash=await hash(input.deviceId);
  if(path==='/api/deactivate'){await stmt(env,'UPDATE activations SET active=0,updated_at=? WHERE license_id=? AND device_hash=?',now(),l.id,deviceHash).run();return json({deactivated:true});}
  if(path==='/api/activate'){
   // One SQL statement enforces the slot cap even under concurrent requests.
   await stmt(env,`INSERT INTO activations(license_id,device_hash,active,updated_at) SELECT ?,?,1,? WHERE (SELECT COUNT(*) FROM activations WHERE license_id=? AND active=1)<? OR EXISTS(SELECT 1 FROM activations WHERE license_id=? AND device_hash=? AND active=1) ON CONFLICT(license_id,device_hash) DO UPDATE SET active=1,updated_at=excluded.updated_at`,l.id,deviceHash,now(),l.id,l.device_limit,l.id,deviceHash).run();
  }
  if(!await one(env,'SELECT 1 FROM activations WHERE license_id=? AND device_hash=? AND active=1',l.id,deviceHash))fail('No active device slot. Deactivate another Mac first.',409);
  return json({entitlement:await entitlement(env,l,deviceHash)});
 }
 if(path==='/api/recover' && request.method==='POST'){
  if(!env.RESEND_API_KEY||!env.RECOVERY_FROM)fail('Email recovery is not configured yet',503);
  const input=await bodyJSON(request),email=String(input.email||'').trim().toLowerCase();if(email.length>254||!/^\S+@\S+\.\S+$/.test(email))fail('Enter a valid email');
  await limit(env,request,'recover-email',await hash(email));
  const p=await one(env,"SELECT p.id FROM purchases p JOIN licenses l ON l.purchase_id=p.id WHERE p.email=? AND p.status='paid' AND l.status='active' ORDER BY p.created_at DESC LIMIT 1",email);
  if(p){const token=random();await stmt(env,'INSERT INTO recovery_tokens(token_hash,email,expires_at) VALUES(?,?,?)',await hash(token),email,now()+900).run();
   const message=JSON.stringify({from:env.RECOVERY_FROM,to:[email],subject:'Recover your WaveDock test license',text:`Use this one-time link within 15 minutes to recover your WaveDock license:\n${origin(env)}/recover.html#token=${token}\nIf you did not request this, ignore this email.`});
   const id=crypto.randomUUID(),iv=crypto.getRandomValues(new Uint8Array(12));
   const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv},await outboxKey(env),encoder.encode(message));
   await stmt(env,'INSERT INTO email_outbox(id,ciphertext,iv,expires_at) VALUES(?,?,?,?)',id,b64(ciphertext),b64(iv),now()+900).run();
   // The public response never depends on whether the address exists or delivery succeeds.
   if(ctx?.waitUntil)ctx.waitUntil(deliverRecovery(env,id));else await deliverRecovery(env,id);
  }
  return json({accepted:true,message:'If a matching purchase exists, a recovery email will arrive shortly.'});
 }
 if(path==='/api/recover/complete' && request.method==='POST'){
  const {token}=await bodyJSON(request);if(!/^[A-Za-z0-9_-]{43}$/.test(token||''))fail('Invalid or expired recovery link',401);
  const recovery=await stmt(env,'UPDATE recovery_tokens SET used=1 WHERE token_hash=? AND used=0 AND expires_at>? RETURNING email',await hash(token),now()).first();if(!recovery)fail('Invalid or expired recovery link',401);
  const p=await one(env,"SELECT p.id FROM purchases p JOIN licenses l ON l.purchase_id=p.id WHERE p.email=? AND p.status='paid' AND l.status='active' ORDER BY p.created_at DESC LIMIT 1",recovery.email);if(!p)fail('Purchase unavailable',404);
  return json({licenseKey:await licenseKey(env,p.id)});
 }
 if(path==='/api/download' && request.method==='POST'){
  const input=await bodyJSON(request);await findLicense(env,input.licenseKey);
  if(!env.RELEASES||!env.RELEASE_OBJECT)fail('Release download is not ready',503);const object=await env.RELEASES.get(env.RELEASE_OBJECT);if(!object)fail('Release download is not ready',503);
  return new Response(object.body,{headers:{'Content-Type':'application/zip','Content-Disposition':'attachment; filename="WaveDock.zip"','Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}});
 }
 fail('Not found',404);
}
export default {
 async fetch(request,env,ctx){
  try{const path=new URL(request.url).pathname;
   if(path.startsWith('/api/'))return await api(request,env,path,ctx);
   if(path.startsWith('/downloads/'))return json({error:'Use the purchase download page.'},403);
   return env.ASSETS.fetch(request);
  }catch(error){return json({error:error.status?error.message:'Service temporarily unavailable'},error.status||503);}
 },
 async scheduled(_event,env){
  const pending=await env.DB.prepare('SELECT id FROM email_outbox WHERE sent=0 AND attempts<6 AND expires_at>? LIMIT 20').bind(now()).all();
  for(const row of pending.results)await deliverRecovery(env,row.id);
  await env.DB.batch([stmt(env,'DELETE FROM request_limits WHERE expires_at<?',now()),stmt(env,'DELETE FROM recovery_tokens WHERE expires_at<?',now()-86400),stmt(env,'DELETE FROM email_outbox WHERE expires_at<? OR sent=1',now())]);
 }
};
