import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.0';

// The caller's token reaches narrow database RPCs. This endpoint has no use for
// a service-role key and cannot bypass the database's administrator checks.
const origin = Deno.env.get('APP_ORIGIN') ?? 'https://trovato.diegolucentedesign.workers.dev';
// Optional, explicit test origin only; it does not match sibling subdomains.
const testOrigin = Deno.env.get('APP_TEST_ORIGIN') ?? '';
function isHttpsOrigin(value: string): boolean {
  try {
    const url = new URL(value);
    return !value.includes('*') && url.protocol === 'https:' && url.origin === value;
  } catch { return false; }
}
const validOrigins = isHttpsOrigin(origin) && (testOrigin === '' || isHttpsOrigin(testOrigin));

async function readUsage() {
  const unavailable = { available: false, observedAt: null, counts: null };
  const token = Deno.env.get('SUPABASE_MANAGEMENT_API_TOKEN');
  const ref = Deno.env.get('SUPABASE_PROJECT_REF');
  if (!token || !ref) return unavailable;
  try {
    const response = await fetch(`https://api.supabase.com/v1/projects/${encodeURIComponent(ref)}/analytics/endpoints/usage.api-counts`, {
      headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(3500),
    });
    if (!response.ok) return unavailable;
    const body = await response.json();
    const row = Array.isArray(body.result) ? body.result.at(-1) : null;
    if (!row || typeof row !== 'object') return unavailable;
    const { timestamp, ...values } = row;
    const counts = Object.fromEntries(Object.entries(values).map(([key, value]) => [key, Number(value)]).filter(([, value]) => Number.isFinite(value)));
    return { available: true, observedAt: typeof timestamp === 'string' ? timestamp : null, counts };
  } catch { return unavailable; }
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  if (!req.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) throw new Error('invalid_request');
  const reader = req.body?.getReader();
  if (!reader) throw new Error('invalid_request');
  const parts: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 8192) { await reader.cancel(); throw new Error('request_too_large'); }
      parts.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const part of parts) { bytes.set(part, offset); offset += part.byteLength; }
  const body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  if (!body || Array.isArray(body) || typeof body !== 'object') throw new Error('invalid_request');
  return body;
}

