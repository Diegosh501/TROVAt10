const CACHE='trovatio-shell-2026-11-13-v21';
const SHELL=['./','./index.html','./index-v2.html','./politiche.html','./privacy.html','./termini.html','./cookie.html','./site.webmanifest','./config.js','./assets/brand/favicon.png','./assets/brand/trovat1o-logo.png','./assets/brand/apple-touch-icon.png','./assets/brand/icon-192.png','./assets/brand/icon-512.png'];
function notificationPath(value){const fallback='/index.html?notifications=1';if(typeof value!=='string'||!value.startsWith('/'))return fallback;try{const url=new URL(value,self.location.origin);return url.origin===self.location.origin?url.pathname+url.search+url.hash:fallback}catch{return fallback}}
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('trovatio-shell-')&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
const SHELL_PATHS=new Set(SHELL.map(path=>new URL(path,self.location.origin+'/').pathname));
const PAGE_PATHS=new Set([...SHELL_PATHS].filter(path=>path==='/'||path.endsWith('.html')));
function cacheable(response){return response.ok&&!/\b(no-store|private)\b/i.test(response.headers.get('Cache-Control')||'')}
self.addEventListener('fetch',event=>{const request=event.request,url=new URL(request.url);if(request.method!=='GET'||url.origin!==self.location.origin||request.headers?.has?.('Authorization')||request.cache==='no-store')return;
 if(request.mode==='navigate'){const key=PAGE_PATHS.has(url.pathname)?url.pathname:'/index.html';event.respondWith(fetch(request).then(async response=>{if(PAGE_PATHS.has(url.pathname)&&cacheable(response)){const cache=await caches.open(CACHE);await cache.put(key,response.clone())}return response}).catch(()=>caches.match(key).then(response=>response||caches.match('./index.html'))));return}
 // Only public app-shell files are cached. Future same-origin API endpoints,
 // authenticated requests and URLs containing tokens never enter this cache.
 if(!SHELL_PATHS.has(url.pathname)||url.search)return;
 event.respondWith(caches.match(url.pathname).then(hit=>hit||fetch(request).then(async response=>{if(cacheable(response)){const cache=await caches.open(CACHE);await cache.put(url.pathname,response.clone())}return response})))
});
self.addEventListener('push',event=>{let payload={};try{payload=event.data?.json()||{}}catch{}const title=typeof payload.title==='string'?payload.title:'TROVAT1O · aggiornamento';const body=typeof payload.body==='string'?payload.body:'Hai un aggiornamento sulla partita.';const path=notificationPath(payload.url);event.waitUntil(self.registration.showNotification(title,{body,icon:'/assets/brand/icon-192.png',badge:'/assets/brand/favicon.png',tag:typeof payload.tag==='string'?payload.tag:undefined,data:{path}}))});
self.addEventListener('notificationclick',event=>{event.notification.close();const target=new URL(notificationPath(event.notification.data?.path),self.location.origin).href;event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(clients=>{const client=clients.find(c=>new URL(c.url).origin===self.location.origin);if(client)return client.navigate(target).then(()=>client.focus());return self.clients.openWindow(target)}))});
