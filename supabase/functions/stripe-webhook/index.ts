import { createStripeWebhookHandler } from '../_shared/billing-core.ts';
import { billingRuntime } from '../_shared/billing-runtime.ts';
const { config, ports } = billingRuntime();
Deno.serve(createStripeWebhookHandler(config, ports));
