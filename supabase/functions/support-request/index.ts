import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.0';
const cors = (origin:string) => ({'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'});
const json=(body:unknown,status=200,origin='null')=>new Response(JSON.stringify(body),{status,headers:{...cors(origin),'Content-Type':'application/json'}});
Deno.serve(async req=>{
 const origin=req.headers.get('Origin')||'null'; const allowed=Deno.env.get('APP_ORIGIN')||'';
 if(req.method==='OPTIONS') return new Response('ok',{headers:cors(allowed)});
 if(req.method!=='POST'||origin!==allowed)return json({error:'unavailable'},403,allowed);
 try{
  const url=Deno.env.get('SUPABASE_URL')!, anon=Deno.env.get('SUPABASE_ANON_KEY')!, key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const userClient=createClient(url,anon,{global:{headers:{Authorization:req.headers.get('Authorization')||''}},auth:{persistSession:false}});
  const {data:{user},error}=await userClient.auth.getUser(); if(error||!user?.email_confirmed_at)return json({error:'unauthorized'},401,allowed);
  const b=await req.json();
  const captchaSecret=Deno.env.get('TURNSTILE_SECRET_KEY');
  if(!captchaSecret||typeof b.captchaToken!=='string'||b.captchaToken.length>2048)return json({error:'captcha_required'},400,allowed);
  const captcha=await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({secret:captchaSecret,response:b.captchaToken})});
  const captchaResult=await captcha.json();
  if(!captcha.ok||!captchaResult.success||captchaResult.hostname!==new URL(allowed).hostname)return json({error:'captcha_failed'},400,allowed);
  const categories=['bug','account','event','safety','other'];
  if(!categories.includes(b.category)||typeof b.subject!=='string'||b.subject.trim().length<4||b.subject.trim().length>120||typeof b.details!=='string'||b.details.trim().length<20||b.details.trim().length>4000)return json({error:'invalid_request'},400,allowed);
  const follow=b.contactAllowed===true, attach=b.attachAccount===true;
  const name=follow&&typeof b.contactName==='string'?b.contactName.trim().slice(0,80)||null:null;
  const email=follow&&typeof b.contactEmail==='string'&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(b.contactEmail.trim())?b.contactEmail.trim().toLowerCase().slice(0,254):null;
  if(follow&&!email)return json({error:'contact_email_required'},400,allowed);
  const admin=createClient(url,key,{auth:{persistSession:false}});
  const {data:ok,error:qerr}=await admin.rpc('consume_support_submit_quota',{p_user_id:user.id}); if(qerr||!ok)return json({error:'rate_limited'},429,allowed);
  const {data:ticket,error:insertErr}=await admin.from('support_requests').insert({requester_user_id:attach?user.id:null,category:b.category,subject:b.subject.trim(),details:b.details.trim(),contact_name:name,contact_email:email,contact_allowed:follow}).select('id').single();
  if(insertErr)throw insertErr; return json({ok:true,ticketId:ticket.id},200,allowed);
 }catch{return json({error:'unavailable'},400,allowed)}
});
