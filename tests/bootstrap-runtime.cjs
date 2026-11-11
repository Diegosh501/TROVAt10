const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync('index.html','utf8');
const source=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)][0][1];
function boot(config={},failSdk=false){const requested=[];const context={TROVAT1O_CONFIG:config,Promise,Error,document:{createElement:tag=>({tag}),head:{appendChild:item=>{requested.push(item);if(item.tag==='script'){if(failSdk&&item.src.includes('supabase-js'))item.onerror();else item.onload()}}}}};context.window=context;vm.createContext(context);vm.runInContext(source,context);return {context,requested}}
const cloud={onlineReady:true,supabaseUrl:'https://project.supabase.co',supabaseAnonKey:'public-test',publicBaseUrl:'https://app.example.test'};
let n=0;async function check(label,fn){await fn();console.log('PASS '+(++n)+': '+label)}
(async()=>{
 await check('Google-only cloud loads Supabase without any CAPTCHA key',async()=>{const b=boot(cloud);await b.context.TROVAT1O_EXTERNAL_READY;assert.equal(b.requested.length,1);assert.match(b.requested[0].src,/@supabase\/supabase-js@2\.119\.0/);assert.match(b.requested[0].integrity,/^sha384-/)});
 await check('preview and incomplete cloud never load third-party account libraries',async()=>{for(const c of [{...cloud,onlineReady:false},{...cloud,supabaseAnonKey:''},{...cloud,publicBaseUrl:''}]){const b=boot(c);await b.context.TROVAT1O_EXTERNAL_READY;assert.equal(b.requested.length,0)}});
 await check('CAPTCHA is loaded only when configured separately',async()=>{const b=boot({...cloud,turnstileSiteKey:'public-site-key'});await b.context.TROVAT1O_EXTERNAL_READY;assert.equal(b.requested.length,2);assert.ok(b.requested.some(x=>x.src.includes('challenges.cloudflare.com')))});
 await check('failed account library rejects readiness rather than reporting success',async()=>{const b=boot(cloud,true);await assert.rejects(b.context.TROVAT1O_EXTERNAL_READY,/external script unavailable/)});
 await check('map library stays lazy and loads once when requested',async()=>{const b=boot(cloud);await b.context.TROVAT1O_EXTERNAL_READY;assert.ok(!b.requested.some(x=>String(x.src).includes('leaflet')));assert.equal(await b.context.TROVAT1O_LOAD_LEAFLET(),true);const count=b.requested.length;await b.context.TROVAT1O_LOAD_LEAFLET();assert.equal(b.requested.length,count);assert.ok(b.requested.some(x=>x.tag==='link'&&x.integrity));assert.ok(b.requested.some(x=>x.tag==='script'&&x.src.includes('leaflet')&&x.integrity))});
 await check('offline preview never requests map assets',async()=>{const b=boot({onlineReady:false});assert.equal(await b.context.TROVAT1O_LOAD_LEAFLET(),false);assert.equal(b.requested.length,0)});
 console.log('PASS: '+n+' actual external-library bootstrap scenarios.');
})().catch(e=>{console.error(e);process.exitCode=1});
