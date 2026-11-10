const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const app=fs.readFileSync(path.join(root,'index.html'),'utf8');
const schema=fs.readFileSync(path.join(root,'supabase/schema.sql'),'utf8');
let passed=0;
function check(label,condition){if(!condition)throw new Error('FAIL: '+label);passed++;console.log('PASS '+passed+': '+label)}

check('online mode starts without demo events or local event writes',/cloudPreview\?\[\]:read\(STORE\.events,null\)/.test(app)&&/function persistEvents\(\)\{if\(cloudMode\(\)\)\{renderEvents\(\);renderHistory\(\);return\}/.test(app));
const feedFunction=app.slice(app.indexOf('async function refreshCloudEvents()'),app.indexOf('\nfunction clearAdminView'));
check('public and authorized private events load through the safe feed RPC',/supabaseClient\.rpc\('event_feed'\)/.test(feedFunction)&&/create or replace function public\.event_feed\(\)/.test(schema));
check('event creation and private invite hashing use the atomic policy RPC',/create_event_with_policy/.test(app)&&/p_invite_token_hash/.test(app)&&/insert into public\.event_invites\(event_id,token_hash,expires_at\)/.test(schema));
check('public and private invite links resolve without exposing private location',/get_event_invitation/.test(app)&&/supabaseClient\.rpc\('get_event_invitation'/.test(app)&&/Luogo comunicato dopo l’ammissione/.test(schema));
check('join, approve, decline, remove and leave use the transactional server functions',/request_event_join/.test(app)&&/manage_event_member/.test(app)&&/leave_event/.test(app)&&/function public\.(request_event_join|manage_event_member|leave_event)/.test(schema));
check('event edits and status transitions use owner-checked transactional RPCs',/update_event_with_policy/.test(app)&&/update_event_status/.test(app)&&/function public\.update_event_with_policy/.test(schema)&&/function public\.update_event_status/.test(schema)&&/revoke all on public\.events from anon,authenticated/i.test(schema));
check('roster and organizer phone are fetched only through protected access',/event_roster/.test(app)&&/loadCloudEventContact/.test(app)&&/event_contact_select_owner_or_admitted/.test(schema));
check('reports and map suggestions are sent to server-side controlled paths',/submit_player_report/.test(app)&&/approve_event_pin/.test(app)&&/event_pin_suggestions/.test(app)&&/update_event_pin/.test(app));
check('private share export creates a bearer link only for the event owner',/ensureCloudInviteToken/.test(app)&&/create_event_invite/.test(app)&&/private_event_owner_required/.test(schema));
console.log(`PASS: ${passed} cloud integration smoke checks.`);
