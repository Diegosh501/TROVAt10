// Shared, transport-independent billing logic. Tests exercise these same handlers.
// Only opaque Stripe IDs and paid periods reach the application database.
export type Json = Record<string, any>;
export type BillingConfig = {
  enabled: boolean; mode: 'test' | 'live'; origin: string; accountId: string;
  priceId: string; portalConfigurationId: string; integrationIdentifier: string;
};
export type BillingPorts = {
  stripe: any;
  authorize: (bearer: string) => Promise<string>;
  service: (action: string, payload: Json) => Promise<any>;
  verifyEvent: (body: string, signature: string) => Promise<Json>;
};
class BillingError extends Error {
  code: string;
  status: number;
  constructor(code: string, status: number) { super(code); this.code = code; this.status = status; }
}
function reject(code = 'unavailable', status = 503): never { throw new BillingError(code, status); }
const objectId = (value: any): string => typeof value === 'string' ? value : value?.id || '';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const billingEventTypes = [
  'checkout.session.completed', 'checkout.session.async_payment_succeeded',
  'customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted',
  'customer.subscription.paused', 'customer.subscription.resumed',
  'invoice.paid', 'invoice.payment_failed',
  'charge.refunded', 'charge.dispute.created', 'charge.dispute.closed',
  'radar.early_fraud_warning.created',
] as const;

