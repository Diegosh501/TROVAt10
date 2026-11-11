import Stripe from 'npm:stripe@23.1.0';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.0';
import { type BillingConfig, type BillingPorts } from './billing-core.ts';

export function billingRuntime(): { config: BillingConfig; ports: BillingPorts } {
  const env = (name: string) => Deno.env.get(name) || '';
  const mode = env('STRIPE_MODE');
  const key = env('STRIPE_RESTRICTED_KEY');
  const validKey = (mode === 'test' && key.startsWith('rk_test_')) || (mode === 'live' && key.startsWith('rk_live_'));
  const config: BillingConfig = {
    enabled: env('BILLING_ENABLED') === 'true' && validKey,
    mode: mode as 'test' | 'live', origin: env('APP_ORIGIN'), accountId: env('STRIPE_ACCOUNT_ID'),
    priceId: env('STRIPE_PREMIUM_PRICE_ID'), portalConfigurationId: env('STRIPE_PORTAL_CONFIGURATION_ID'),
    integrationIdentifier: env('STRIPE_INTEGRATION_IDENTIFIER'),
  };
  const stripe = new Stripe(key || 'unconfigured', {
    apiVersion: '2026-10-28.endive', httpClient: Stripe.createFetchHttpClient(), timeout: 8000, maxNetworkRetries: 1,
  });
  const db = createClient(env('SUPABASE_URL') || 'https://unconfigured.invalid', env('SUPABASE_SERVICE_ROLE_KEY') || 'unconfigured',
    { auth: { persistSession: false, autoRefreshToken: false } });
  const ports: BillingPorts = {
    stripe,
    authorize: async bearer => {
      const caller = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
        global: { headers: { Authorization: bearer } }, auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data: { user }, error } = await caller.auth.getUser();
      if (error || !user?.email_confirmed_at || user.is_anonymous) throw { code: 'PT401' };
      const result = await caller.rpc('billing_authorize');
      if (result.error) throw result.error;
      if (result.data !== user.id) throw { code: 'PT401' };
      return user.id;
    },
    service: async (action, payload) => {
      const { data, error } = await db.rpc('billing_service', { p_action: action, p: payload });
      if (error) throw error;
      return data;
    },
    verifyEvent: (body, signature) => stripe.webhooks.constructEventAsync(body, signature,
      env('STRIPE_WEBHOOK_SIGNING_SECRET'), 300, Stripe.createSubtleCryptoProvider()) as Promise<any>,
  };
  return { config, ports };
}
