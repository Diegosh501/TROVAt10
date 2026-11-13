const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {stripTypeScriptTypes}=require('node:module');
const src=stripTypeScriptTypes(fs.readFileSync('supabase/functions/host-contact/index.ts','utf8').replace(/^import .*?;\s*/,''),{mode:'strip'});
const origin='https://app.example.test',userId='11111111-1111-4111-8111-111111111111',sessionId='22222222-2222-4222-8222-222222222222',eventId='33333333-3333-4333-8333-333333333333';
const testOrigin='https://v1-check-trovato.diegolucentedesign.workers.dev';
const phone='+393331234567',secret='synthetic-phone-binding-fixture-32-bytes';
const expected=crypto.createHmac('sha256',secret).update(phone).digest('hex');
function boot(options={}){
 let handler;const calls=[],clients=[];
 const env={APP_ORIGIN:origin,SUPABASE_URL:'https://project.supabase.co',SUPABASE_ANON_KEY:'public-fixture',SUPABASE_SERVICE_ROLE_KEY:'server-fixture',PHONE_HASH_SECRET:secret,...options.env};
 vm.runInNewContext(src,{Deno:{env:{get:k=>env[k]},serve:fn=>handler=fn},Request,Response,URL,Uint8Array,TextDecoder,TextEncoder,JSON,Object,Array,Error,crypto:crypto.webcrypto,
 createClient:(url,key,config)=>{clients.push({url,key,config});return {auth:{getUser:async()=>options.badAuth?{data:{user:null},error:{message:'bad JWT'}}:{data:{user:{id:userId,email_confirmed_at:'2026-01-01',is_anonymous:!!options.anonymous}},error:null}},rpc:async(name,args)=>{
 calls.push({name,args});
 if(options.rpc)return options.rpc({name,args,authorization:config?.global?.headers?.Authorization,key});
 if(name==='authorize_host_contact')return options.authzError?{data:null,error:options.authzError}:{data:{user_id:options.wrongUser?'other':userId,session_id:sessionId},error:null};
 if(options.writeError)return {data:null,error:options.writeError};
 if(args.p_share&&(args.p_hash!==expected||args.p_phone!==phone))return {data:null,error:{code:'PT403',message:'phone_mismatch'}};
 return {data:true,error:null};}}}});
 const request=(body={eventId,phone,consent:true},headers={})=>handler(new Request(origin,{method:'POST',headers:{Origin:origin,Authorization:'Bearer synthetic','Content-Type':'application/json',...headers},body:typeof body==='string'?body:JSON.stringify(body)}));
 return {handler,request,calls,clients};
}
let count=0;async function check(label,fn){await fn();console.log('PASS '+(++count)+': '+label)}
(async()=>{
 await check('unconfigured and insecure origins fail closed',async()=>{for(const APP_ORIGIN of ['', '*','http://app.example.test']){const b=boot({env:{APP_ORIGIN}});assert.equal((await b.request()).status,503);assert.equal(b.calls.length,0)}});
 await check('foreign origins and missing authorization never reach the database',async()=>{for(const headers of [{Origin:'https://attacker.invalid'},{Origin:''},{Authorization:''}]){const b=boot();assert.ok([401,403].includes((await b.request(undefined,headers)).status));assert.equal(b.calls.length,0)}});
 await check('exact-origin preflight requires no account',async()=>{const b=boot();assert.equal((await b.handler(new Request(origin,{method:'OPTIONS',headers:{Origin:origin}}))).status,204);assert.equal(b.calls.length,0)});
 await check('test origin requires explicit configuration and cannot replace an unset primary',async()=>{for(const value of [undefined,'']){const b=boot({env:{APP_TEST_ORIGIN:value}});const r=await b.handler(new Request(origin,{method:'OPTIONS',headers:{Origin:testOrigin}}));assert.equal(r.status,403);assert.equal(r.headers.get('Access-Control-Allow-Origin'),null);assert.equal(b.clients.length,0)}for(const value of [undefined,'']){const b=boot({env:{APP_ORIGIN:value,APP_TEST_ORIGIN:testOrigin}});const r=await b.request(undefined,{Origin:testOrigin});assert.equal(r.status,503);assert.equal(r.headers.get('Access-Control-Allow-Origin'),null);assert.equal(b.clients.length,0)}});
 await check('both exact origins allow standard Supabase preflight without reflecting arbitrary headers',async()=>{const b=boot({env:{APP_TEST_ORIGIN:testOrigin}});for(const requestOrigin of [origin,testOrigin]){const r=await b.handler(new Request(origin,{method:'OPTIONS',headers:{Origin:requestOrigin,'Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'authorization, x-client-info, apikey, content-type, x-attacker'}}));assert.equal(r.status,204);assert.equal(r.headers.get('Access-Control-Allow-Origin'),requestOrigin);assert.equal(r.headers.get('Access-Control-Allow-Headers'),'authorization, x-client-info, apikey, content-type');assert.equal(r.headers.get('Access-Control-Allow-Methods'),'POST, OPTIONS');assert.equal(r.headers.get('Vary'),'Origin')}assert.equal(b.clients.length,0)});
 await check('malformed configured origins fail closed before Auth or database work',async()=>{for(const field of ['APP_ORIGIN','APP_TEST_ORIGIN'])for(const value of ['*','https://*.example.test','http://example.test','https://example.test/','https://example.test/path','https://example.test?query=1','https://example.test#fragment','https://user:password@example.test',' https://example.test','https://example.test,https://other.test']){const b=boot({env:{APP_TEST_ORIGIN:testOrigin,[field]:value}});for(const requestOrigin of [origin,testOrigin]){const r=await b.request(undefined,{Origin:requestOrigin});assert.equal(r.status,503,field+' '+value);assert.equal(r.headers.get('Access-Control-Allow-Origin'),null,field+' '+value)}assert.equal(b.clients.length,0)}});
 await check('configured test origin does not permit siblings suffixes paths or absent origins',async()=>{const b=boot({env:{APP_TEST_ORIGIN:testOrigin}});for(const requestOrigin of [testOrigin+'.attacker.invalid','https://sibling-trovato.diegolucentedesign.workers.dev',testOrigin+'/',testOrigin+'?query=1','null',''])for(const method of ['OPTIONS','POST']){const r=await b.handler(new Request(origin,{method,headers:{Origin:requestOrigin}}));assert.equal(r.status,403,requestOrigin);assert.equal(r.headers.get('Access-Control-Allow-Origin'),null,requestOrigin)}assert.equal(b.clients.length,0)});
 await check('test-origin contact requests still require verified Auth and caller authorization',async()=>{const missing=boot({env:{APP_TEST_ORIGIN:testOrigin}});let r=await missing.request(undefined,{Origin:testOrigin,Authorization:''});assert.equal(r.status,401);assert.equal(r.headers.get('Access-Control-Allow-Origin'),testOrigin);assert.equal(missing.calls.length,0);const forged=boot({env:{APP_TEST_ORIGIN:testOrigin},badAuth:true});r=await forged.request(undefined,{Origin:testOrigin});assert.equal(r.status,401);assert.equal(r.headers.get('Access-Control-Allow-Origin'),testOrigin);assert.equal(forged.calls.length,0);for(const code of ['PT401','PT403']){const b=boot({env:{APP_TEST_ORIGIN:testOrigin},authzError:{code,message:'private diagnostic'}});r=await b.request(undefined,{Origin:testOrigin});assert.equal(r.status,code==='PT401'?401:403);assert.equal(r.headers.get('Access-Control-Allow-Origin'),testOrigin);assert.equal(b.calls.length,1);assert.ok(!(await r.text()).includes('private diagnostic'))}});
 await check('test-origin sharing preserves HMAC requirements while removal works without a key',async()=>{for(const PHONE_HASH_SECRET of [undefined,'','short']){const b=boot({env:{APP_TEST_ORIGIN:testOrigin,PHONE_HASH_SECRET}});let r=await b.request(undefined,{Origin:testOrigin});assert.equal(r.status,503);assert.equal(b.clients.length,0);r=await b.request({eventId,phone:'',consent:false},{Origin:testOrigin});assert.equal(r.status,200);assert.equal(r.headers.get('Access-Control-Allow-Origin'),testOrigin);assert.equal(b.calls[1].name,'set_verified_host_contact');assert.equal(b.calls[1].args.p_share,false);assert.equal(b.calls[1].args.p_hash,'');assert.equal(b.calls[1].args.p_phone,'');assert.equal(b.calls[1].args.p_user,userId);assert.equal(b.calls[1].args.p_session,sessionId)}});
 await check('concurrent production and test requests isolate headers and caller-bound session checks',async()=>{
  let resolveProduction,resolveTest,resolveReached;
  const production=new Promise(r=>{resolveProduction=r}),test=new Promise(r=>{resolveTest=r}),reached=new Promise(r=>{resolveReached=r});
  let arrivals=0;
  const b=boot({env:{APP_TEST_ORIGIN:testOrigin,PHONE_HASH_SECRET:''},rpc:({name,authorization})=>{
   if(name==='authorize_host_contact'){if(++arrivals===2)resolveReached();return authorization==='Bearer production-caller'?production:test}
   return {data:true,error:null};
  }});
  const first=b.request({eventId,phone:'',consent:false},{Origin:origin,Authorization:'Bearer production-caller'});
  const second=b.request({eventId,phone:'',consent:false},{Origin:testOrigin,Authorization:'Bearer test-caller'});
  let timeout;
  try{await Promise.race([reached,new Promise((_,reject)=>{timeout=setTimeout(()=>reject(new Error('requests did not reach independent authorizations')),1000)})]);}
  finally{clearTimeout(timeout)}
  resolveTest({data:{user_id:userId,session_id:sessionId},error:null});
  const testResponse=await second;
  assert.equal(testResponse.status,200);assert.equal(testResponse.headers.get('Access-Control-Allow-Origin'),testOrigin);
  resolveProduction({data:null,error:{code:'PT401',message:'session_revoked'}});
  const productionResponse=await first;
  assert.equal(productionResponse.status,401);assert.equal(productionResponse.headers.get('Access-Control-Allow-Origin'),origin);
  assert.deepEqual(await productionResponse.json(),{error:'unauthorized'});
  assert.deepEqual(b.clients.filter(c=>c.key==='public-fixture').map(c=>c.config.global.headers.Authorization),['Bearer production-caller','Bearer test-caller']);
  assert.equal(b.calls.filter(c=>c.name==='set_verified_host_contact').length,1);
 });
 await check('malformed or non-object JSON is rejected',async()=>{for(const body of ['broken','[]','null','42']){const b=boot();assert.equal((await b.request(body)).status,400);assert.equal(b.calls.length,0)}});
 await check('a streaming payload cannot evade the real byte limit',async()=>{const b=boot();assert.equal((await b.request(' '.repeat(3000),{'Content-Length':'1'})).status,400);assert.equal(b.calls.length,0)});
 await check('only exact event, E164 phone and explicit consent are accepted',async()=>{for(const body of [{eventId:'bad',phone,consent:true},{eventId,phone:'3331234567',consent:true},{eventId,phone},{eventId,phone,consent:'true'},{eventId,phone,consent:true,userId:'victim'}]){const b=boot();assert.equal((await b.request(body)).status,400);assert.equal(b.calls.length,0)}});
 await check('a missing or short server HMAC key disables contact sharing',async()=>{for(const PHONE_HASH_SECRET of ['', 'short'])assert.equal((await boot({env:{PHONE_HASH_SECRET}}).request()).status,503)});
 await check('forged JWT and anonymous identities cannot publish a number',async()=>{for(const opts of [{badAuth:true},{anonymous:true}]){const b=boot(opts);assert.equal((await b.request()).status,401);assert.equal(b.calls.length,0)}});
 await check('server authorization rejects non-owners and revoked sessions',async()=>{for(const [code,status]of [['PT403',403],['PT401',401],['PT429',429]]){const b=boot({authzError:{code,message:'private detail'}});const r=await b.request();assert.equal(r.status,status);assert.equal(b.calls.length,1);assert.ok(!(await r.text()).includes('private detail'))}});
 await check('the verified Auth user must match the caller-bound RPC result',async()=>{const b=boot({wrongUser:true});assert.equal((await b.request()).status,401);assert.equal(b.calls.length,1)});
 await check('only the verified number HMAC is submitted with explicit consent',async()=>{const b=boot();const r=await b.request();assert.equal(r.status,200);assert.deepEqual(await r.json(),{ok:true});assert.equal(r.headers.get('Cache-Control'),'no-store');const write=b.calls[1];assert.equal(write.name,'set_verified_host_contact');assert.equal(write.args.p_hash,expected);assert.equal(write.args.p_user,userId);assert.equal(write.args.p_session,sessionId);assert.equal(write.args.p_share,true);assert.equal(b.clients[0].key,'public-fixture');assert.equal(b.clients[1].key,'server-fixture')});
 await check('another E164 number is not accepted merely because the profile is verified',async()=>{const b=boot();const r=await b.request({eventId,phone:'+393339999999',consent:true});assert.equal(r.status,403);assert.deepEqual(await r.json(),{error:'phone_mismatch'})});
 await check('consent can be revoked even if phone service is not configured',async()=>{const b=boot({env:{PHONE_HASH_SECRET:''}});assert.equal((await b.request({eventId,phone:'',consent:false})).status,200);assert.equal(b.calls[1].args.p_share,false);assert.equal(b.calls[1].args.p_hash,'');assert.equal(b.calls[1].args.p_phone,'')});
 await check('database failures never expose server diagnostics',async()=>{const r=await boot({writeError:{code:'XX000',message:'private secret diagnostic'}}).request();assert.equal(r.status,503);assert.deepEqual(await r.json(),{error:'unavailable'})});
 console.log('PASS: '+count+' actual Host contact handler scenarios; transport is controlled, DB RLS requires separate tests.');
})().catch(e=>{console.error(e);process.exitCode=1});
