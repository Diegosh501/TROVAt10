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

Deno.serve(async req => {
  const origin = req.headers.get('Origin') || '';
  if (!allowedOrigin || origin !== allowedOrigin) return new Response(null, { status: 403 });
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, origin);
  if (!req.headers.get('Content-Type')?.toLowerCase().includes('application/json')) return json({ error: 'invalid_request' }, 415, origin);
  const declaredLength = Number(req.headers.get('Content-Length') || 0);
  if (declaredLength > 4096) return json({ error: 'invalid_request' }, 413, origin);

  try {
    if (missingConfig('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'TURNSTILE_SECRET_KEY', 'TWILIO_VERIFY_SERVICE_SID', 'TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN')) {
      return json({ error: 'verification_unavailable' }, 503, origin);
    }
    const raw = await req.text();
    if (raw.length > 4096) return json({ error: 'invalid_request' }, 413, origin);
    const body = JSON.parse(raw);
    const { phone, captchaToken } = body;
    if (typeof phone !== 'string' || !/^\+[1-9]\d{7,14}$/.test(phone) || typeof captchaToken !== 'string' || captchaToken.length < 10 || captchaToken.length > 2048) {
      return json({ error: 'invalid_request' }, 400, origin);
    }

    const auth = req.headers.get('Authorization') || '';
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const userClient = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user?.email_confirmed_at) return json({ error: 'unauthorized' }, 401, origin);

    const captchaSecret = Deno.env.get('TURNSTILE_SECRET_KEY')!;
    const captchaResponse = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ secret: captchaSecret, response: captchaToken }),
      signal: AbortSignal.timeout(10000),
    });
    const captcha = await captchaResponse.json();
    if (!captchaResponse.ok || captcha?.success !== true || captcha?.hostname !== new URL(allowedOrigin).hostname) {
      return json({ error: 'verification_unavailable' }, 400, origin);
    }

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
    const { data: permitted, error: quotaError } = await admin.rpc('consume_phone_otp_quota', { p_user_id: user.id });
    if (quotaError || permitted !== true) return json({ error: 'try_later' }, 429, origin);
    const { error: pendingError } = await admin.from('phone_otp_pending').upsert({
      user_id: user.id,
      phone,
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    });
    if (pendingError) return json({ error: 'verification_unavailable' }, 503, origin);

    const sid = Deno.env.get('TWILIO_VERIFY_SERVICE_SID')!;
    const account = Deno.env.get('TWILIO_ACCOUNT_SID')!;
    const token = Deno.env.get('TWILIO_AUTH_TOKEN')!;
    const twilio = await fetch(`https://verify.twilio.com/v2/Services/${encodeURIComponent(sid)}/Verifications`, {
      method: 'POST',
      headers: { Authorization: `Basic ${btoa(`${account}:${token}`)}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ To: phone, Channel: 'sms' }),
      signal: AbortSignal.timeout(10000),
    });
    if (!twilio.ok) {
      await admin.from('phone_otp_pending').delete().eq('user_id', user.id);
      return json({ error: 'verification_unavailable' }, 503, origin);
    }
    return json({ sent: true }, 200, origin);
  } catch {
    return json({ error: 'verification_unavailable' }, 400, origin);
  }
});
