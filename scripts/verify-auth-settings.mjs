// Read-only provider preflight. Never signs in, creates accounts or sends mail.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const PROJECT='nrixslotansgrtrosaof';
const scope='Provider alignment only; SMTP, CAPTCHA, delivery, Google login and MFA require separate verification.';
function invalid(code){return Object.assign(new Error(code),{code})}

// Accept the flat primitive config format used by this project, without eval.
// Reject duplicates or executable expressions instead of guessing their value.
export function parsePublicAuthConfig(source){
 const text=source.replace(/^\s*\/\/.*$/gm,'').trim();
 const assignment=/^window\.TROVAT1O_CONFIG\s*=\s*\{([\s\S]*)\}\s*;\s*$/.exec(text);
 if(!assignment)throw invalid('invalid_public_config');
 const body=assignment[1].trim(),config=Object.create(null);
 const property=/\s*(?:"([A-Za-z_$][\w$]*)"|'([A-Za-z_$][\w$]*)'|([A-Za-z_$][\w$]*))\s*:\s*(?:"((?:[^"\\\r\n]|\\["\\/bfnrt]|\\u[\da-fA-F]{4})*)"|'([^'\\\r\n]*)'|(true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?))\s*(,|$)/gy;
 let offset=0;
 while(offset<body.length){
  property.lastIndex=offset;const match=property.exec(body);
  if(!match)throw invalid('invalid_public_config');
  const key=match[1]||match[2]||match[3];
  if(Object.hasOwn(config,key))throw invalid('duplicate_config_property');
  config[key]=match[4]!==undefined?JSON.parse('"'+match[4]+'"'):match[5]!==undefined?match[5]:JSON.parse(match[6]);
  offset=property.lastIndex;
 }
 return config;
}

function publicKey(key){
 if(typeof key!=='string'||key.length>2048)return false;
 if(/^sb_publishable_[A-Za-z0-9_-]{10,}$/.test(key))return true;
 try{
  const parts=key.split('.');
  if(parts.length!==3||parts.some(p=>!/^[A-Za-z0-9_-]+$/.test(p)))return false;
  const claims=JSON.parse(Buffer.from(parts[1],'base64url').toString('utf8'));
  return claims.role==='anon'&&claims.ref===PROJECT;
 }catch{return false}
}
function endpointFor(config){
 if(typeof config.onlineReady!=='boolean'||typeof config.emailAuthEnabled!=='boolean')throw invalid('invalid_public_config');
 if(!config.onlineReady)return null;
 if(config.supabaseUrl!=='https://'+PROJECT+'.supabase.co'||!publicKey(config.supabaseAnonKey))throw invalid('invalid_public_auth_connection');
 return config.supabaseUrl+'/auth/v1/settings';
}
async function boundedJSON(response){
 if(!response.headers.get('content-type')?.toLowerCase().startsWith('application/json'))throw invalid('invalid_auth_settings_response');
 const reader=response.body?.getReader();if(!reader)throw invalid('invalid_auth_settings_response');
 const parts=[];let size=0;
 try{
  while(true){
   const {done,value}=await reader.read();if(done)break;
   size+=value.length;
   if(size>65536){await reader.cancel();throw invalid('auth_settings_response_too_large')}
   parts.push(value);
  }
 }finally{reader.releaseLock()}
 try{return JSON.parse(Buffer.concat(parts).toString('utf8'))}catch{throw invalid('invalid_auth_settings_response')}
}
export function evaluateProviderSettings(config,data){
 const ext=data?.external;
 if(!ext||typeof ext!=='object'||Array.isArray(ext)||
   !['google','email','phone','anonymous_users'].every(k=>typeof ext[k]==='boolean')||
   !Object.values(ext).every(v=>typeof v==='boolean')||
   typeof data.disable_signup!=='boolean'||typeof data.mailer_autoconfirm!=='boolean')throw invalid('invalid_auth_settings_response');
 const issues=[];
 if(!ext.google)issues.push('google_auth_unavailable');
 if(data.disable_signup)issues.push('signup_disabled');
 if(config.emailAuthEnabled&&!ext.email)issues.push('email_auth_unavailable');
 if(!config.emailAuthEnabled&&ext.email)issues.push('email_provider_exposed_while_ui_disabled');
 if(ext.email&&data.mailer_autoconfirm)issues.push('email_confirmation_disabled');
 if(ext.anonymous_users)issues.push('anonymous_auth_enabled');
 if(Object.entries(ext).some(([key,value])=>value&&!['google','email','anonymous_users'].includes(key)))issues.push('unsupported_auth_provider_enabled');
 return {status:issues.length?'blocked':'passed',passed:issues.length===0,issues,
  providers:{google:ext.google,email:ext.email,anonymous:ext.anonymous_users,
    unsupportedEnabledCount:Object.entries(ext).filter(([key,value])=>value&&!['google','email','anonymous_users'].includes(key)).length},
  signupAllowed:!data.disable_signup,emailConfirmationRequired:ext.email?!data.mailer_autoconfirm:null};
}
export async function auditPublicAuth(config,{fetchImpl=globalThis.fetch,timeoutMs=10000}={}){
 const base={checkedAt:new Date().toISOString(),project:PROJECT,requestReadOnly:true,accountsCreated:false,emailsSent:false,scope};
 try{
  const endpoint=endpointFor(config);
  if(!endpoint)return {...base,status:'skipped_preview',passed:false,issues:['cloud_config_disabled']};
  const response=await fetchImpl(endpoint,{method:'GET',headers:{apikey:config.supabaseAnonKey,Accept:'application/json'},
    redirect:'error',signal:AbortSignal.timeout(timeoutMs)});
  if(response.status!==200){await response.body?.cancel();throw invalid('auth_settings_http_error')}
  return {...base,...evaluateProviderSettings(config,await boundedJSON(response))};
 }catch(error){
  const allowed=new Set(['invalid_public_config','invalid_public_auth_connection','auth_settings_http_error','invalid_auth_settings_response','auth_settings_response_too_large']);
  return {...base,status:'unverified',passed:false,issues:[allowed.has(error?.code)?error.code:'auth_settings_unavailable']};
 }
}

async function main(){
 const args=process.argv.slice(2);
 if(args[0]==='--help'){console.log('Usage: node scripts/verify-auth-settings.mjs [public/config.js] [private-report.json]\nExit 0: provider alignment verified; 1: blocked/unverified; 2: preview skipped. No sign-in, signup, email or settings changes.');return}
 const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
 let report;
 try{
  if(args.length>2||args.some(x=>x.startsWith('--')))throw invalid('invalid_arguments');
  const config=parsePublicAuthConfig(await fs.readFile(path.resolve(root,args[0]||'TROVAT1O-Cloudflare-Deploy/public/config.js'),'utf8'));
  report=await auditPublicAuth(config);
 }catch{
  report={checkedAt:new Date().toISOString(),project:PROJECT,status:'unverified',passed:false,issues:['invalid_public_config'],requestReadOnly:true,scope};
 }
 if(args[1]){const file=path.resolve(root,args[1]);await fs.mkdir(path.dirname(file),{recursive:true});await fs.writeFile(file,JSON.stringify(report,null,2)+'\n')}
 console.log(JSON.stringify(report));
 process.exitCode=report.passed?0:report.status==='skipped_preview'?2:1;
}
if(process.argv[1]&&pathToFileURL(path.resolve(process.argv[1])).href===import.meta.url)await main();
