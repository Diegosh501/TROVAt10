import * as webpush from 'npm:web-push@4.0.0';
import {createClient} from 'npm:@supabase/supabase-js@2.119.0';
import {createPushDispatcher} from '../_shared/push-core.ts';
const env=(name:string)=>Deno.env.get(name)||'';
const db=createClient(env('SUPABASE_URL')||'https://unconfigured.invalid',env('SUPABASE_SERVICE_ROLE_KEY')||'unconfigured',
  {auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(createPushDispatcher({enabled:env('PUSH_ENABLED')==='true',cronSecret:env('PUSH_CRON_SECRET'),
  publicKey:env('VAPID_PUBLIC_KEY'),privateKey:env('VAPID_PRIVATE_KEY'),subject:env('VAPID_SUBJECT'),origin:env('APP_ORIGIN')},
  {rpc:async(name,args)=>{const {data,error}=await db.rpc(name,args);if(error)throw new Error('push_transport_failed');return data},
   prepare:(subscription,payload,options)=>webpush.generateRequestDetails(subscription,payload,options),
   send:details=>fetch(details.endpoint,{method:'POST',headers:details.headers,body:details.body,redirect:'error',signal:AbortSignal.timeout(8000)})}));