function validConfig(c: BillingConfig) {
  try {
    return c.enabled && ['test', 'live'].includes(c.mode) && new URL(c.origin).origin === c.origin &&
      new URL(c.origin).protocol === 'https:' && /^acct_[a-zA-Z0-9]+$/.test(c.accountId) &&
      /^price_[a-zA-Z0-9]+$/.test(c.priceId) && /^bpc_[a-zA-Z0-9]+$/.test(c.portalConfigurationId) &&
      /^trovat1o-annual-[a-z]{8}$/.test(c.integrationIdentifier);
  } catch { return false; }
}
function assertMode(object: Json, c: BillingConfig) {
  if (object?.livemode !== (c.mode === 'live')) reject('mode_mismatch', 400);
}
function invoiceSubscription(invoice: Json): string {
  return invoice.parent?.type === 'subscription_details'
    ? objectId(invoice.parent.subscription_details?.subscription) : '';
}
function invoicePeriod(invoice: Json, subscriptionId: string, c: BillingConfig, requirePaid = true) {
  assertMode(invoice, c);
  if (invoiceSubscription(invoice) !== subscriptionId || invoice.currency !== 'eur') return null;
  if (requirePaid && (invoice.status !== 'paid' || !(invoice.amount_paid > 0))) return null;
  // A truncated line list is not sufficient to determine the paid entitlement.
  if (invoice.lines?.has_more) reject();
  const ends = (invoice.lines?.data || []).filter((line: Json) =>
    line.pricing?.type === 'price_details' && objectId(line.pricing.price_details?.price) === c.priceId &&
    line.quantity === 1 && line.amount > 0 && Number.isSafeInteger(line.period?.end)
  ).map((line: Json) => line.period.end);
  if (!ends.length) return null;
  const until = Math.max(...ends);
  if (until > Date.now() / 1000 + 400 * 86400) reject();
  return { id: invoice.id, paid_until: until };
}
async function boundedList(request: any, limit = 500): Promise<Json[]> {
  const result: Json[] = [];
  // stripe-node auto-pagination visits every page, including multi-invoice risks.
  for await (const value of request) {
    result.push(value);
    if (result.length > limit) reject();
  }
  return result;
}
function stripeUrl(value: any, expectedHost: string) {
  try {
    const url = new URL(value);
    if (url.protocol === 'https:' && url.hostname === expectedHost && !url.username && !url.password) return url.href;
  } catch { /* fail closed */ }
  return reject();
}
async function textBody(req: Request, max: number) {
  if (!req.body) reject('invalid_request', 400);
  const reader = req.body!.getReader(), chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > max) { await reader.cancel(); reject('request_too_large', 413); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let at = 0;
  for (const part of chunks) { bytes.set(part, at); at += part.length; }
  try { return new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
  catch { return reject('invalid_request', 400); }
}
function headers(c: BillingConfig, cors = false): Record<string, string> {
  return { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
    ...(cors ? { 'Access-Control-Allow-Origin': c.origin, 'Access-Control-Allow-Headers': 'authorization,apikey,content-type',
      'Access-Control-Allow-Methods': 'POST,OPTIONS', 'Vary': 'Origin' } : {}) };
}
function response(c: BillingConfig, body: any, status = 200, cors = false) {
  return new Response(JSON.stringify(body), { status, headers: headers(c, cors) });
}
function failure(c: BillingConfig, error: any, cors = false) {
  if (error instanceof BillingError) return response(c, { error: error.code }, error.status, cors);
  if (error?.code === 'PT429') return response(c, { error: 'rate_limited' }, 429, cors);
  if (error?.code === 'PT401') return response(c, { error: 'unauthorized' }, 401, cors);
  if (error?.code === 'PT409') return response(c, { error: 'busy' }, 409, cors);
  return response(c, { error: 'unavailable' }, 503, cors);
}
async function validateAccount(p: BillingPorts, c: BillingConfig) {
  const account = await p.stripe.accounts.retrieve();
  if (account.id !== c.accountId) reject();
}
async function validatePrice(p: BillingPorts, c: BillingConfig) {
  const price = await p.stripe.prices.retrieve(c.priceId);
  assertMode(price, c);
  if (!price.active || price.currency !== 'eur' || price.unit_amount !== 499 || price.type !== 'recurring' ||
    price.recurring?.interval !== 'year' || price.recurring.interval_count !== 1 || price.recurring.usage_type !== 'licensed') reject();
}

export function createBillingHandler(c: BillingConfig, p: BillingPorts) {
  const service = (action: string, body: Json) => p.service(action, { ...body, mode: c.mode });
  return async (req: Request): Promise<Response> => {
    if (!validConfig(c)) return response(c, { error: 'billing_unavailable' }, 503);
    if (req.headers.get('Origin') !== c.origin) return response(c, { error: 'forbidden' }, 403);
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(c, true) });
    if (req.method !== 'POST') return response(c, { error: 'invalid_method' }, 405, true);
    let lease: Json | null = null, userId = '';
    try {
      const bearer = req.headers.get('Authorization') || '';
      if (!/^Bearer\s+\S+$/i.test(bearer)) reject('unauthorized', 401);
      if (!req.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) reject('invalid_request', 400);
      let body: Json;
      try { body = JSON.parse(await textBody(req, 2048)); }
      catch (error) { if (error instanceof BillingError) throw error; return reject('invalid_request', 400); }
      if (!body || Array.isArray(body) || typeof body !== 'object' ||
        Object.keys(body).some(key => !['action', 'requestId'].includes(key)) ||
        !['checkout', 'portal', 'status'].includes(body.action) ||
        (body.action !== 'status' && (typeof body.requestId !== 'string' || !uuid.test(body.requestId)))) reject('invalid_request', 400);
      userId = await p.authorize(bearer);
      if (!uuid.test(userId)) reject('unauthorized', 401);
      if (body.action === 'status') {
        const status = await service('status', { user_id: userId });
        return response(c, { mode: c.mode, ...(status || { plan: 'free', validUntil: null, cancelAtPeriodEnd: false, hasCustomer: false }) }, 200, true);
      }
      await validateAccount(p, c);
      if (body.action === 'portal') {
        const account = await service('account', { user_id: userId });
        if (!account?.customer_id) reject('no_subscription', 409);
        const config = await p.stripe.billingPortal.configurations.retrieve(c.portalConfigurationId);
        assertMode(config, c);
        if (!config.active || config.features?.subscription_cancel?.enabled !== true ||
          config.features.subscription_cancel.mode !== 'at_period_end' || config.features.subscription_update?.enabled) reject();
        const portal = await p.stripe.billingPortal.sessions.create({ customer: account.customer_id,
          configuration: c.portalConfigurationId, return_url: `${c.origin}/?billing=return` },
          { idempotencyKey: `trovat1o-${c.mode}-portal-${userId}-${body.requestId}` });
        return response(c, { url: stripeUrl(portal.url, 'billing.stripe.com'), mode: c.mode }, 200, true);
      }
      await validatePrice(p, c);
      lease = await service('checkout-lock', { user_id: userId });
      if (!lease?.token) reject('busy', 409);
      let customerId = lease.customer_id;
      if (!customerId) {
        // No email, phone, name or user metadata is copied to Stripe.
        const customer = await p.stripe.customers.create({}, { idempotencyKey: `trovat1o-${c.mode}-customer-${userId}` });
        assertMode(customer, c);
        customerId = customer.id;
        await service('customer-bind', { user_id: userId, token: lease.token, customer_id: customerId });
      }
      const customer = await p.stripe.customers.retrieve(customerId);
      if (customer.deleted) reject('customer_unavailable', 409);
      assertMode(customer, c);
      const subscriptions = await boundedList(p.stripe.subscriptions.list({ customer: customerId, status: 'all', limit: 100 }));
      if (subscriptions.some(sub => !['canceled', 'incomplete_expired'].includes(sub.status))) reject('subscription_exists', 409);
      if (lease.checkout_id) {
        const previous = await p.stripe.checkout.sessions.retrieve(lease.checkout_id);
        assertMode(previous, c);
        if (objectId(previous.customer) !== customerId) reject();
        if (previous.status === 'open' && previous.expires_at > Date.now() / 1000)
          return response(c, { url: stripeUrl(previous.url, 'checkout.stripe.com'), mode: c.mode }, 200, true);
      }
      const session = await p.stripe.checkout.sessions.create({
        customer: customerId, mode: 'subscription', line_items: [{ price: c.priceId, quantity: 1 }],
        success_url: `${c.origin}/?billing=success`, cancel_url: `${c.origin}/?billing=cancelled`,
        locale: 'it', integration_identifier: c.integrationIdentifier,
        expires_at: Math.floor(Date.now() / 1000) + 1800,
        // automatic_tax is deliberately absent until an active tax registration is confirmed.
      }, { idempotencyKey: `trovat1o-${c.mode}-checkout-${userId}-${body.requestId}` });
      assertMode(session, c);
      if (objectId(session.customer) !== customerId || session.mode !== 'subscription') reject();
      const url = stripeUrl(session.url, 'checkout.stripe.com');
      await service('checkout-save', { user_id: userId, token: lease.token, checkout_id: session.id, expires_at: session.expires_at });
      return response(c, { url, mode: c.mode }, 200, true);
    } catch (error) { return failure(c, error, true); }
    finally {
      if (lease?.token) { try { await service('checkout-release', { user_id: userId, token: lease.token }); } catch { /* lease expires server-side */ } }
    }
  };
}