Deno.serve(async req => {
  const requestOrigin = req.headers.get('Origin') || '';
  const allowedOrigin = validOrigins && (requestOrigin === origin || (testOrigin !== '' && requestOrigin === testOrigin));
  // Each request gets its own headers/response factory, including error paths.
  // Never reflect an origin that was not matched against this configuration.
  const cors: Record<string, string> = {
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
    ...(allowedOrigin ? { 'Access-Control-Allow-Origin': requestOrigin } : {}),
  };
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' },
  });
  if (!validOrigins) return json({ error: 'unavailable' }, 503);
  if (!allowedOrigin) return json({ error: 'unavailable' }, 403);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (req.method !== 'POST') return json({ error: 'invalid_method' }, 405);
  const auth = req.headers.get('Authorization') || '';
  if (!/^Bearer\s+\S+$/i.test(auth)) return json({ error: 'unauthorized' }, 401);
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anon) return json({ error: 'unavailable' }, 503);
  try {
    const client = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
    // Never trust decoded token contents, editable user_metadata or UI state.
    const { data: { user }, error: userError } = await client.auth.getUser();
    if (userError || !user?.email_confirmed_at || user.is_anonymous) return json({ error: 'unauthorized' }, 401);
    let body: Record<string, unknown>;
    try { body = await readBody(req); }
    catch (error) { return json({ error: error instanceof Error && error.message === 'request_too_large' ? 'request_too_large' : 'invalid_request' }, 400); }
    let rpc: string;
    let args: Record<string, unknown> = {};
    const isId = (id: unknown) => typeof id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
    if (typeof body.action !== 'string') return json({error:'invalid_request'},400);
    if (['users','events','reports'].includes(body.action)) {
      const statuses = body.action === 'events' ? ['', 'scheduled','in_progress','completed','cancelled'] : ['', 'received','in_review','actioned','no_action','appealed'];
      if ((body.query !== undefined && (typeof body.query !== 'string' || body.query.length > 100)) ||
        (body.offset !== undefined && (typeof body.offset !== 'number' || !Number.isInteger(body.offset) || body.offset<0 || body.offset>100000)) ||
        (body.action === 'users' && body.role !== undefined && (typeof body.role !== 'string' || !['','host','sportivo'].includes(body.role))) ||
        (body.action !== 'users' && body.status !== undefined && (typeof body.status !== 'string' || !statuses.includes(body.status)))) return json({error:'invalid_request'},400);
      rpc = body.action === 'users' ? 'admin_users' : body.action === 'events' ? 'admin_events' : 'admin_reports';
      args = {p_query:body.query??'',p_offset:body.offset??0,...(body.action==='users'?{p_role:body.role??''}:{p_status:body.status??''})};
    } else if (body.action === 'user-role') {
      if(!isId(body.id) || typeof body.role!=='string' || !['host','sportivo'].includes(body.role)) return json({error:'invalid_request'},400);
      rpc='admin_set_user_role';args={p_id:body.id,p_role:body.role};
    } else if (body.action === 'review-report') {
      if(!isId(body.id) || typeof body.status!=='string' || !['received','in_review','actioned','no_action','appealed'].includes(body.status) ||
        typeof body.note!=='string' || body.note.length>2000) return json({error:'invalid_request'},400);
      rpc='admin_review_report';args={p_id:body.id,p_status:body.status,p_note:body.note};
    } else if (body.action === 'cancel-event') {
      if(!isId(body.id)) return json({error:'invalid_request'},400);
      rpc='admin_cancel_event';args={p_id:body.id};
    } else if (body.action === 'erasure-preview' || body.action === 'erasure-execute') {
      // Separate rollout and database gates. Existing deployments stay off;
      // the user JWT still reaches the allowlist/MFA-protected transaction.
      if (Deno.env.get('ACCOUNT_ERASURE_EXECUTION_ENABLED') !== 'true') return json({ error: 'unavailable' }, 503);
      const execute = body.action === 'erasure-execute';
      const keys = execute ? ['action', 'id', 'reviewToken', 'confirmation'] : ['action', 'id'];
      if (!isId(body.id) || Object.keys(body).some(key => !keys.includes(key)) ||
        (execute && (typeof body.reviewToken !== 'string' || !/^[a-f0-9]{64}$/.test(body.reviewToken) || body.confirmation !== 'CANCELLA ACCOUNT'))) {
        return json({ error: 'invalid_request' }, 400);
      }
      rpc = execute ? 'admin_execute_account_erasure' : 'admin_preview_account_erasure';
      args = { p_request_id: body.id, ...(execute ? { p_review_token: body.reviewToken, p_confirmation: body.confirmation } : {}) };
    } else if (body.action === 'dashboard') rpc = 'admin_dashboard';
    else if (body.action === 'audit') rpc = 'admin_audit_log';
    else if (body.action === 'tickets') {
      if ((body.query !== undefined && (typeof body.query !== 'string' || body.query.length > 100)) ||
        (body.status !== undefined && (typeof body.status !== 'string' || !['', 'new', 'in_progress', 'waiting_user', 'resolved', 'closed'].includes(body.status))) ||
        (body.category !== undefined && (typeof body.category !== 'string' || !['', 'bug', 'account', 'event', 'safety', 'other'].includes(body.category))) ||
        (body.sort !== undefined && (typeof body.sort !== 'string' || !['date', 'name'].includes(body.sort)))) return json({ error: 'invalid_request' }, 400);
      rpc = 'admin_support_tickets';
      args = { p_query: body.query ?? '', p_status: body.status ?? '', p_category: body.category ?? '', p_sort: body.sort ?? 'date' };
    } else if (body.action === 'update-ticket') {
      if (typeof body.id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.id) ||
        typeof body.status !== 'string' || !['new', 'in_progress', 'waiting_user', 'resolved', 'closed'].includes(body.status) ||
        typeof body.reply !== 'string' || body.reply.length > 3000) return json({ error: 'invalid_request' }, 400);
      rpc = 'admin_update_support_ticket';
      args = { p_id: body.id, p_status: body.status, p_reply: body.reply };
    } else return json({ error: 'invalid_action' }, 400);
    const { data, error } = await client.rpc(rpc, args);
    if (error) {
      const message = error.message || '';
      if (error.code === 'PT429') return json({ error: 'rate_limited' }, 429);
      if (message === 'mfa_required') return json({ error: 'mfa_required' }, 403);
      if (error.code === 'PT401') return json({ error: 'unauthorized' }, 401);
      if (error.code === 'PT403' || error.code === '42501') return json({ error: 'forbidden' }, 403);
      if (error.code === 'PT404') return json({ error: 'not_found' }, 404);
      if (error.code === '22023') return json({ error: 'invalid_request' }, 400);
      return json({ error: 'unavailable' }, 503);
    }
    if (rpc === 'admin_preview_account_erasure' || rpc === 'admin_execute_account_erasure') {
      const valid = data && typeof data === 'object' && data.requestId === body.id &&
        ((data.status === 'blocked' && typeof data.reason === 'string' && data.accountErased === false && data.accessClosed === false) ||
         (data.status === 'ready' && rpc === 'admin_preview_account_erasure' && typeof data.reviewToken === 'string' &&
          /^[a-f0-9]{64}$/.test(data.reviewToken) && data.accountErased === false && data.accessClosed === false) ||
         (data.status === 'completed' && data.accountErased === true && data.accessClosed === true));
      if (!valid) return json({ error: 'unavailable' }, 503);
      return json(data);
    }
    if (rpc === 'admin_dashboard') return json({ ...data, usage: await readUsage() });
    return json(['admin_update_support_ticket','admin_set_user_role','admin_review_report','admin_cancel_event'].includes(rpc) ? { ok: data === true } : data);
  } catch {
    return json({ error: 'unavailable' }, 503);
  }
});
