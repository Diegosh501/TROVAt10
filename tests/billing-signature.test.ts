import Stripe from 'npm:stripe@23.1.0';
import { createStripeWebhookHandler, type BillingPorts } from '../supabase/functions/_shared/billing-core.ts';

// Deterministic synthetic fixture; never an account credential or a deploy secret.
const secret = 'synthetic-webhook-signature-fixture';
const stripe = new Stripe('synthetic-noncredential-fixture', { apiVersion: '2026-10-28.endive', httpClient: Stripe.createFetchHttpClient() });
const config = { enabled: true, mode: 'test' as const, origin: 'https://app.example.test', accountId: 'acct_test',
  priceId: 'price_test', portalConfigurationId: 'bpc_test', integrationIdentifier: 'trovat1o-annual-abcdefgh' };
const body = JSON.stringify({ id: 'evt_test', type: 'product.updated', livemode: false, created: 1,
  api_version: '2026-10-28.endive', data: { object: { id: 'prod_test' } } });
async function sign(payload: string, timestamp: number, signingSecret = secret) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(signingSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const digest = await crypto.subtle.sign('HMAC', key, enc.encode(`${timestamp}.${payload}`));
  const hex = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
  return `t=${timestamp},v1=${hex}`;
}
const ports: BillingPorts = {
  stripe: {}, authorize: () => Promise.reject('unused'), service: () => Promise.reject('unexpected database access'),
  verifyEvent: (raw, signature) => stripe.webhooks.constructEventAsync(raw, signature, secret, 300, Stripe.createSubtleCryptoProvider()) as Promise<any>,
};
const handler = createStripeWebhookHandler(config, ports);
async function expectStatus(payload: string, signature: string, expected: number) {
  const response = await handler(new Request(config.origin, { method: 'POST', headers: { 'Stripe-Signature': signature }, body: payload }));
  if (response.status !== expected) throw new Error(`Expected ${expected}, received ${response.status}`);
  const output = await response.text();
  if (output.includes(secret)) throw new Error('Signing secret exposed');
}
Deno.test('actual Stripe SDK accepts the exact signed raw payload', async () => {
  await expectStatus(body, await sign(body, Math.floor(Date.now() / 1000)), 200);
});
Deno.test('actual Stripe SDK rejects a body changed after signing', async () => {
  await expectStatus(body + ' ', await sign(body, Math.floor(Date.now() / 1000)), 400);
});
Deno.test('actual Stripe SDK rejects an old replay outside the 300s tolerance', async () => {
  await expectStatus(body, await sign(body, Math.floor(Date.now() / 1000) - 600), 400);
});
Deno.test('actual Stripe SDK rejects another endpoint signing secret', async () => {
  await expectStatus(body, await sign(body, Math.floor(Date.now() / 1000), 'another-synthetic-fixture'), 400);
});
Deno.test('actual Stripe SDK supports overlapping signatures during rotation', async () => {
  await expectStatus(body, (await sign(body, Math.floor(Date.now() / 1000))) + ',v1=000000', 200);
});
Deno.test('missing or malformed signatures cannot reach the database', async () => {
  await expectStatus(body, '', 400);
  await expectStatus(body, 't=invalid,v1=invalid', 400);
});
