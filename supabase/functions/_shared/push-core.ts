export type PushConfig={enabled:boolean;cronSecret:string;publicKey:string;privateKey:string;subject:string;origin:string};
export type PushPorts={rpc:(name:string,args:Record<string,unknown>)=>Promise<any>;
  prepare:(subscription:any,payload:string,options:any)=>any;send:(details:any)=>Promise<Response>};
const idPattern=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function permittedPushEndpoint(value:unknown){
  if(typeof value!=='string'||value.length>2048)return false;
  try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&!u.hash&&!u.search&&u.pathname!=='/'&&
    ['fcm.googleapis.com','updates.push.services.mozilla.com','web.push.apple.com'].includes(u.hostname)}catch{return false}
}
function validConfig(c:PushConfig){
  try{return c.enabled&&/^[A-Za-z0-9_-]{43,128}$/.test(c.cronSecret)&&/^[A-Za-z0-9_-]{87}$/.test(c.publicKey)&&
    /^[A-Za-z0-9_-]{43}$/.test(c.privateKey)&&new URL(c.origin).origin===c.origin&&new URL(c.origin).protocol==='https:'&&
    (/^mailto:[^@\s]+@[^@\s]+\.[^@\s]+$/.test(c.subject)||(new URL(c.subject).protocol==='https:'&&new URL(c.subject).origin===c.origin))}catch{return false}
}
async function matchingVapidKeys(publicKey:string,privateKey:string){
  try{
    const raw=Uint8Array.from(atob(publicKey.replace(/-/g,'+').replace(/_/g,'/')+'='),c=>c.charCodeAt(0));
    if(raw.length!==65||raw[0]!==4)return false;
    const encode=(part:Uint8Array)=>btoa(String.fromCharCode(...part)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
    const publicCryptoKey=await crypto.subtle.importKey('raw',raw,{name:'ECDSA',namedCurve:'P-256'},false,['verify']);
    const privateCryptoKey=await crypto.subtle.importKey('jwk',{kty:'EC',crv:'P-256',x:encode(raw.slice(1,33)),y:encode(raw.slice(33)),d:privateKey},
      {name:'ECDSA',namedCurve:'P-256'},false,['sign']);
    const probe=crypto.getRandomValues(new Uint8Array(32));
    const signature=await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},privateCryptoKey,probe);
    return await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},publicCryptoKey,signature,probe);
  }catch{return false}
}
function equalSecret(a:string,b:string){const x=new TextEncoder().encode(a),y=new TextEncoder().encode(b);let diff=x.length^y.length;
  for(let i=0;i<Math.max(x.length,y.length);i++)diff|=(x[i]||0)^(y[i]||0);return diff===0}
