import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.0';
const origin=Deno.env.get('APP_ORIGIN')||'';
const cors={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type',
  'Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin'};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,
  'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
async function readBody(req:Request){
  const reader=req.body?.getReader();if(!reader)throw new Error('invalid_request');
  const chunks:Uint8Array[]=[];let size=0;
  try{while(true){const {value,done}=await reader.read();if(done)break;size+=value.length;
    if(size>2048){await reader.cancel();throw new Error('too_large')}chunks.push(value)}}finally{reader.releaseLock()}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length}
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
Deno.serve(async req=>{
  try{if(new URL(origin).origin!==origin||new URL(origin).protocol!=='https:')return json({error:'unavailable'},503)}catch{return json({error:'unavailable'},503)}
  if(req.headers.get('Origin')!==origin)return json({error:'forbidden'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return json({error:'invalid_method'},405);
  const bearer=req.headers.get('Authorization')||'';
  if(!/^Bearer\s+\S+$/i.test(bearer))return json({error:'unauthorized'},401);
  if(!req.headers.get('Content-Type')?.toLowerCase().startsWith('application/json'))return json({error:'invalid_request'},400);
  let body;
  try{body=await readBody(req)}catch(e){return json({error:e instanceof Error&&e.message==='too_large'?'too_large':'invalid_request'},400)}
  if(!body||Array.isArray(body)||typeof body!=='object'||Object.keys(body).some(k=>!['eventId','phone','consent'].includes(k))||
    typeof body.eventId!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.eventId)||
    typeof body.consent!=='boolean'||(body.consent&&(typeof body.phone!=='string'||!/^\+[1-9]\d{7,14}$/.test(body.phone))))return json({error:'invalid_request'},400);
  const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),secret=Deno.env.get('PHONE_HASH_SECRET');
  if(!url||!anon||!service||(body.consent&&(!secret||secret.length<32)))return json({error:'unavailable'},503);
  try{
    const caller=createClient(url,anon,{global:{headers:{Authorization:bearer}},auth:{persistSession:false,autoRefreshToken:false}});
    const {data:{user},error}=await caller.auth.getUser();
    if(error||!user?.email_confirmed_at||user.is_anonymous)return json({error:'unauthorized'},401);
    const authorization=await caller.rpc('authorize_host_contact',{p_event:body.eventId});
    if(authorization.error)throw authorization.error;
    if(authorization.data?.user_id!==user.id||!authorization.data.session_id)return json({error:'unauthorized'},401);
    let hash='';
    if(body.consent){const enc=new TextEncoder(),key=await crypto.subtle.importKey('raw',enc.encode(secret!),{name:'HMAC',hash:'SHA-256'},false,['sign']);
      const bytes=new Uint8Array(await crypto.subtle.sign('HMAC',key,enc.encode(body.phone)));
      hash=[...bytes].map(v=>v.toString(16).padStart(2,'0')).join('')}
    const db=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
    const saved=await db.rpc('set_verified_host_contact',{p_user:user.id,p_session:authorization.data.session_id,p_event:body.eventId,
      p_phone:body.consent?body.phone:'',p_hash:hash,p_share:body.consent});
    if(saved.error)throw saved.error;if(saved.data!==true)return json({error:'unavailable'},503);
    return json({ok:true});
  }catch(e){const code=(e as {code?:string})?.code,message=(e as {message?:string})?.message;
    if(code==='PT401')return json({error:'unauthorized'},401);
    if(code==='PT429')return json({error:'rate_limited'},429);
    if(code==='PT403')return json({error:message==='phone_mismatch'?'phone_mismatch':'forbidden'},403);
    return json({error:'unavailable'},503)}
});
