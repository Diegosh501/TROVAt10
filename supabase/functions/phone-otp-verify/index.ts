import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.0';

const allowedOrigin = Deno.env.get('APP_ORIGIN') || '';
const corsHeaders = (origin: string) => ({
  'Access-Control-Allow-Origin': origin === allowedOrigin ? allowedOrigin : 'null',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '600',
  'Vary': 'Origin',
});
const json = (body: unknown, status = 200, origin = '') => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders(origin), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});
const missingConfig = (...names: string[]) => names.some(name => !Deno.env.get(name));

async function phoneHash(phone: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const bytes = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(phone)));
  return [...bytes].map(x => x.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async req => {
  const origin = req.headers.get('Origin') || '';
  if (!allowedOrigin || origin !== allowedOrigin) return new Response(null, { status: 403 });
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);
  if (!req.headers.get('Content-Type')?.toLowerCase().includes('application/json')) return json({ error: 'invalid_request' }, 415, origin);
  const declaredLength = Number(req.headers.get('Content-Length') || 0);
  if (declaredLength > 2048) return json({ error: 'invalid_request' }, 413, origin);

  try {
    if (missingConfig('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'TWILIO_VERIFY_SERVICE_SID', 'TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'PHONE_HASH_SECRET')) {
      return json({ error: 'verification_unavailable' }, 503, origin);
    }
    const raw = await req.text();
    if (raw.length > 2048) return json({ error: 'invalid_request' }, 413, origin);
    const body = JSON.parse(raw);
    const code = body?.token;
    if (typeof code !== 'string' || !/^\d{6,8}$/.test(code)) return json({ error: 'invalid_code' }, 400, origin);

    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const auth = req.headers.get('Authorization') || '';
    const userClient = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user?.email_confirmed_at) return json({ error: 'unauthorized' }, 401, origin);

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
    const { data: pending, error: pendingError } = await admin.from('phone_otp_pending')
      .select('phone').eq('user_id', user.id).gt('expires_at', new Date().toISOString()).maybeSingle();
    if (pendingError || !pending?.phone) return json({ error: 'verification_unavailable' }, 400, origin);
    const { data: permitted, error: quotaError } = await admin.rpc('consume_phone_otp_check', { p_user_id: user.id });
    if (quotaError || permitted !== true) return json({ error: 'try_later' }, 429, origin);

    const sid = Deno.env.get('TWILIO_VERIFY_SERVICE_SID')!;
    const account = Deno.env.get('TWILIO_ACCOUNT_SID')!;
    const twilioToken = Deno.env.get('TWILIO_AUTH_TOKEN')!;
    const check = await fetch(`https://verify.twilio.com/v2/Services/${encodeURIComponent(sid)}/VerificationCheck`, {
      method: 'POST',
      headers: { Authorization: `Basic ${btoa(`${account}:${twilioToken}`)}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ To: pending.phone, Code: code }),
      signal: AbortSignal.timeout(10000),
    });
    const result = await check.json().catch(() => null);
    if (!check.ok || result?.status !== 'approved') return json({ verified: false }, 400, origin);

    const hashed = await phoneHash(pending.phone, Deno.env.get('PHONE_HASH_SECRET')!);
    const { data: completed, error: completeError } = await admin.rpc('complete_phone_verification', {
      p_user_id: user.id,
      p_phone_hash: hashed,
    });
    if (completeError || completed !== true) return json({ error: 'phone_already_used_or_unavailable' }, 409, origin);
    return json({ verified: true }, 200, origin);
  } catch {
    return json({ error: 'verification_unavailable' }, 400, origin);
  }
});
