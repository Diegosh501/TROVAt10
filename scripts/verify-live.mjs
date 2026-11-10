import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const publicDir=path.join(root,'TROVAT1O-Cloudflare-Deploy/public');
const base=new URL(process.argv[2]||'https://trovato.diegolucentedesign.workers.dev/');
if(base.protocol!=='https:')throw new Error('HTTPS required');
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
const report={checkedAt:new Date().toISOString(),url:base.href,homeStatus:home.status,securityHeaders,headersPass,files:results,passed:home.status===200&&headersPass&&results.every(r=>r.matches)};
await fs.mkdir(path.join(root,'output/audit/2026-11-10'),{recursive:true});
await fs.writeFile(path.join(root,'output/audit/2026-11-10/live-verification.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({passed:report.passed,assets:results.length,matching:results.filter(r=>r.matches).length,headersPass}));
if(!report.passed){console.error(JSON.stringify(results.filter(r=>!r.matches)));process.exitCode=1}
