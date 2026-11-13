'use strict';
// Authenticated encryption for private backup files; never a public app asset.
const fs=require('node:fs'),fsp=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const {pipeline,finished}=require('node:stream/promises'),{Readable}=require('node:stream');
const MAGIC=Buffer.from('T1OBKP01'),HEADER=20,TAG=16;
function keyCheck(key){if(!Buffer.isBuffer(key)||key.length!==32)throw Error('A 32-byte backup key is required')}
function seal(bytes,key){keyCheck(key);const iv=crypto.randomBytes(12),c=crypto.createCipheriv('aes-256-gcm',key,iv);c.setAAD(MAGIC);return Buffer.concat([MAGIC,iv,c.update(bytes),c.final(),c.getAuthTag()])}
function open(bytes,key){keyCheck(key);if(!Buffer.isBuffer(bytes)||bytes.length<HEADER+TAG||!bytes.subarray(0,8).equals(MAGIC))throw Error('Invalid backup envelope');try{const d=crypto.createDecipheriv('aes-256-gcm',key,bytes.subarray(8,HEADER));d.setAAD(MAGIC);d.setAuthTag(bytes.subarray(-TAG));return Buffer.concat([d.update(bytes.subarray(HEADER,-TAG)),d.final()])}catch{throw Error('Backup authentication failed')}}
async function privateDirectory(dir){const s=await fsp.stat(dir);if(!s.isDirectory()||(s.mode&0o077)!==0||process.getuid&&s.uid!==process.getuid())throw Error('Use a private directory owned by the current user (mode 700)')}
async function readKey(file){const handle=await fsp.open(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);try{const s=await handle.stat();if(!s.isFile()||(s.mode&0o077)!==0||process.getuid&&s.uid!==process.getuid())throw Error('Use a private regular key file owned by the current user (mode 600)');const key=await handle.readFile();keyCheck(key);return key}finally{await handle.close()}}
async function keygen(file){await privateDirectory(path.dirname(path.resolve(file)));const key=crypto.randomBytes(32);try{await fsp.writeFile(file,key,{flag:'wx',mode:0o600})}finally{key.fill(0)}}
async function fileOperation(mode,input,output,key){
 keyCheck(key);const source=path.resolve(input),destination=path.resolve(output);if(source===destination)throw Error('Input and output must differ');await privateDirectory(path.dirname(destination));
 const meta=await fsp.lstat(source);if(!meta.isFile()||meta.isSymbolicLink())throw Error('Use a regular input file');
 // A random exclusive temporary file is published only after the full operation
 // succeeds. Failed authentication never exposes a partial plaintext output.
 const temp=path.join(path.dirname(destination),'.trovat1o-'+crypto.randomBytes(12).toString('hex')+'.tmp');let created=false;
 try{
  let transform,read;
  if(mode==='encrypt'){const iv=crypto.randomBytes(12);transform=crypto.createCipheriv('aes-256-gcm',key,iv);transform.setAAD(MAGIC);read=fs.createReadStream(source);const out=fs.createWriteStream(temp,{flags:'wx',mode:0o600});created=true;out.write(Buffer.concat([MAGIC,iv]));await pipeline(read,transform,out,{end:false});out.end(transform.getAuthTag());await finished(out)}
  else if(mode==='decrypt'){
   if(meta.size<HEADER+TAG)throw Error('Invalid backup envelope');const file=await fsp.open(source,'r'),header=Buffer.alloc(HEADER),tag=Buffer.alloc(TAG);
   try{await file.read(header,0,HEADER,0);await file.read(tag,0,TAG,meta.size-TAG)}finally{await file.close()}
   if(!header.subarray(0,8).equals(MAGIC))throw Error('Invalid backup envelope');transform=crypto.createDecipheriv('aes-256-gcm',key,header.subarray(8));transform.setAAD(MAGIC);transform.setAuthTag(tag);
   read=meta.size===HEADER+TAG?Readable.from([]):fs.createReadStream(source,{start:HEADER,end:meta.size-TAG-1});const out=fs.createWriteStream(temp,{flags:'wx',mode:0o600});created=true;
   try{await pipeline(read,transform,out)}catch{throw Error('Backup authentication or file operation failed')}
  }else throw Error('Choose encrypt or decrypt');
  // Hard-link publication fails atomically if the destination already exists.
  await fsp.link(temp,destination);
 }finally{if(created)await fsp.unlink(temp).catch(()=>{})}
}
module.exports={seal,open,fileOperation,keygen,readKey};
if(require.main===module)(async()=>{const[mode,...args]=process.argv.slice(2);if(mode==='keygen'&&args.length===1){await keygen(args[0]);console.log('Private backup key created. Keep it separate from backups.');return}if(!['encrypt','decrypt'].includes(mode)||args.length!==3)throw Error('Usage: keygen <key-file> OR encrypt|decrypt <input> <output> <key-file>');const key=await readKey(args[2]);try{await fileOperation(mode,args[0],args[1],key);console.log('Private backup file completed; existing files were not overwritten.')}finally{key.fill(0)}})().catch(error=>{console.error(error.message);process.exitCode=1});
