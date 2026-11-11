import { createBillingHandler } from '../_shared/billing-core.ts';
import { billingRuntime } from '../_shared/billing-runtime.ts';
const { config, ports } = billingRuntime();
Deno.serve(createBillingHandler(config, ports));
