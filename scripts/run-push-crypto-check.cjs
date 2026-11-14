// Run dependency code with an explicit, non-sensitive environment. The debug
// dependency enumerates process.env, so a broad Deno env grant is used only
// inside this sanitized child. No network/read/write permission is granted.
const {spawnSync}=require('node:child_process');
const denoBin=process.argv[2];
if(!denoBin){console.error('Usage: node scripts/run-push-crypto-check.cjs /path/to/deno');process.exit(2)}
const baseEnv={PATH:process.env.PATH||'',NO_COLOR:'1'};
if(process.env.DENO_DIR)baseEnv.DENO_DIR=process.env.DENO_DIR;
const info=spawnSync(denoBin,['info','--json'],{env:baseEnv,encoding:'utf8',timeout:20000,maxBuffer:1024*1024});
if(info.status!==0){console.error('Unable to locate the Deno cache.');process.exit(1)}
let cache;try{cache=JSON.parse(info.stdout).denoDir}catch{}
if(typeof cache!=='string'||!cache){console.error('Invalid Deno cache response.');process.exit(1)}
const result=spawnSync(denoBin,['test','--cached-only','--frozen','--no-prompt','--allow-env','--lock=supabase/deno.lock','tests/push-crypto.test.ts'],
  {env:{...baseEnv,DENO_DIR:cache},encoding:'utf8',timeout:60000,maxBuffer:2*1024*1024});
process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');
if(result.error)console.error('Web Push crypto test process did not complete.');
process.exit(result.status===0?0:1);
