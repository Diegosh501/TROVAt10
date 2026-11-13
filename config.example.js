// Copy to config.js only after configuring Supabase Auth, Turnstile and the
// backend. Never put a Supabase service-role key or payment secret here.
window.TROVAT1O_CONFIG = {
  onlineReady: false,
  emailAuthEnabled: false,
  supportReady: false,
  billingReady: false,
  exportReady: false,
  erasureRequestsReady: false,
  accountLifecycleReady: false,
  billingMode: 'test',
  publicBaseUrl: '',
  supabaseUrl: '',
  supabaseAnonKey: '',
  turnstileSiteKey: '',
  supportTurnstileSiteKey: '',
  vapidPublicKey: '',
  pushReady: false
};
