// Structural/security smoke checks for the single-page TROVAT1O release.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.join(__dirname,'..'),html=fs.readFileSync(path.join(root,'index.html'),'utf8'),script=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(x=>x[1]).join('\n');
new vm.Script(script,{filename:'index.html:inline-script'});
assert.match(html,/<section id="eventsTab"/);assert.match(html,/<section id="historyTab"/);assert.match(html,/<section id="adminTab"/,'admin is integrated into the same app page');
assert.match(html,/id="adminNav"/);assert.match(script,/onlineReady!==true\|\|authSession\?\.user\?\.app_metadata\?\.role==='admin'/,'console visibility is local demo or admin role only');
assert.match(script,/currentLevel!=='aal2'/,'online console requires MFA');assert.match(script,/functions\.invoke\('admin-console'/,'live dashboard uses protected backend');assert.match(script,/Numeri e ticket inventati/,'offline numbers are explicitly labelled as fake');
assert.match(html,/id="adminSearch"[\s\S]*id="adminCategory"[\s\S]*id="adminStatus"[\s\S]*id="adminSort"/,'integrated support queue has search and filters');
assert.match(script,/contactAllowed:\$\('supportContactAllowed'\)\.checked/);assert.match(script,/attachAccount:\$\('supportAttachAccount'\)\.checked/);assert.match(script,/functions\.invoke\('support-request'/,'support submission uses backend');
assert.match(script,/support\.trovat10@gmail\.com/);assert.match(script,/389564728222/);
const edge=fs.readFileSync(path.join(root,'supabase/functions/admin-console/index.ts'),'utf8'),support=fs.readFileSync(path.join(root,'supabase/functions/support-request/index.ts'),'utf8'),schema=fs.readFileSync(path.join(root,'supabase/schema.sql'),'utf8');
assert.match(support,/contactAllowed===true/);assert.match(support,/attachAccount===true/);
assert.match(script,/function createDemoAccount\(\)/);assert.match(script,/function readDemoProfile\(\)/);assert.match(script,/privateRecent>=1/);assert.match(script,/if\(isPublic&&!profile\.phoneVerified&&!profile\.demo\)/,'phone verification remains required online while local demo publishing can be tested');assert.match(script,/function makeEventUrl\(e\)/,'public and private event URL generation is available');
assert.match(schema,/create_event_with_policy/);assert.match(schema,/weekly_private_event_limit/);assert.match(schema,/phone_verification_required/);assert.match(schema,/revoke all on public\.events from anon,authenticated/);assert.match(schema,/guard_event_update_trigger/);assert.match(schema,/update_event_with_policy/);
assert.match(edge,/app_metadata\?\.role!=='admin'/);assert.match(edge,/claims\?\.claims\?\.aal!=='aal2'/);assert.match(edge,/analytics\/endpoints\/usage\.api-counts/);assert.match(edge,/Access-Control-Allow-Origin/);assert.match(edge,/\.range\(0,49\)/);
assert.match(support,/siteverify/);assert.match(support,/consume_support_submit_quota/);assert.match(schema,/revoke all on public\.support_requests from anon,authenticated/i);assert.match(schema,/search_document tsvector generated/i);
assert.equal(fs.readFileSync(path.join(root,'config.js'),'utf8').includes('onlineReady: false'),true,'cloud remains safely disabled pending setup');
assert.doesNotMatch(html,/SUPABASE_SERVICE_ROLE_KEY|stripe_secret/i,'no server secrets are embedded in the page');
console.log('PASS: single-page navigation, offline admin preview, online admin role/MFA gate, support privacy controls, server-only ticket access, analytics and safe cloud defaults.');
