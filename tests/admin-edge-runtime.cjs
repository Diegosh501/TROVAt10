// Runs the actual Edge handler with mocked Auth/RPC transports. Database ACL,
// session and MFA authorization are tested separately in sql/admin-access.sql.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {stripTypeScriptTypes}=require('node:module');
const source=fs.readFileSync(path.join(__dirname,'..','supabase/functions/admin-console/index.ts'),'utf8').replace(/^import .*?;\s*/,'');
const js=stripTypeScriptTypes(source,{mode:'strip'});
const appOrigin='https://trovato.diegolucentedesign.workers.dev';
let passed=0;
function boot(options={}){
 let handler;const rpcCalls=[],clientCalls=[];
 const env={APP_ORIGIN:appOrigin,SUPABASE_URL:'https://test.supabase.co',SUPABASE_ANON_KEY:'public-test-key',...(options.env||{})};
 const context={Request,Response,URL,TextDecoder,Uint8Array,Error,JSON,Array,Deno:{env:{get:key=>env[key]},serve:fn=>{handler=fn}},createClient:(url,key,config)=>{
  clientCalls.push({url,key,config});return {auth:{getUser:async()=>{if(options.throwAuth)throw new Error('private upstream diagnostic');return options.userResult||{data:{user:{id:'synthetic-admin',email_confirmed_at:'2026-11-10T00:00:00Z',is_anonymous:false}},error:null}}},rpc:async(name,args)=>{rpcCalls.push({name,args});return options.rpcResult||{data:name==='admin_update_support_ticket'?true:{metrics:{totalUsers:0}},error:null}}}
 }};
 vm.runInNewContext(js,context,{filename:'admin-console/index.ts'});
 async function request(body={action:'dashboard'},extra={}){return handler(new Request(appOrigin+'/functions/v1/admin-console',{method:'POST',headers:{Origin:appOrigin,Authorization:'Bearer synthetic-access-token','Content-Type':'application/json',...(extra.headers||{})},body:typeof body==='string'?body:JSON.stringify(body),...(extra.request||{})}))}
 return {handler,request,rpcCalls,clientCalls};
}
async function check(label,fn){await fn();console.log('PASS '+(++passed)+': '+label)}
(async()=>{
 await check('unconfigured origin fails closed',async()=>{const b=boot({env:{APP_ORIGIN:''}});assert.equal((await b.request()).status,503);assert.equal(b.clientCalls.length,0)});
 await check('wildcard origin is never accepted',async()=>{assert.equal((await boot({env:{APP_ORIGIN:'*'}}).request()).status,503)});
 await check('non-HTTPS production origin fails closed',async()=>{assert.equal((await boot({env:{APP_ORIGIN:'http://example.test'}}).request()).status,503)});
 await check('foreign origin and missing origin are rejected before Auth',async()=>{const b=boot();for(const origin of ['https://attacker.invalid','null',''])assert.equal((await b.request(undefined,{headers:{Origin:origin}})).status,403);assert.equal(b.clientCalls.length,0)});
 await check('only exact-origin preflight succeeds',async()=>{const b=boot();const r=await b.handler(new Request(appOrigin,{method:'OPTIONS',headers:{Origin:appOrigin}}));assert.equal(r.status,204);assert.equal(r.headers.get('Access-Control-Allow-Origin'),appOrigin);assert.equal(b.clientCalls.length,0)});
 await check('unexpected methods are refused',async()=>{assert.equal((await boot().handler(new Request(appOrigin,{headers:{Origin:appOrigin}}))).status,405)});
 await check('missing bearer token is unauthorized',async()=>{const b=boot();assert.equal((await b.request(undefined,{headers:{Authorization:''}})).status,401);assert.equal(b.rpcCalls.length,0)});
 await check('a forged bearer token must pass real Auth verification',async()=>{const b=boot({userResult:{data:{user:null},error:{message:'bad signature'}}});assert.equal((await b.request()).status,401);assert.equal(b.rpcCalls.length,0)});
 await check('unconfirmed and anonymous accounts are denied',async()=>{for(const user of [{id:'x',is_anonymous:false},{id:'x',email_confirmed_at:'now',is_anonymous:true}]){const b=boot({userResult:{data:{user},error:null}});assert.equal((await b.request()).status,401);assert.equal(b.rpcCalls.length,0)}});
 await check('upstream Auth failures do not leak diagnostics',async()=>{const r=await boot({throwAuth:true}).request();assert.equal(r.status,503);assert.deepEqual(await r.json(),{error:'unavailable'})});
 await check('JSON content type and object shape are required',async()=>{for(const body of ['{broken','null','[]','42']){const b=boot();assert.equal((await b.request(body)).status,400);assert.equal(b.rpcCalls.length,0)}assert.equal((await boot().request('{}',{headers:{'Content-Type':'text/plain'}})).status,400)});
 await check('oversized streaming requests cannot bypass the byte limit',async()=>{const b=boot();const stream=new ReadableStream({start(c){c.enqueue(new TextEncoder().encode(' '.repeat(9000)));c.close()}});const r=await b.handler(new Request(appOrigin,{method:'POST',headers:{Origin:appOrigin,Authorization:'Bearer synthetic-access-token','Content-Type':'application/json','Content-Length':'1'},body:stream,duplex:'half'}));assert.equal(r.status,400);assert.deepEqual(await r.json(),{error:'request_too_large'});assert.equal(b.rpcCalls.length,0)});
 await check('unknown actions never reach a database RPC',async()=>{const b=boot();assert.equal((await b.request({action:'provision_platform_admin'})).status,400);assert.equal(b.rpcCalls.length,0)});
 await check('dashboard uses the caller token and no privileged key',async()=>{const b=boot();const r=await b.request();assert.equal(r.status,200);assert.equal(b.rpcCalls[0].name,'admin_dashboard');assert.equal(b.clientCalls[0].key,'public-test-key');assert.equal(b.clientCalls[0].config.global.headers.Authorization,'Bearer synthetic-access-token');assert.equal(r.headers.get('Cache-Control'),'no-store')});
 await check('ticket search has strict typed and bounded filters',async()=>{for(const body of [{query:'x'.repeat(101)},{status:['new']},{category:{}},{sort:'id'}]){const b=boot();assert.equal((await b.request({action:'tickets',...body})).status,400);assert.equal(b.rpcCalls.length,0)}const b=boot();assert.equal((await b.request({action:'tickets',query:'test',status:'new',category:'bug',sort:'name'})).status,200);assert.equal(b.rpcCalls[0].name,'admin_support_tickets');assert.equal(b.rpcCalls[0].args.p_query,'test')});
 await check('ticket mutation validates UUID, state and reply length',async()=>{for(const body of [{id:"x');drop table events;--",status:'closed',reply:''},{id:'12345678-1234-1234-1234-123456789abc',status:'owner',reply:''},{id:'12345678-1234-1234-1234-123456789abc',status:'closed',reply:'x'.repeat(3001)}]){const b=boot();assert.equal((await b.request({action:'update-ticket',...body})).status,400);assert.equal(b.rpcCalls.length,0)}});
 await check('ticket mutation uses a single transactional database operation',async()=>{const b=boot();const r=await b.request({action:'update-ticket',id:'12345678-1234-1234-1234-123456789abc',status:'resolved',reply:'Done'});assert.deepEqual(await r.json(),{ok:true});assert.equal(b.rpcCalls.length,1);assert.equal(b.rpcCalls[0].name,'admin_update_support_ticket')});
 await check('audit read uses its own protected database operation',async()=>{const b=boot();await b.request({action:'audit'});assert.equal(b.rpcCalls[0].name,'admin_audit_log')});
 for(const [code,message,status,publicError] of [['PT401','session_revoked',401,'unauthorized'],['PT403','admin_required',403,'forbidden'],['PT403','mfa_required',403,'mfa_required'],['PT429','admin_rate_limited',429,'rate_limited'],['PT404','ticket_not_found',404,'not_found'],['XX000','private SQL or credentials',503,'unavailable']])await check('database denial '+code+' '+publicError+' is preserved without raw errors',async()=>{const r=await boot({rpcResult:{data:null,error:{code,message}}}).request();assert.equal(r.status,status);assert.deepEqual(await r.json(),{error:publicError})});
 console.log(`PASS: ${passed} actual administrative Edge handler scenarios.`);
})().catch(error=>{console.error(error);process.exitCode=1});
