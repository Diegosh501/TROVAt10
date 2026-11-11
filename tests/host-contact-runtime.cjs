const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {stripTypeScriptTypes}=require('node:module');
const src=stripTypeScriptTypes(fs.readFileSync('supabase/functions/host-contact/index.ts','utf8').replace(/^import .*?;\s*/,''),{mode:'strip'});
const origin='https://app.example.test',userId='11111111-1111-4111-8111-111111111111',sessionId='22222222-2222-4222-8222-222222222222',eventId='33333333-3333-4333-8333-333333333333';
const phone='+393331234567',secret='synthetic-phone-binding-fixture-32-bytes';
const expected=crypto.createHmac('sha256',secret).update(phone).digest('hex');
function boot(options={}){
 let handler;const calls=[],clients=[];
 const env={APP_ORIGIN:origin,SUPABASE_URL:'https://project.supabase.co',SUPABASE_ANON_KEY:'public-fixture',SUPABASE_SERVICE_ROLE_KEY:'server-fixture',PHONE_HASH_SECRET:secret,...options.env};
 vm.runInNewContext(src,{Deno:{env:{get:k=>env[k]},serve:fn=>handler=fn},Request,Response,URL,Uint8Array,TextDecoder,TextEncoder,JSON,Object,Array,Error,crypto:crypto.webcrypto,
 createClient:(url,key,config)=>{clients.push({url,key,config});return {auth:{getUser:async()=>options.badAuth?{data:{user:null},error:{message:'bad JWT'}}:{data:{user:{id:userId,email_confirmed_at:'2026-01-01',is_anonymous:!!options.anonymous}},error:null}},rpc:async(name,args)=>{
 calls.push({name,args});
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