type Target = { subscriptionId: string; invoiceId?: string; risk?: Json };
async function riskTargets(event: Json, p: BillingPorts, c: BillingConfig): Promise<Target[]> {
  const source = event.data.object;
  const chargeId = event.type === 'charge.refunded' ? source.id : objectId(source.charge);
  if (!chargeId) return [];
  const charge = await p.stripe.charges.retrieve(chargeId);
  assertMode(charge, c);
  const paymentIntent = objectId(charge.payment_intent);
  if (!paymentIntent) return []; // Not an invoice-based subscription payment.
  const payments = await boundedList(p.stripe.invoicePayments.list({
    payment: { type: 'payment_intent', payment_intent: paymentIntent }, status: 'paid', limit: 100,
  }));
  const targets: Target[] = [];
  for (const invoiceId of new Set(payments.map(payment => objectId(payment.invoice)))) {
    if (!invoiceId) continue;
    const invoice = await p.stripe.invoices.retrieve(invoiceId);
    assertMode(invoice, c);
    const sid = invoiceSubscription(invoice);
    if (!sid || objectId(invoice.customer) !== objectId(charge.customer)) continue;
    const period = invoicePeriod(invoice, sid, c, false);
    if (!period) continue;
    let risk: Json;
    if (event.type === 'charge.refunded') {
      // Partial refunds keep the remaining service; a full refund revokes this invoice only.
      if (!charge.refunded || charge.amount_refunded < charge.amount) continue;
      risk = { reason: 'refund', invoice_id: invoiceId, paid_until: period.paid_until };
    } else if (event.type.startsWith('charge.dispute.')) {
      const dispute = await p.stripe.disputes.retrieve(source.id);
      assertMode(dispute, c);
      if (objectId(dispute.charge) !== chargeId) reject();
      risk = { reason: 'dispute', object_id: dispute.id, active: dispute.status !== 'won' && dispute.status !== 'warning_closed' };
    } else {
      risk = { reason: 'fraud', object_id: source.id, active: true };
    }
    targets.push({ subscriptionId: sid, invoiceId, risk });
  }
  return targets;
}
async function targetsFor(event: Json, p: BillingPorts, c: BillingConfig): Promise<Target[]> {
  const obj = event.data.object;
  if (event.type.startsWith('customer.subscription.')) return [{ subscriptionId: obj.id }];
  if (event.type.startsWith('invoice.')) {
    const invoice = await p.stripe.invoices.retrieve(obj.id);
    assertMode(invoice, c);
    const sid = invoiceSubscription(invoice);
    return sid ? [{ subscriptionId: sid, invoiceId: invoice.id }] : [];
  }
  if (event.type.startsWith('checkout.session.')) {
    const session = await p.stripe.checkout.sessions.retrieve(obj.id);
    assertMode(session, c);
    if (session.mode !== 'subscription' || session.payment_status !== 'paid') return [];
    const sid = objectId(session.subscription);
    return sid ? [{ subscriptionId: sid }] : [];
  }
  return riskTargets(event, p, c);
}
async function reconcile(target: Target, p: BillingPorts, c: BillingConfig) {
  // First retrieve resolves the ownership boundary. Retrieve again AFTER the
  // per-customer lock to prevent a delayed handler overwriting newer state.
  const initial = await p.stripe.subscriptions.retrieve(target.subscriptionId);
  assertMode(initial, c);
  const customerId = objectId(initial.customer);
  const service = (action: string, body: Json) => p.service(action, { ...body, mode: c.mode });
  const lock = await service('sync-lock', { customer_id: customerId });
  if (!lock?.token) return; // A subscription unrelated to TROVAT1O is ignored.
  try {
    const sub = await p.stripe.subscriptions.retrieve(target.subscriptionId);
    assertMode(sub, c);
    if (objectId(sub.customer) !== customerId || sub.items?.has_more || sub.items?.data?.length !== 1) reject();
    const item = sub.items.data[0];
    if (objectId(item.price) !== c.priceId || item.quantity !== 1) reject('unexpected_price', 400);
    const invoices: Json[] = [];
    const ids = new Set([target.invoiceId, objectId(sub.latest_invoice)].filter(Boolean));
    for (const id of ids) {
      const invoice = await p.stripe.invoices.retrieve(id);
      if (objectId(invoice.customer) !== customerId) reject();
      const period = invoicePeriod(invoice, sub.id, c);
      if (period) invoices.push(period);
    }
    await service('apply', { customer_id: customerId, token: lock.token,
      subscription: { id: sub.id, customer_id: customerId, price_id: c.priceId,
        status: sub.status, cancel_at_period_end: sub.cancel_at_period_end }, invoices, risk: target.risk || null });
  } finally { await service('sync-release', { customer_id: customerId, token: lock.token }); }
}

