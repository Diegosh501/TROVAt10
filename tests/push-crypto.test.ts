import * as webpush from 'npm:web-push@4.0.0';
import { createPushDispatcher, type PushConfig } from '../supabase/functions/_shared/push-core.ts';

// Real library and independent WebCrypto receiver. No network permissions,
// provider credentials, persistent keys, browser subscription or user data.
// Receiver framing/key derivation follows RFC8291/8188; VAPID follows RFC8292.
const enc = new TextEncoder(), dec = new TextDecoder();
const ids = { delivery: '11111111-1111-4111-8111-111111111111',
  lease: '22222222-2222-4222-8222-222222222222', notice: '33333333-3333-4333-8333-333333333333' };
function ensure(value: unknown, message: string): asserts value { if (!value) throw Error(message); }
function encode(bytes: Uint8Array) { return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
function decode(value: string) { return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - value.length % 4) % 4)), c => c.charCodeAt(0)); }
function join(...parts: Uint8Array[]) { const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0)); let offset = 0; for (const part of parts) { out.set(part, offset); offset += part.length; } return out; }
async function receiver() {
  const keys = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const publicKey = new Uint8Array(await crypto.subtle.exportKey('raw', keys.publicKey));
  return { keys, publicKey, auth: crypto.getRandomValues(new Uint8Array(16)) };
}
type Receiver = Awaited<ReturnType<typeof receiver>>;
async function openMessage(body: Uint8Array, recipient: Receiver) {
  ensure(body.length > 102 && body[20] === 65, 'Unexpected encrypted record framing');
  const salt = body.slice(0, 16), recordSize = new DataView(body.buffer, body.byteOffset + 16, 4).getUint32(0);
  const sender = body.slice(21, 86), ciphertext = body.slice(86);
  ensure(sender[0] === 4 && ciphertext.length < recordSize && body.length <= 4096, 'Invalid single-record limits');
  const senderKey = await crypto.subtle.importKey('raw', sender, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = await crypto.subtle.deriveBits({ name: 'ECDH', public: senderKey }, recipient.keys.privateKey, 256);
  const firstKey = await crypto.subtle.importKey('raw', shared, 'HKDF', false, ['deriveBits']);
  const ikm = await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: recipient.auth,
    info: join(enc.encode('WebPush: info\0'), recipient.publicKey, sender) }, firstKey, 256);
  const ikmKey = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  const key = await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info: enc.encode('Content-Encoding: aes128gcm\0') }, ikmKey, 128);
  const nonce = await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info: enc.encode('Content-Encoding: nonce\0') }, ikmKey, 96);
  const cek = await crypto.subtle.importKey('raw', key, 'AES-GCM', false, ['decrypt']);
  const plaintext = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce, tagLength: 128 }, cek, ciphertext));
  let end = plaintext.length - 1; while (end >= 0 && plaintext[end] === 0) end--;
  ensure(end >= 0 && plaintext[end] === 2, 'Missing final-record delimiter');
  return JSON.parse(dec.decode(plaintext.slice(0, end)));
}
async function vapid(details: any, tamperSignature = false) {
  const auth = new Headers(details.headers).get('Authorization') || '';
  ensure(auth.startsWith('vapid '), 'Missing VAPID authorization');
  const params = Object.fromEntries(auth.slice(6).split(',').map(pair => { const at = pair.indexOf('='); return [pair.slice(0, at).trim(), pair.slice(at + 1).trim()]; }));
  const parts = params.t.split('.'); ensure(parts.length === 3, 'Invalid signed token');
  const header = JSON.parse(dec.decode(decode(parts[0]))), claims = JSON.parse(dec.decode(decode(parts[1])));
  ensure(header.alg === 'ES256', 'Unexpected signature algorithm');
  const raw = decode(params.k), signature = decode(parts[2]); if (tamperSignature) signature[0] ^= 1;
  const publicKey = await crypto.subtle.importKey('raw', raw, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
  const validSignature = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, publicKey, signature, enc.encode(parts[0] + '.' + parts[1]));
  return { validSignature, claims, publicKey: params.k };
}
async function rejected(operation: () => Promise<unknown>) { let failed = false; try { await operation(); } catch { failed = true; } ensure(failed, 'Changed encryption material was accepted'); }
async function fixture(options: { endpoint?: string; withdraw?: boolean; mismatch?: boolean } = {}) {
  const recipient = await receiver(), signing = webpush.generateVAPIDKeys();
  const config: PushConfig = { enabled: true, cronSecret: encode(crypto.getRandomValues(new Uint8Array(32))),
    publicKey: signing.publicKey, privateKey: options.mismatch ? webpush.generateVAPIDKeys().privateKey : signing.privateKey,
    subject: 'mailto:support@example.invalid', origin: 'https://app.example.test' };
  const row = { delivery_id: ids.delivery, lease_token: ids.lease, notice_id: ids.notice, subscription_id: ids.delivery,
    endpoint: options.endpoint || 'https://updates.push.services.mozilla.com/wpush/v2/synthetic-fixture',
    p256dh: encode(recipient.publicKey), auth: encode(recipient.auth),
    private_venue: 'PRIVATE VENUE FIXTURE', phone: 'PRIVATE PHONE FIXTURE', invite_token: 'PRIVATE INVITE FIXTURE' };
  const calls: string[] = [], prepared: any[] = [], sent: any[] = [], finishes: string[] = []; let checks = 0;
  const handler = createPushDispatcher(config, {
    rpc: async (name, args) => { calls.push(name); if (name === 'claim_push_deliveries') return [row];
      if (name === 'check_push_delivery') return options.withdraw && ++checks > 1 ? null : row;
      ensure(name === 'finish_push_delivery', 'Unexpected RPC'); finishes.push(String(args.p_result)); return true; },
    prepare: (subscription, payload, opts) => { const details = webpush.generateRequestDetails(subscription, payload, opts); prepared.push(details); return details; },
    send: details => { sent.push(details); return Promise.resolve(new Response(null, { status: 201 })); },
  });
  const request = () => handler(new Request(config.origin, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + config.cronSecret }, body: '{}' }));
  return { config, recipient, row, calls, prepared, sent, finishes, request };
}

