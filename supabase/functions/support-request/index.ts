import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.0';

const appOrigin=Deno.env.get('APP_ORIGIN')||'';
const testOrigin=Deno.env.get('APP_TEST_ORIGIN')??'';
const isId=(value:unknown):value is string=>typeof value==='string'&&/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value);
function isHttpsOrigin(value:string){try{return !value.includes('*')&&new URL(value).protocol==='https:'&&new URL(value).origin===value}catch{return false}}
const originsValid=isHttpsOrigin(appOrigin)&&(testOrigin===''||isHttpsOrigin(testOrigin));
async function readJson(source:Request|Response,maxBytes=32768){
 const reader=source.body?.getReader();if(!reader)throw Error('invalid_request');
 const chunks:Uint8Array[]=[];let size=0;
 try{while(true){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>maxBytes){await reader.cancel();throw Error('too_large')}chunks.push(value)}}finally{reader.releaseLock()}
 const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
Deno.serve(async req=>{
 const origin=req.headers.get('Origin')||'',allowed=originsValid&&(origin===appOrigin||(testOrigin!==''&&origin===testOrigin));
 const cors:Record<string,string>={'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin',...(allowed?{'Access-Control-Allow-Origin':origin}:{})};
 const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
 if(!originsValid)return json({error:'unavailable'},503);
 if(!allowed)return json({error:'forbidden'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return json({error:'invalid_method'},405);
 const bearer=req.headers.get('Authorization')||'';if(!/^Bearer\s+\S+$/i.test(bearer))return json({error:'unauthorized'},401);
 if(!req.headers.get('Content-Type')?.toLowerCase().startsWith('application/json'))return json({error:'invalid_request'},400);
 let b;
 try{b=await readJson(req)}catch(error){return json({error:error instanceof Error&&error.message==='too_large'?'request_too_large':'invalid_request'},error instanceof Error&&error.message==='too_large'?413:400)}
 const keys=['requestId','category','subject','details','contactAllowed','contactName','contactEmail','attachAccount','captchaToken'];
 if(!b||Array.isArray(b)||typeof b!=='object'||Object.keys(b).some(key=>!keys.includes(key))||!isId(b.requestId)||
  !['bug','account','event','safety','other'].includes(b.category)||typeof b.subject!=='string'||typeof b.details!=='string'||
  typeof b.contactAllowed!=='boolean'||typeof b.attachAccount!=='boolean')return json({error:'invalid_request'},400);
 const subject=b.subject.trim(),details=b.details.trim(),length=(s:string)=>Array.from(s).length;
 if(length(subject)<4||length(subject)>120||length(details)<20||length(details)>4000)return json({error:'invalid_request'},400);
 if(typeof b.captchaToken!=='string'||! /^[\x21-\x7e]{1,2048}$/.test(b.captchaToken))return json({error:'captcha_required'},400);
 const follow=b.contactAllowed===true,attach=b.attachAccount===true;
 if(follow&&(typeof b.contactEmail!=='string'||(b.contactName!==undefined&&typeof b.contactName!=='string')))return json({error:'invalid_request'},400);
 const contactName=follow&&typeof b.contactName==='string'?b.contactName.trim()||null:null;
 const contactEmail=follow?b.contactEmail.trim().toLowerCase():null;
 if(follow&&(!contactEmail||length(contactEmail)>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)||contactName&&length(contactName)>80))return json({error:'contact_email_required'},400);
 const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),secret=Deno.env.get('SUPPORT_TURNSTILE_SECRET_KEY');
 // Real anti-abuse configuration is required; public dummy secrets cannot enable the endpoint.
 if(Deno.env.get('SUPPORT_ENABLED')!=='true'||!url||!anon||!service||!secret||secret.length<20||/^[123]x0+AA$/.test(secret))return json({error:'unavailable'},503);
 try{
  const caller=createClient(url,anon,{global:{headers:{Authorization:bearer}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:userError}=await caller.auth.getUser();
  if(userError||!user?.email_confirmed_at||user.is_anonymous)return json({error:'unauthorized'},401);
  const authorization=await caller.rpc('authorize_support_submission');if(authorization.error)throw authorization.error;
  if(authorization.data?.user_id!==user.id||!isId(authorization.data.session_id))return json({error:'unauthorized'},401);
  let captcha;
  try{
   const response=await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({secret,response:b.captchaToken}),signal:AbortSignal.timeout(5000)});
   if(!response.ok)return json({error:'captcha_unavailable'},503);captcha=await readJson(response,8192);
  }catch{return json({error:'captcha_unavailable'},503)}
  const challengeAt=Date.parse(captcha?.challenge_ts),age=Date.now()-challengeAt;
  if(captcha?.success!==true||captcha.hostname!==new URL(origin).hostname||captcha.action!=='support_submit'||!Number.isFinite(challengeAt)||age>300000||age< -30000)return json({error:'captcha_failed'},400);
  const digest=new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(b.captchaToken)));
  const tokenHash=[...digest].map(v=>v.toString(16).padStart(2,'0')).join('');
  const db=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  // The SQL transaction rechecks Auth and the exact session after CAPTCHA, then
  // consumes quota, rejects token replays and commits the ticket atomically.
  const saved=await db.rpc('submit_verified_support_request',{p_user:user.id,p_session:authorization.data.session_id,p_request_id:b.requestId,p_captcha_hash:tokenHash,p_category:b.category,p_subject:subject,p_details:details,p_contact_allowed:follow,p_contact_name:contactName,p_contact_email:contactEmail,p_attach_account:attach});
  if(saved.error)throw saved.error;
  if(!isId(saved.data?.ticketId)||typeof saved.data?.reused!=='boolean')return json({error:'unavailable'},503);
  return json({ok:true,ticketId:saved.data.ticketId});
 }catch(error){
  const code=(error as {code?:string})?.code,message=(error as {message?:string})?.message;
  if(code==='PT401')return json({error:'unauthorized'},401);
  if(code==='PT403')return json({error:'forbidden'},403);
  if(code==='PT429')return json({error:'rate_limited'},429);
  if(code==='PT409'&&['captcha_reused','idempotency_conflict'].includes(message||''))return json({error:message},409);
  if(code==='22023'||code==='22P02')return json({error:'invalid_request'},400);
  return json({error:'unavailable'},503);
 }
});