export function createStripeWebhookHandler(c: BillingConfig, p: BillingPorts) {
  const service = (action: string, body: Json) => p.service(action, { ...body, mode: c.mode });
  return async (req: Request): Promise<Response> => {
    if (!validConfig(c)) return response(c, { error: 'billing_unavailable' }, 503);
    if (req.method !== 'POST') return response(c, { error: 'invalid_method' }, 405);
    let event: Json;
    try {
      const raw = await textBody(req, 262144), signature = req.headers.get('Stripe-Signature');
      if (!signature || signature.length > 2048) reject('invalid_signature', 400);
      try { event = await p.verifyEvent(raw, signature); } catch { return reject('invalid_signature', 400); }
      assertMode(event, c);
      // Not a Connect integration. Never accept a connected-account event.
      if (event.account || !/^evt_[A-Za-z0-9]+$/.test(event.id) || !Number.isSafeInteger(event.created) ||
        !event.data?.object || event.api_version !== '2026-10-28.endive') reject('invalid_event', 400);
    } catch (error) { return failure(c, error); }
    if (!(billingEventTypes as readonly string[]).includes(event.type)) return response(c, { received: true });
    let claim: Json | null = null, success = false;
    try {
      await validateAccount(p, c);
      claim = await service('claim-event', { event_id: event.id, type: event.type, created: event.created });
      if (claim?.done) return response(c, { received: true });
      if (!claim?.token) reject();
      const targets = await targetsFor(event, p, c);
      for (const target of targets) await reconcile(target, p, c);
      const result = await service('finish-event', { event_id: event.id, token: claim.token, success: true });
      if (!result?.ok) reject();
      success = true;
      return response(c, { received: true });
    } catch (error) {
      // A concurrent delivery or infrastructure failure must be retried by Stripe.
      // Do not acknowledge an event until all database work has committed.
      return response(c, { error: error instanceof BillingError && error.status === 400 ? error.code : 'retry_later' },
        error instanceof BillingError && error.status === 400 ? 400 : 503);
    } finally {
      if (claim?.token && !success) { try { await service('finish-event', { event_id: event.id, token: claim.token, success: false }); } catch { /* lease expires */ } }
    }
  };
}
