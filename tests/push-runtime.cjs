const assert=require('node:assert/strict');
const {createECDH}=require('node:crypto');
const {createPushDispatcher,permittedPushEndpoint}=require('../supabase/functions/_shared/push-core.ts');
const id='11111111-1111-4111-8111-111111111111',lease='22222222-2222-4222-8222-222222222222',notice='33333333-3333-4333-8333-333333333333';
// Ephemeral synthetic signing material: never a deploy credential or an output.
const signing=createECDH('prime256v1');signing.generateKeys();
const config={enabled:true,cronSecret:'c'.repeat(43),publicKey:signing.getPublicKey().toString('base64url'),privateKey:signing.getPrivateKey().toString('base64url'),subject:'mailto:support@example.test',origin:'https://app.example.test'};
function boot(options={}){
 const calls=[],sent=[],prepared=[];let checks=0;
 const row={delivery_id:id,lease_token:lease,subscription_id:id,notice_id:notice,endpoint:'https://fcm.googleapis.com/fcm/send/synthetic-token',p256dh:'a'.repeat(87),auth:'b'.repeat(22),...options.row};
 const ports={rpc:async(name,args)=>{calls.push({name,args});if(options.throwAt===name)throw new Error('private endpoint/key diagnostics');
  if(name==='claim_push_deliveries')return options.rows||[row];
  if(name==='check_push_delivery'){checks++;return options.withdraw||(options.withdrawAfterCrypto&&checks>1)?null:row}
  return options.callbackFalse?false:true;},prepare:(subscription,payload,opts)=>{prepared.push({subscription,payload,opts});if(options.cryptoError)throw new Error('sensitive crypto error');return {endpoint:subscription.endpoint,method:'POST',headers:{},body:new Uint8Array([1,2,3]),...options.details}},
 send:async details=>{sent.push(details);if(options.networkError)throw new Error('private network failure');return new Response('',{status:options.status||201})}};
 const handler=createPushDispatcher({...config,...options.config},ports);
 const request=(body='{}',headers={})=>handler(new Request(config.origin,{method:'POST',headers:{Authorization:'Bearer '+config.cronSecret,'Content-Type':'application/json',...headers},body}));
 return {calls,sent,prepared,handler,request};
}
let n=0;async function check(label,fn){await fn();console.log('PASS '+(++n)+': '+label)}
const finishes=b=>b.calls.filter(c=>c.name==='finish_push_delivery');
(async()=>{
 await check('default-off/unconfigured dispatcher never touches database',async()=>{const b=boot({config:{enabled:false}});assert.equal((await b.request()).status,503);assert.equal(b.calls.length,0)});
 await check('malformed VAPID, contact or origin fails closed',async()=>{for(const config of [{publicKey:''},{privateKey:'short'},{cronSecret:'short'},{subject:'invalid'},{origin:'http://app.example.test'}]){const b=boot({config});assert.equal((await b.request()).status,503)}});
  await check('shape-valid but mismatched signing keys cannot claim queued notices',async()=>{const other=createECDH('prime256v1');other.generateKeys();const b=boot({config:{privateKey:other.getPrivateKey().toString('base64url')}});assert.equal((await b.request()).status,503);assert.equal(b.calls.length,0);assert.equal(b.sent.length,0)});
  await check('invalid public curve point cannot consume a delivery',async()=>{const b=boot({config:{publicKey:'B'+'p'.repeat(86)}});assert.equal((await b.request()).status,503);assert.equal(b.calls.length,0)});
 await check('browser-origin requests and absent/incorrect cron secrets are rejected',async()=>{const b=boot();assert.equal((await b.request('{}',{Origin:config.origin})).status,403);for(const Authorization of ['', 'Bearer wrong'])assert.equal((await b.request('{}',{Authorization})).status,401);assert.equal(b.calls.length,0)});
 await check('request accepts only a bounded empty JSON object',async()=>{for(const body of ['[]','null','broken','{"endpoint":"https://evil.invalid"}',' '.repeat(1030)])assert.equal((await boot().request(body)).status,400)});
 await check('endpoint allowlist rejects SSRF, user-info, ports, redirects and lookalike domains',async()=>{for(const url of ['http://fcm.googleapis.com/x','https://127.0.0.1/x','https://localhost/x','https://169.254.169.254/latest','https://fcm.googleapis.com.evil.invalid/x','https://fcm.googleapis.com@evil.invalid/x','https://evil.invalid@fcm.googleapis.com/x','https://fcm.googleapis.com:8443/x','https://fcm.googleapis.com/x?redirect=https://evil.invalid','https://[::1]/x'])assert.equal(permittedPushEndpoint(url),false);for(const url of ['https://fcm.googleapis.com/fcm/send/a','https://updates.push.services.mozilla.com/wpush/v2/a','https://web.push.apple.com/a'])assert.equal(permittedPushEndpoint(url),true)});
 await check('invalid stored endpoint is never encrypted or sent',async()=>{const b=boot({row:{endpoint:'https://169.254.169.254/latest'}});assert.equal((await b.request()).status,200);assert.equal(b.prepared.length,0);assert.equal(b.sent.length,0);assert.equal(finishes(b)[0].args.p_result,'invalid')});
 await check('normal delivery uses generic payload and short TTL without event/contact data',async()=>{const b=boot();const response=await b.request();assert.equal(response.status,200);assert.equal(response.headers.get('Cache-Control'),'no-store');const p=JSON.parse(b.prepared[0].payload);assert.deepEqual(p,{title:'TROVAT1O',body:'Hai un aggiornamento per una partita.',url:'/?notifications=1',tag:'trovat1o-'+notice});assert.equal(b.prepared[0].opts.TTL,300);assert.equal(finishes(b)[0].args.p_lease,lease);assert.equal(finishes(b)[0].args.p_result,'sent');const output=await response.text();assert.ok(!output.includes('synthetic-token'));assert.ok(!output.includes(config.privateKey))});
 await check('consent withdrawal after claim prevents transmission',async()=>{const b=boot({withdraw:true});await b.request();assert.equal(b.sent.length,0);assert.equal(finishes(b)[0].args.p_result,'skipped')});
 await check('consent is rechecked again after encryption',async()=>{const b=boot({withdrawAfterCrypto:true});await b.request();assert.equal(b.prepared.length,1);assert.equal(b.sent.length,0)});
 await check('prepared request cannot switch endpoint or method',async()=>{for(const details of [{endpoint:'https://evil.invalid/steal'},{method:'GET'}]){const b=boot({details});await b.request();assert.equal(b.sent.length,0);assert.equal(finishes(b)[0].args.p_result,'invalid')}});
 await check('HTTP410/404 use token-protected subscription cleanup',async()=>{for(const status of [404,410]){const b=boot({status});await b.request();assert.equal(finishes(b)[0].args.p_result,'gone');assert.equal(finishes(b)[0].args.p_lease,lease)}});
 await check('HTTP429/5xx and timeouts retry without exposing upstream response',async()=>{for(const opts of [{status:429},{status:503},{networkError:true}]){const b=boot(opts);await b.request();assert.equal(finishes(b)[0].args.p_result,'retry')}});
 await check('other HTTP errors and invalid encryption data stop rather than loop',async()=>{for(const opts of [{status:400},{cryptoError:true}]){const b=boot(opts);await b.request();assert.equal(finishes(b)[0].args.p_result,'invalid')}});
 await check('mismatched lease or identity shape is never sent',async()=>{const b=boot({row:{lease_token:'bad'}});assert.equal((await b.request()).status,503);assert.equal(b.sent.length,0)});
 await check('failed DB acknowledgements return503 so scheduler can observe failure',async()=>{const b=boot({callbackFalse:true});assert.equal((await b.request()).status,503)});
 await check('database failures expose only generic unavailability',async()=>{const b=boot({throwAt:'claim_push_deliveries'});const r=await b.request();assert.equal(r.status,503);assert.deepEqual(await r.json(),{error:'unavailable'})});
 await check('unexpected large database batches cannot expand work',async()=>{const b=boot({rows:new Array(11).fill({})});assert.equal((await b.request()).status,503);assert.equal(b.sent.length,0)});
 console.log('PASS: '+n+' actual dispatcher scenarios; no real push delivered.');
})().catch(e=>{console.error(e);process.exitCode=1});
