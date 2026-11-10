import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.0';
const origin=Deno.env.get('APP_ORIGIN')||''; const cors={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors}); if(req.method!=='POST'||req.headers.get('Origin')!==origin)return json({error:'unavailable'},403);
 try{
  const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const auth=req.headers.get('Authorization')||''; const client=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:{user},error}=await client.auth.getUser(); if(error||!user?.email_confirmed_at||user.app_metadata?.role!=='admin')return json({error:'unauthorized'},401);
  const jwt=auth.replace(/^Bearer\s+/i,'');
  const {data:claims,error:claimsError}=await client.auth.getClaims(jwt);
  if(claimsError||claims?.claims?.aal!=='aal2')return json({error:'mfa_required'},403);
  const admin=createClient(url,key,{auth:{persistSession:false}}); const body=await req.json();
  if(body.action==='dashboard'){
   const [users,verified,events,activeEvents,pending,done,cancelled,supportNew,supportOpen,reports,signups]=await Promise.all([
    admin.from('profiles').select('id',{count:'exact',head:true}),admin.from('profiles').select('id',{count:'exact',head:true}).not('phone_verified_at','is',null),
    admin.from('events').select('id',{count:'exact',head:true}),admin.from('events').select('id',{count:'exact',head:true}).in('status',['scheduled','in_progress']),
    admin.from('event_members').select('event_id',{count:'exact',head:true}).eq('state','pending'),admin.from('events').select('id',{count:'exact',head:true}).eq('status','completed'),admin.from('events').select('id',{count:'exact',head:true}).eq('status','cancelled'),
    admin.from('support_requests').select('id',{count:'exact',head:true}).eq('status','new'),admin.from('support_requests').select('id',{count:'exact',head:true}).in('status',['new','in_progress','waiting_user']),admin.from('player_reports').select('id',{count:'exact',head:true}).eq('state','received'),admin.from('profiles').select('id',{count:'exact',head:true}).gte('created_at',new Date(Date.now()-30*86400000).toISOString())
   ]);
   const counts=[users,verified,events,activeEvents,pending,done,cancelled,supportNew,supportOpen,reports,signups]; if(counts.some(x=>x.error))return json({error:'metrics_unavailable'},503);
   let usage:{available:boolean;observedAt:string|null;counts:Record<string,number>|null}={available:false,observedAt:null,counts:null};
   const token=Deno.env.get('SUPABASE_MANAGEMENT_API_TOKEN'),ref=Deno.env.get('SUPABASE_PROJECT_REF');
   if(token&&ref){try{const resp=await fetch(`https://api.supabase.com/v1/projects/${encodeURIComponent(ref)}/analytics/endpoints/usage.api-counts`,{headers:{Authorization:`Bearer ${token}`}});if(resp.ok){const data=await resp.json();const rows=Array.isArray(data.result)?data.result:[];const latest=rows.at(-1);if(latest){const {timestamp,...values}=latest;usage={available:true,observedAt:timestamp||null,counts:Object.fromEntries(Object.entries(values).map(([k,v])=>[k,Number(v)]))}}}}catch{}}
   return json({updatedAt:new Date().toISOString(),metrics:{totalUsers:users.count||0,verifiedPhones:verified.count||0,totalEvents:events.count||0,activeEvents:activeEvents.count||0,pendingJoins:pending.count||0,completedEvents:done.count||0,cancelledEvents:cancelled.count||0,newTickets:supportNew.count||0,openTickets:supportOpen.count||0,openReports:reports.count||0,signups30d:signups.count||0},usage});
  }
  if(body.action==='tickets'){
   let q=admin.from('support_requests').select('id,category,subject,details,contact_name,contact_email,contact_allowed,status,admin_reply,created_at,updated_at',{count:'exact'});
   if(typeof body.query==='string'&&body.query.trim())q=q.textSearch('search_document',body.query.trim().slice(0,100),{type:'websearch',config:'simple'});
   if(['new','in_progress','waiting_user','resolved','closed'].includes(body.status))q=q.eq('status',body.status);
   if(['bug','account','event','safety','other'].includes(body.category))q=q.eq('category',body.category);
   q=q.order(body.sort==='name'?'contact_name':'created_at',{ascending:body.sort==='name',nullsFirst:false}).range(0,49);const {data,error,count}=await q;if(error)throw error;return json({tickets:data||[],total:count||0});
  }
  if(body.action==='update-ticket'){
   if(typeof body.id!=='string'||!['new','in_progress','waiting_user','resolved','closed'].includes(body.status)||typeof body.reply!=='string'||body.reply.length>3000)return json({error:'invalid_request'},400);
   const {data:old,error:oldErr}=await admin.from('support_requests').select('status').eq('id',body.id).maybeSingle();if(oldErr||!old)return json({error:'not_found'},404);
   const {error:upErr}=await admin.from('support_requests').update({status:body.status,admin_reply:body.reply.trim()||null,updated_at:new Date().toISOString()}).eq('id',body.id);if(upErr)throw upErr;
   await admin.from('support_request_audit').insert([{ticket_id:body.id,actor_id:user.id,action:'status_changed',old_status:old.status,new_status:body.status},{ticket_id:body.id,actor_id:user.id,action:'reply_saved',old_status:old.status,new_status:body.status}]);return json({ok:true});
  }
  return json({error:'invalid_action'},400);
 }catch{return json({error:'unavailable'},400)}
});
