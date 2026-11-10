const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const schema = fs.readFileSync(path.join(root, 'supabase/schema.sql'), 'utf8');
const otpStart = fs.readFileSync(path.join(root, 'supabase/functions/phone-otp-start/index.ts'), 'utf8');
const otpVerify = fs.readFileSync(path.join(root, 'supabase/functions/phone-otp-verify/index.ts'), 'utf8');
const config = fs.readFileSync(path.join(root, 'config.js'), 'utf8');
let passed = 0;
function check(label, condition) {
  if (!condition) throw new Error(`FAIL: ${label}`);
  passed += 1;
  console.log(`PASS ${passed}: ${label}`);
}

check('cloud mode stays disabled until providers and integration are verified', /onlineReady:\s*false/.test(config));
check('public client configuration contains no service-role or provider secrets', !/service_role|TWILIO_AUTH_TOKEN|TURNSTILE_SECRET_KEY|PHONE_HASH_SECRET|STRIPE_SECRET_KEY/i.test(config));
check('all application tables enable row-level security', [
  'profiles','events','event_members','event_host_contacts','event_invites','pin_suggestions','player_reports',
  'support_requests','support_request_audit','support_submit_quota','subscriptions','verified_phones','phone_otp_quota','phone_otp_pending'
].every(table => new RegExp(`alter table public\\.${table} enable row level security`, 'i').test(schema)));
check('event rows cannot be read directly; the safe feed RPC is the only read path', /revoke all on public\.events from anon,authenticated/i.test(schema) && /events_deny_direct_client_access on public\.events for all to anon,authenticated using \(false\)/i.test(schema) && /grant execute on function public\.event_feed\(\) to anon,authenticated/i.test(schema));
check('event feed exposes approved counts and masks pending invite location', /create or replace function public\.event_feed\(\)/i.test(schema) && /Luogo comunicato dopo l’ammissione/.test(schema));
check('private event invite lookup masks the exact field location', /select e\.id,e\.title,e\.format,e\.kind,e\.starts_at,'Luogo comunicato dopo l’ammissione'/i.test(schema));
check('private invite table stores only token hashes and compares a SHA-256 digest', /token_hash bytea not null unique/i.test(schema) && /extensions\.digest\(pg_catalog\.convert_to\(p_invite_token,'UTF8'\),'sha256'\)/i.test(schema));
check('direct membership writes are revoked and membership changes use narrow RPCs', /revoke insert,update,delete on public\.event_members from anon,authenticated/i.test(schema) && /function public\.(request_event_join|manage_event_member|leave_event)/i.test(schema));
check('direct report submissions are revoked and rate-limited through a function', /revoke insert on public\.player_reports from anon,authenticated/i.test(schema) && /report_rate_limit/i.test(schema));
check('event creation enforces confirmed email, Host role, visibility and server-side limits', /public\.is_email_confirmed\(\)/i.test(schema) && /host_role_required/i.test(schema) && /weekly_private_event_limit/i.test(schema) && /active_event_limit/i.test(schema));
check('service-only OTP completion updates phone state transactionally', /function public\.complete_phone_verification\(uuid,text\)/i.test(schema) && /grant execute on function public\.complete_phone_verification\(uuid,text\) to service_role/i.test(schema));
const joinStart = schema.indexOf('create or replace function public.request_event_join');
const joinEnd = schema.indexOf('revoke all on function public.request_event_join', joinStart);
const joinFunction = schema.slice(joinStart, joinEnd);
check('confirmed-email private invite joins do not need paid SMS; public joins still require phone verification', /public\.is_email_confirmed\(\)/i.test(joinFunction) && /v_event\.visibility='public' and not coalesce\(v_phone_verified,false\)/i.test(joinFunction) && /v_event\.visibility='private' and not exists/i.test(joinFunction));
check('private invite tokens expire after the event and cannot be rotated once it starts', /p_starts_at\+interval '1 day'/i.test(schema) && /v_starts_at\+interval '1 day'/i.test(schema) && /e\.status='scheduled'/i.test(schema));
check('OTP endpoints reject wildcard CORS and require the exact configured app origin', !/Access-Control-Allow-Origin['"]\s*:\s*['"]\*['"]/.test(otpStart+otpVerify) && /origin !== allowedOrigin/.test(otpStart) && /origin !== allowedOrigin/.test(otpVerify));
check('OTP start validates Turnstile hostname and limits request size', /captcha\?\.hostname !== new URL\(allowedOrigin\)\.hostname/.test(otpStart) && /raw\.length > 4096/.test(otpStart));
check('OTP sending and verification have separate server-side rate limits', /consume_phone_otp_quota/.test(otpStart) && /consume_phone_otp_check/.test(otpVerify) && /verify_attempts>=8/.test(schema));
check('failed SMS provider requests delete the short-lived pending phone record', /if \(!twilio\.ok\)[\s\S]{0,180}phone_otp_pending'\)\.delete\(\)/.test(otpStart));
check('final database grants apply least privilege after initial schema grants', schema.lastIndexOf('Final least-privilege pass') > schema.indexOf('grant select,insert,update,delete on public.event_members'));
check('host contacts and map pin suggestions require a confirmed email at policy and RPC boundaries', /event_contact_select_owner_or_admitted[\s\S]{0,180}public\.is_email_confirmed\(\)/i.test(schema) && /pins_insert_member[\s\S]{0,180}public\.is_email_confirmed\(\)/i.test(schema) && /function public\.event_pin_suggestions[\s\S]{0,300}public\.is_email_confirmed\(\)/i.test(schema) && /function public\.approve_event_pin[\s\S]{0,300}public\.is_email_confirmed\(\)/i.test(schema));
check('sensitive support, OTP and verified-phone tables deny direct client access explicitly', ['verified_phones','support_requests','support_request_audit','support_submit_quota','phone_otp_quota','phone_otp_pending'].every(name => new RegExp(`create policy ${name}_deny_clients on public\\.${name} for all to anon,authenticated using \\(false\\) with check \\(false\\)`, 'i').test(schema)));
check('phone and event access helper functions deny anonymous execute access', /revoke all on function public\.is_event_member\(uuid\),public\.is_event_owner\(uuid\) from anon/i.test(schema) && /revoke all on function public\.is_phone_verified\(\) from anon/i.test(schema));
check('all cloud event edits, pins and status transitions use owner-checked server RPCs', /function public\.update_event_with_policy/i.test(schema) && /function public\.update_event_pin/i.test(schema) && /function public\.update_event_status/i.test(schema) && !/supabaseClient\.from\('events'\)\.update/.test(fs.readFileSync(path.join(root, 'index.html'), 'utf8')));

console.log(`PASS: ${passed} security smoke checks.`);