Deno.test('crypto fixtures run without operator credentials or delivery/network permission', async () => {
  ensure(Object.keys(Deno.env.toObject()).every(name => ['PATH', 'DENO_DIR', 'NO_COLOR'].includes(name)), 'Use the sanitized crypto test runner');
  ensure((await Deno.permissions.query({ name: 'net', host: 'fcm.googleapis.com' })).state !== 'granted', 'Real delivery permission must not be granted');
  ensure((await Deno.permissions.query({ name: 'write' })).state !== 'granted', 'Fixture must not persist signing keys');
});
Deno.test('actual Web Push library encrypts a generic payload decryptable by an independent receiver', async () => {
  const f = await fixture(), response = await f.request(); ensure(response.status === 200 && f.sent.length === 1, 'Valid message not sent to controlled transport');
  const details = f.sent[0], headers = new Headers(details.headers), body = new Uint8Array(details.body);
  ensure(headers.get('Content-Encoding') === 'aes128gcm' && headers.get('TTL') === '300' && details.method === 'POST', 'Unexpected wire headers');
  const payload = await openMessage(body, f.recipient);
  ensure(JSON.stringify(payload) === JSON.stringify({ title: 'TROVAT1O', body: 'Hai un aggiornamento per una partita.', url: '/?notifications=1', tag: 'trovat1o-' + ids.notice }), 'Notification leaked extra data or changed its destination');
  ensure(!dec.decode(body).includes('Hai un aggiornamento') && !dec.decode(body).includes('PRIVATE'), 'Payload was not encrypted');
  ensure(f.finishes.join() === 'sent', 'Successful transport not acknowledged');
  const receipt = await response.text(); ensure(!receipt.includes(f.config.privateKey) && !receipt.includes(f.row.endpoint), 'Private transport data exposed');
});
Deno.test('actual VAPID signatures use the provider audience and matching public key for all supported hosts', async () => {
  for (const endpoint of ['https://fcm.googleapis.com/fcm/send/synthetic-fixture', 'https://updates.push.services.mozilla.com/wpush/v2/synthetic-fixture', 'https://web.push.apple.com/synthetic-fixture']) {
    const f = await fixture({ endpoint }); await f.request(); ensure(f.sent.length === 1, 'Provider fixture did not prepare');
    const signed = await vapid(f.sent[0]), now = Math.floor(Date.now() / 1000);
    ensure(signed.validSignature && signed.publicKey === f.config.publicKey, 'VAPID signature does not match advertised identity');
    ensure(signed.claims.aud === new URL(endpoint).origin && signed.claims.sub === f.config.subject, 'Wrong audience or contact');
    ensure(signed.claims.exp > now && signed.claims.exp <= now + 86400, 'Invalid VAPID expiry');
    ensure(encode(new Uint8Array(f.sent[0].body).slice(21, 86)) !== signed.publicKey, 'Encryption and signing keys were reused');
    ensure(!(await vapid(f.sent[0], true)).validSignature, 'Changed signature accepted');
  }
});
Deno.test('ciphertext tampering, another receiver and a changed authentication secret cannot decrypt', async () => {
  const f = await fixture(); await f.request(); const body = new Uint8Array(f.sent[0].body), changed = body.slice(); changed[changed.length - 1] ^= 1;
  await rejected(() => openMessage(changed, f.recipient)); await rejected(async () => openMessage(body, await receiver()));
  const auth = f.recipient.auth.slice(); auth[0] ^= 1; await rejected(() => openMessage(body, { ...f.recipient, auth }));
});
Deno.test('new encryption uses fresh record material for the same recipient and payload', async () => {
  const f = await fixture(); await f.request(); await f.request(); ensure(f.sent.length === 2, 'Two controlled messages not prepared');
  const first = new Uint8Array(f.sent[0].body), second = new Uint8Array(f.sent[1].body);
  ensure(encode(first.slice(0, 16)) !== encode(second.slice(0, 16)) && encode(first.slice(21, 86)) !== encode(second.slice(21, 86)), 'Record material reused');
  ensure(JSON.stringify(await openMessage(first, f.recipient)) === JSON.stringify(await openMessage(second, f.recipient)), 'Fresh encrypted records do not recover the same payload');
});
Deno.test('consent withdrawal after real encryption prevents any controlled send', async () => {
  const f = await fixture({ withdraw: true }); await f.request(); ensure(f.prepared.length === 1 && f.sent.length === 0 && f.finishes.join() === 'skipped', 'Withdrawal did not stop delivery');
});
Deno.test('mismatched VAPID configuration fails before claiming any queued message', async () => {
  const f = await fixture({ mismatch: true }), response = await f.request();
  ensure(response.status === 503 && f.calls.length === 0 && f.sent.length === 0, 'Mismatched VAPID key pair reached the queue');
});
Deno.test('actual Edge entrypoint imports and registers a protected handler without starting a server', async () => {
  const signing = webpush.generateVAPIDKeys(), secret = encode(crypto.getRandomValues(new Uint8Array(32)));
  const env: Record<string, string> = { SUPABASE_URL: 'https://fixture.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'synthetic-notcredential',
    PUSH_ENABLED: 'true', PUSH_CRON_SECRET: secret, VAPID_PUBLIC_KEY: signing.publicKey, VAPID_PRIVATE_KEY: signing.privateKey,
    VAPID_SUBJECT: 'mailto:support@example.invalid', APP_ORIGIN: 'https://app.example.test' };
  const originalServe = Deno.serve, originalGet = Deno.env.get; let captured: ((request: Request) => Promise<Response>) | null = null;
  try {
    Deno.env.get = (name: string) => env[name];
    Deno.serve = ((handler: any) => { captured = handler; return {}; }) as typeof Deno.serve;
    await import('../supabase/functions/push-dispatch/index.ts');
  } finally { Deno.serve = originalServe; Deno.env.get = originalGet; }
  const handler = captured as unknown as ((request: Request) => Promise<Response>); ensure(typeof handler === 'function', 'Entrypoint did not register');
  const response = await handler(new Request(env.APP_ORIGIN, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }));
  ensure(response.status === 401 && response.headers.get('Cache-Control') === 'no-store', 'Unauthenticated job request was accepted');
});
