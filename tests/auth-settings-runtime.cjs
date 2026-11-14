// Exercises the read-only preflight against a loopback HTTP server only.
const assert=require('node:assert/strict'),fs=require('node:fs'),http=require('node:http'),path=require('node:path');
const {once}=require('node:events'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'..');
const config={onlineReady:true,emailAuthEnabled:false,supabaseUrl:'https://nrixslotansgrtrosaof.supabase.co',supabaseAnonKey:'sb_publishable_synthetic_only'};
const settings={external:{google:true,email:false,phone:false,anonymous_users:false},disable_signup:false,mailer_autoconfirm:false};
let count=0;
async function check(label,fn){await fn();console.log('PASS '+(++count)+': '+label)}
(async()=>{
 const {parsePublicAuthConfig,auditPublicAuth}=await import(pathToFileURL(path.join(root,'scripts/verify-auth-settings.mjs')));
 let behavior='ok',payload=settings,requests=[];
 const server=http.createServer((req,res)=>{
  requests.push({method:req.method,path:req.url,headers:req.headers});
  if(behavior==='redirect'){res.writeHead(302,{Location:'/unexpected'});return res.end()}
  if(behavior==='slow'){const timer=setTimeout(()=>{res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(settings))},100);res.on('close',()=>clearTimeout(timer));return}
  if(behavior==='http-error'){res.writeHead(503,{'Content-Type':'application/json'});return res.end(JSON.stringify({private:'upstream credential detail'}))}
  if(behavior==='html'){res.writeHead(200,{'Content-Type':'text/html'});return res.end('<html>unexpected login</html>')}
  res.writeHead(200,{'Content-Type':'application/json'});
  res.end(behavior==='malformed'?'{':behavior==='large'?' '.repeat(65537):JSON.stringify(payload));
 });
 server.listen(0,'127.0.0.1');await once(server,'listening');
 const local='http://127.0.0.1:'+server.address().port;
 const transport=async(url,options)=>{
  assert.equal(url,config.supabaseUrl+'/auth/v1/settings');
  assert.equal(options.method,'GET');assert.equal(options.redirect,'error');
  assert.equal(options.headers.apikey,config.supabaseAnonKey);
  assert.equal(options.body,undefined);
  return fetch(local+'/settings',options);
 };
 const audit=(c=config,options={})=>auditPublicAuth(c,{fetchImpl:transport,...options});
 try{
  await check('project template and JSON config are parsed without executing JavaScript',async()=>{
   assert.equal(parsePublicAuthConfig(fs.readFileSync(path.join(root,'config.example.js'),'utf8')).onlineReady,false);
   assert.deepEqual({...parsePublicAuthConfig('window.TROVAT1O_CONFIG = '+JSON.stringify(config)+';')},config);
   assert.throws(()=>parsePublicAuthConfig('window.TROVAT1O_CONFIG = {}; globalThis.sideEffect = true;'));
   assert.throws(()=>parsePublicAuthConfig('window.TROVAT1O_CONFIG = {onlineReady: (true)};'));
  });
  await check('duplicate config keys and executable expressions are refused',async()=>{
   assert.throws(()=>parsePublicAuthConfig('window.TROVAT1O_CONFIG = {onlineReady: false, onlineReady: true};'));
   assert.throws(()=>parsePublicAuthConfig('window.TROVAT1O_CONFIG = {supabaseUrl: fetch("https://example.invalid")};'));
  });
  await check('preview is explicitly skipped with no network request or false readiness',async()=>{
   const before=requests.length,r=await audit({...config,onlineReady:false});
   assert.equal(r.status,'skipped_preview');assert.equal(r.passed,false);assert.equal(requests.length,before);
  });
  await check('missing or incorrectly typed readiness flags cannot pass',async()=>{
   for(const change of [{onlineReady:'true'},{emailAuthEnabled:undefined},{emailAuthEnabled:'false'}]){
    const before=requests.length,r=await audit({...config,...change});assert.equal(r.passed,false);assert.equal(requests.length,before);
   }
  });
  await check('server keys and wrong or credential-bearing project URLs never reach the network',async()=>{
   for(const change of [{supabaseAnonKey:'sb_secret_do_not_transmit'},{supabaseUrl:'https://other-project.supabase.co'},{supabaseUrl:'http://nrixslotansgrtrosaof.supabase.co'},{supabaseUrl:'https://user:password@nrixslotansgrtrosaof.supabase.co'}]){
    const before=requests.length,r=await audit({...config,...change});assert.equal(r.passed,false);assert.equal(requests.length,before);
   }
  });
  await check('legacy JWT service role is refused before any request',async()=>{
   const jwt=['header',Buffer.from(JSON.stringify({role:'service_role',ref:'nrixslotansgrtrosaof'})).toString('base64url'),'signature'].join('.');
   const before=requests.length,r=await audit({...config,supabaseAnonKey:jwt});assert.equal(r.passed,false);assert.equal(requests.length,before);
  });
  await check('Google-only server and UI agree using one GET and a public key header',async()=>{
   payload=settings;behavior='ok';const r=await audit();assert.equal(r.passed,true);assert.equal(r.status,'passed');
   assert.equal(requests.at(-1).method,'GET');assert.equal(requests.at(-1).headers.apikey,config.supabaseAnonKey);
   assert.equal(requests.at(-1).headers.authorization,undefined);assert.equal(requests.at(-1).headers.cookie,undefined);
   assert.match(r.scope,/SMTP, CAPTCHA/);assert.equal(r.accountsCreated,false);assert.equal(r.emailsSent,false);
  });
  await check('hidden email form cannot conceal an enabled email signup provider',async()=>{
   payload={...settings,external:{...settings.external,email:true}};const r=await audit();
   assert.equal(r.passed,false);assert.deepEqual(r.issues,['email_provider_exposed_while_ui_disabled']);
  });
  await check('offered email login requires an enabled provider and email confirmation',async()=>{
   payload=settings;assert.deepEqual((await audit({...config,emailAuthEnabled:true})).issues,['email_auth_unavailable']);
   payload={...settings,external:{...settings.external,email:true},mailer_autoconfirm:true};
   assert.deepEqual((await audit({...config,emailAuthEnabled:true})).issues,['email_confirmation_disabled']);
   payload.mailer_autoconfirm=false;assert.equal((await audit({...config,emailAuthEnabled:true})).passed,true);
  });
  await check('disabled Google, blocked signup, anonymous and unoffered providers are reported',async()=>{
   for(const [patch,issue] of [
    [{external:{...settings.external,google:false}},'google_auth_unavailable'],
    [{disable_signup:true},'signup_disabled'],
    [{external:{...settings.external,anonymous_users:true}},'anonymous_auth_enabled'],
    [{external:{...settings.external,phone:true}},'unsupported_auth_provider_enabled'],
    [{external:{...settings.external,apple:true}},'unsupported_auth_provider_enabled']]){
    payload={...settings,...patch};assert.ok((await audit()).issues.includes(issue));
   }
  });
  await check('missing and wrongly typed server flags fail closed',async()=>{
   for(const value of [{},{...settings,external:[]},{...settings,disable_signup:'false'},{...settings,external:{google:true,email:false}},{...settings,external:{...settings.external,email:'false'}}]){
    payload=value;const r=await audit();assert.equal(r.passed,false);assert.deepEqual(r.issues,['invalid_auth_settings_response']);
   }
  });
  await check('non-JSON, malformed and oversized responses are refused',async()=>{
   for(const mode of ['html','malformed','large']){behavior=mode;const r=await audit();assert.equal(r.passed,false);assert.equal(r.status,'unverified')}
  });
  await check('HTTP errors never include private upstream diagnostics',async()=>{
   behavior='http-error';const r=await audit();assert.deepEqual(r.issues,['auth_settings_http_error']);
   assert.doesNotMatch(JSON.stringify(r),/credential detail|sb_publishable|apikey/);
  });
  await check('redirect is rejected without forwarding the public key to another path',async()=>{
   behavior='redirect';const before=requests.length,r=await audit();assert.equal(r.passed,false);assert.equal(requests.length,before+1);
   assert.ok(requests.every(x=>x.path==='/settings'));
  });
  await check('timeout and transport exceptions give bounded, redacted failures',async()=>{
   behavior='slow';const r=await audit(config,{timeoutMs:15});assert.equal(r.passed,false);assert.deepEqual(r.issues,['auth_settings_unavailable']);
   const error=await auditPublicAuth(config,{fetchImpl:async()=>{throw Error('private credential detail')}});
   assert.doesNotMatch(JSON.stringify(error),/credential detail/);assert.equal(error.passed,false);
  });
  assert.ok(requests.every(x=>x.method==='GET'&&x.path==='/settings'));
  console.log('PASS: '+count+' public Auth preflight scenarios; only a local HTTP fixture was contacted. No provider, account or delivery is configured by this test.');
 }finally{server.closeAllConnections();server.close();await once(server,'close')}
})().catch(error=>{console.error(error);process.exitCode=1});