function reply(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}})}
async function readSmallBody(req:Request){
  const reader=req.body?.getReader();if(!reader)return '{}';let size=0;const parts:Uint8Array[]=[];
  try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>1024){await reader.cancel();throw new Error('large')}parts.push(value)}}finally{reader.releaseLock()}
  const bytes=new Uint8Array(size);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length}
  return new TextDecoder('utf-8',{fatal:true}).decode(bytes)||'{}';
}
export function createPushDispatcher(c:PushConfig,p:PushPorts){
 let keyCheck:{publicKey:string;privateKey:string;result:Promise<boolean>}|null=null;
 function keysReady(){if(!keyCheck||keyCheck.publicKey!==c.publicKey||keyCheck.privateKey!==c.privateKey){
   keyCheck={publicKey:c.publicKey,privateKey:c.privateKey,result:matchingVapidKeys(c.publicKey,c.privateKey)};
 }return keyCheck.result}
 return async(req:Request)=>{
  if(!validConfig(c))return reply({error:'push_unavailable'},503);
  if(req.method!=='POST')return reply({error:'invalid_method'},405);
  if(req.headers.has('Origin'))return reply({error:'forbidden'},403);
  const authorization=req.headers.get('Authorization')||'';
  if(authorization.length>160||!equalSecret(authorization,'Bearer '+c.cronSecret))return reply({error:'unauthorized'},401);
  if(!req.headers.get('Content-Type')?.toLowerCase().startsWith('application/json'))return reply({error:'invalid_request'},400);
  try{const body=JSON.parse(await readSmallBody(req));if(!body||Array.isArray(body)||typeof body!=='object'||Object.keys(body).length)return reply({error:'invalid_request'},400)}catch{return reply({error:'invalid_request'},400)}
  // Check once per key pair, only after authenticating the bounded job request.
  // A bad deployment must not consume leases or discard queued notifications.
  if(!await keysReady())return reply({error:'push_unavailable'},503);
  let rows:any[];
  try{rows=await p.rpc('claim_push_deliveries',{p_limit:10});if(!Array.isArray(rows)||rows.length>10)throw new Error('bad_claim')}
  catch{return reply({error:'unavailable'},503)}
  const counts={claimed:rows.length,sent:0,retry:0,gone:0,invalid:0,skipped:0,callbackErrors:0};
  async function finish(row:any,result:'sent'|'retry'|'gone'|'invalid'|'skipped'){
    try{const ok=await p.rpc('finish_push_delivery',{p_delivery:row.delivery_id,p_lease:row.lease_token,p_result:result});if(ok!==true)counts.callbackErrors++}
    catch{counts.callbackErrors++}counts[result]++;
  }
  async function deliver(claim:any){
    if(!claim||!idPattern.test(claim.delivery_id)||!idPattern.test(claim.lease_token)){counts.callbackErrors++;return}
    let row:any;
    try{row=await p.rpc('check_push_delivery',{p_delivery:claim.delivery_id,p_lease:claim.lease_token})}catch{counts.callbackErrors++;return}
    if(!row)return finish(claim,'skipped');
    if(row.delivery_id!==claim.delivery_id||row.lease_token!==claim.lease_token||!idPattern.test(row.notice_id)||
      !idPattern.test(row.subscription_id)||!permittedPushEndpoint(row.endpoint)||
      typeof row.p256dh!=='string'||!/^[A-Za-z0-9_-]{87,88}$/.test(row.p256dh)||typeof row.auth!=='string'||!/^[A-Za-z0-9_-]{22,24}$/.test(row.auth))return finish(claim,'invalid');
    let details:any;
    try{
      const payload=JSON.stringify({title:'TROVAT1O',body:'Hai un aggiornamento per una partita.',url:'/?notifications=1',tag:'trovat1o-'+row.notice_id});
      details=p.prepare({endpoint:row.endpoint,keys:{p256dh:row.p256dh,auth:row.auth}},payload,
        {vapidDetails:{subject:c.subject,publicKey:c.publicKey,privateKey:c.privateKey},TTL:300,contentEncoding:'aes128gcm',urgency:'normal'});
      if(details.endpoint!==row.endpoint||!permittedPushEndpoint(details.endpoint)||details.method!=='POST')return finish(claim,'invalid');
    }catch{return finish(claim,'invalid')}
    // Consent/ownership/lease is checked once more after encryption. A withdrawal
    // already committed before this final check prevents the network request.
    try{if(!await p.rpc('check_push_delivery',{p_delivery:claim.delivery_id,p_lease:claim.lease_token}))return finish(claim,'skipped')}
    catch{counts.callbackErrors++;return}
    let status:number;
    try{const result=await p.send(details);status=result.status;await result.body?.cancel()}catch{return finish(claim,'retry')}
    if(status>=200&&status<300)return finish(claim,'sent');
    if(status===404||status===410)return finish(claim,'gone');
    if(status===429||status>=500)return finish(claim,'retry');
    return finish(claim,'invalid');
  }
  // Two bounded lanes keep a ten-row batch below the three-minute DB lease.
  let next=0;async function lane(){while(next<rows.length){const row=rows[next++];await deliver(row)}}
  await Promise.all([lane(),lane()]);
  return reply(counts,counts.callbackErrors?503:200);
}}
