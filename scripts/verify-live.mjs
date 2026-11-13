import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
// A version preview can use its own public configuration without replacing
// the production candidate. Compare against the directory actually uploaded.
const publicDir=path.resolve(root,process.argv[4]||'TROVAT1O-Cloudflare-Deploy/public');
const base=new URL(process.argv[2]||'https://trovato.diegolucentedesign.workers.dev/');
if(base.protocol!=='https:')throw new Error('HTTPS required');
const reportPath=path.resolve(root,process.argv[3]||'output/audit/2026-11-11/live-verification.json');
async function walk(dir){const rows=await fs.readdir(dir,{withFileTypes:true});const files=[];for(const row of rows){const target=path.join(dir,row.name);if(row.isDirectory())files.push(...await walk(target));else if(!row.name.startsWith('_'))files.push(target)}return files}
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const results=await Promise.all((await walk(publicDir)).map(async file=>{
 const relative=path.relative(publicDir,file).split(path.sep).join('/');
 const response=await fetch(new URL(relative,base),{headers:{'Cache-Control':'no-cache'},signal:AbortSignal.timeout(15000)});
 const actual=new Uint8Array(await response.arrayBuffer()),expected=await fs.readFile(file);
 return {file:relative,status:response.status,sha256:hash(actual),matches:response.status===200&&hash(actual)===hash(expected)};
}));
const home=await fetch(base,{headers:{'Cache-Control':'no-cache'},signal:AbortSignal.timeout(15000)});
const securityHeaders=Object.fromEntries(['content-security-policy','strict-transport-security','x-frame-options','x-content-type-options','referrer-policy','permissions-policy','x-robots-tag'].map(k=>[k,home.headers.get(k)]));
const headersPass=securityHeaders['x-frame-options']==='DENY'&&securityHeaders['strict-transport-security']?.includes('31536000')&&securityHeaders['content-security-policy']?.includes("frame-ancestors 'none'");
const privatePaths=['/.env','/.git/config','/supabase/schema.sql','/tests/local-postgres.cjs','/output/handoff/LAST-CHECKPOINT.json'];
const privateProbes=await Promise.all(privatePaths.map(async relative=>{
 const response=await fetch(new URL(relative,base),{redirect:'manual',signal:AbortSignal.timeout(15000)});
 await response.arrayBuffer();
 return {path:relative,status:response.status,denied:response.status===404||response.status===403};
}));
const release=JSON.parse(await fs.readFile(path.join(publicDir,'release.json'),'utf8'));
const report={checkedAt:new Date().toISOString(),url:base.href,release,homeStatus:home.status,securityHeaders,headersPass,files:results,privateProbes,passed:home.status===200&&headersPass&&results.every(r=>r.matches)&&privateProbes.every(r=>r.denied)};
await fs.mkdir(path.dirname(reportPath),{recursive:true});
await fs.writeFile(reportPath,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({passed:report.passed,version:release.version,mode:release.mode,assets:results.length,matching:results.filter(r=>r.matches).length,headersPass,privatePathsDenied:privateProbes.filter(r=>r.denied).length}));
if(!report.passed){console.error(JSON.stringify(results.filter(r=>!r.matches)));process.exitCode=1}
