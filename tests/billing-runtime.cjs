// Real shared handlers; Auth, Stripe transport and storage are controlled ports.
// SQL authorization/transactions and SDK signature crypto have separate suites.
const assert=require('node:assert/strict');
const {createBillingHandler,createStripeWebhookHandler,billingEventTypes}=require('../supabase/functions/_shared/billing-core.ts');
const user='11111111-1111-4111-8111-111111111111',requestId='22222222-2222-4222-8222-222222222222';
const config={enabled:true,mode:'test',origin:'https://app.example.test',accountId:'acct_test',priceId:'price_annual',portalConfigurationId:'bpc_test',integrationIdentifier:'trovat1o-annual-abcdefgh'};
const clone=value=>JSON.parse(JSON.stringify(value));
const until=Math.floor(Date.now()/1000)+365*86400;
const invoice={id:'in_paid',livemode:false,customer:'cus_test',currency:'eur',status:'paid',amount_paid:499,parent:{type:'subscription_details',subscription_details:{subscription:'sub_test'}},lines:{has_more:false,data:[{quantity:1,amount:499,pricing:{type:'price_details',price_details:{price:'price_annual'}},period:{end:until}}]}};
const subscription={id:'sub_test',livemode:false,customer:'cus_test',status:'active',cancel_at_period_end:false,latest_invoice:'in_paid',items:{has_more:false,data:[{price:'price_annual',quantity:1}]}};
function boot(options={}){
 const calls=[],applied=[],seen=new Set(),opts={...options};
 const obj={account:{customer_id:opts.noCustomer?null:'cus_test',checkout_id:opts.previous?'cs_test_old':null}};
 const price={id:'price_annual',livemode:false,active:true,currency:'eur',unit_amount:499,type:'recurring',recurring:{interval:'year',interval_count:1,usage_type:'licensed'},...opts.price};
 const sub={...clone(subscription),...opts.sub};
 const inv={...clone(invoice),...opts.invoice};
 const customer={id:'cus_test',livemode:false,...opts.customer};
 const checkout={id:'cs_test_new',livemode:false,mode:'subscription',customer:'cus_test',url:'https://checkout.stripe.com/c/pay/test',status:'complete',subscription:'sub_test',payment_status:'paid',expires_at:Math.floor(Date.now()/1000)+1800,...opts.session};
 const portalConfig={id:'bpc_test',livemode:false,active:true,features:{subscription_cancel:{enabled:true,mode:'at_period_end'},subscription_update:{enabled:false}},...opts.portalConfig};
 const call=(name,value)=>{calls.push({name,value});if(opts.throwAt===name)throw new Error('synthetic private upstream diagnostic');};
 const stripe={accounts:{retrieve:async()=>{call('account');return {id:opts.wrongAccount?'acct_foreign':'acct_test'}}},prices:{retrieve:async()=>{call('price');return price}},
 customers:{create:async(body,options)=>{call('customer-create',{body,options});return customer},retrieve:async()=>{call('customer-get');return customer}},
 subscriptions:{list:params=>{call('subscriptions-list',params);return opts.existing?[sub]:[]},retrieve:async()=>{call('subscription-get');return clone(sub)}},
 checkout:{sessions:{create:async(body,options)=>{call('checkout-create',{body,options});return checkout},retrieve:async id=>{call('checkout-get',id);return id==='cs_test_old'?{...checkout,id,status:'open'}:checkout}}},
 billingPortal:{configurations:{retrieve:async()=>{call('portal-config');return portalConfig}},sessions:{create:async(body,options)=>{call('portal-create',{body,options});return {url:opts.portalUrl||'https://billing.stripe.com/p/session/test'}}}},
 invoices:{retrieve:async id=>{call('invoice-get',id);return {...inv,id}}},
 charges:{retrieve:async()=>{call('charge-get');return {id:'ch_test',livemode:false,customer:'cus_test',payment_intent:'pi_test',refunded:true,amount:499,amount_refunded:499,...opts.charge}}},
 invoicePayments:{list:params=>{call('payments-list',params);return opts.payments||[{invoice:'in_paid'}]}},
 disputes:{retrieve:async()=>({id:'dp_test',livemode:false,charge:'ch_test',status:opts.disputeStatus||'needs_response'})}};
 const ports={stripe,
 authorize:async bearer=>{call('authorize',bearer);if(opts.unauthorized)throw {code:'PT401'};if(opts.quota)throw {code:'PT429'};return user},
 service:async(action,body)=>{call(action,body);if(opts.busy===action)throw {code:'PT409'};
  if(action==='status')return opts.status||{plan:'free',validUntil:null,cancelAtPeriodEnd:false,hasCustomer:!opts.noCustomer};
  if(action==='account')return obj.account;
  if(action==='checkout-lock')return {...obj.account,token:'lease-checkout'};
  if(action==='customer-bind'){obj.account.customer_id=body.customer_id;return {ok:true}};
  if(action==='claim-event'){if(seen.has(body.event_id)||opts.duplicate)return {done:true};return {done:false,token:'lease-event'}};
  if(action==='finish-event'){if(body.success)seen.add(body.event_id);return {ok:!opts.finishFails}};
  if(action==='sync-lock')return opts.unmanaged?null:{token:'lease-sync'};
  if(action==='apply'){applied.push(body);return {ok:true}};
  return {ok:true};},
 verifyEvent:async(body,signature)=>{call('verify-signature',{body,signature});if(signature!=='valid')throw new Error('signature detail');return JSON.parse(body)}};
 const c={...config,...opts.config};const billing=createBillingHandler(c,ports),webhook=createStripeWebhookHandler(c,ports);
 const request=(body={action:'checkout',requestId},extra={})=>billing(new Request(c.origin,{method:'POST',headers:{Origin:c.origin,Authorization:'Bearer test','Content-Type':'application/json',...extra.headers},body:typeof body==='string'?body:JSON.stringify(body),...extra.request}));
 const hook=(type='invoice.paid',overrides={},extra={})=>webhook(new Request(c.origin,{method:'POST',headers:{'Stripe-Signature':'valid',...extra.headers},body:JSON.stringify({id:'evt_test',livemode:false,type,created:Math.floor(Date.now()/1000),api_version:'2026-10-28.endive',data:{object:{id:type.startsWith('checkout')?'cs_test_new':type.startsWith('customer')?'sub_test':type.startsWith('charge.refund')?'ch_test':type.startsWith('charge.dispute')?'dp_test':type.startsWith('radar.')?'issfr_test':'in_paid',charge:'ch_test'}},...overrides})}));
 return {calls,applied,request,hook,billing,webhook};
}
let count=0;async function check(name,fn){await fn();console.log('PASS '+(++count)+': '+name)}
const named=(b,name)=>b.calls.filter(c=>c.name===name);
(async()=>{
 await check('unconfigured billing fails closed without Auth or Stripe calls',async()=>{const b=boot({config:{enabled:false}});assert.equal((await b.request()).status,503);assert.equal(b.calls.length,0)});
 await check('invalid mode, origin, price or integration identity fails closed',async()=>{for(const cfg of [{mode:'other'},{origin:'http://app.example.test'},{origin:'https://app.example.test/'},{priceId:'client-price'},{integrationIdentifier:'untracked'}])assert.equal((await boot({config:cfg}).request()).status,503)});
 await check('exact-origin CORS excludes foreign/missing origin',async()=>{const b=boot();for(const origin of ['https://attacker.test','null',''])assert.equal((await b.request(undefined,{headers:{Origin:origin}})).status,403);assert.equal(b.calls.length,0)});
 await check('preflight succeeds without accessing account data',async()=>{const b=boot();const r=await b.billing(new Request(config.origin,{method:'OPTIONS',headers:{Origin:config.origin}}));assert.equal(r.status,204);assert.equal(b.calls.length,0)});
 await check('missing token, invalid JSON and oversized body are refused',async()=>{assert.equal((await boot().request(undefined,{headers:{Authorization:''}})).status,401);for(const body of ['{broken','null','[]','true'])assert.equal((await boot().request(body)).status,400);assert.equal((await boot().request(' '.repeat(2100))).status,413)});
 await check('untrusted price/customer/redirect/role input never reaches Stripe',async()=>{for(const extra of [{priceId:'price_cheap'},{customer:'cus_other'},{return_url:'https://evil.test'},{role:'admin'}]){const b=boot();assert.equal((await b.request({action:'checkout',requestId,...extra})).status,400);assert.equal(b.calls.length,0)}});
 await check('invalid actions and missing request UUID cannot create a checkout',async()=>{for(const body of [{action:'refund',requestId},{action:'checkout'},{action:'portal',requestId:'bad'}])assert.equal((await boot().request(body)).status,400)});
 await check('revoked session and quota refusals are preserved',async()=>{for(const [opts,status]of [[{unauthorized:true},401],[{quota:true},429]]){const b=boot(opts);assert.equal((await b.request()).status,status);assert.equal(named(b,'account').length,0)}});
 await check('wrong Stripe account and wrong mode are refused',async()=>{for(const opts of [{wrongAccount:true},{price:{livemode:true}}]){const b=boot(opts);assert.notEqual((await b.request()).status,200);assert.equal(named(b,'checkout-create').length,0)}});
 await check('only active EUR 4.99 licensed yearly price is accepted',async()=>{for(const price of [{active:false},{unit_amount:498},{currency:'usd'},{type:'one_time'},{recurring:{interval:'month',interval_count:1,usage_type:'licensed'}},{recurring:{interval:'year',interval_count:2,usage_type:'licensed'}}]){const b=boot({price});assert.notEqual((await b.request()).status,200);assert.equal(named(b,'checkout-create').length,0)}});
 await check('customer is privately mapped with no copied personal information',async()=>{const b=boot({noCustomer:true});assert.equal((await b.request()).status,200);assert.deepEqual(named(b,'customer-create')[0].value.body,{});assert.equal(named(b,'customer-bind')[0].value.customer_id,'cus_test')});
 await check('checkout uses fixed price, server URLs and stable idempotency',async()=>{const b=boot();const r=await b.request();assert.equal(r.status,200);assert.equal(r.headers.get('Cache-Control'),'no-store');const create=named(b,'checkout-create')[0].value;assert.deepEqual(create.body.line_items,[{price:'price_annual',quantity:1}]);assert.equal(create.body.mode,'subscription');assert.equal(create.body.success_url,config.origin+'/?billing=success');assert.ok(!('payment_method_types'in create.body));assert.ok(!('automatic_tax'in create.body));assert.ok(create.options.idempotencyKey.includes(user+'-'+requestId));assert.equal(named(b,'checkout-release').length,1)});
 await check('parallel checkout lease prevents duplicate purchases',async()=>{const b=boot({busy:'checkout-lock'});assert.equal((await b.request()).status,409);assert.equal(named(b,'checkout-create').length,0)});
 await check('existing subscription leads to management, not a second purchase',async()=>{const b=boot({existing:true});assert.equal((await b.request()).status,409);assert.equal(named(b,'checkout-create').length,0);assert.equal(named(b,'checkout-release').length,1)});
 await check('existing open checkout is reused',async()=>{const b=boot({previous:true});assert.equal((await b.request()).status,200);assert.equal(named(b,'checkout-create').length,0)});
 await check('upstream failures are private and release the purchase lease',async()=>{const b=boot({throwAt:'checkout-create'});const r=await b.request();assert.equal(r.status,503);assert.deepEqual(await r.json(),{error:'unavailable'});assert.equal(named(b,'checkout-release').length,1)});
 await check('Stripe URL validation refuses unsafe redirect hosts',async()=>{for(const url of ['http://checkout.stripe.com/pay','https://evil.test/pay','https://checkout.stripe.com.evil.test/pay']){const b=boot({session:{url}});assert.equal((await b.request()).status,503)}});
 await check('portal uses mapped customer and cancels at the paid period end',async()=>{const b=boot();const r=await b.request({action:'portal',requestId});assert.equal(r.status,200);const body=named(b,'portal-create')[0].value.body;assert.equal(body.customer,'cus_test');assert.equal(body.configuration,'bpc_test');assert.equal(body.return_url,config.origin+'/?billing=return')});
 await check('portal cannot be configured to switch prices or cancel paid access immediately',async()=>{for(const features of [{subscription_cancel:{enabled:true,mode:'immediately'},subscription_update:{enabled:false}},{subscription_cancel:{enabled:true,mode:'at_period_end'},subscription_update:{enabled:true}}])assert.equal((await boot({portalConfig:{features}}).request({action:'portal',requestId})).status,503)});
 await check('status is read-only and never exposes customer or subscription IDs',async()=>{const b=boot();const r=await b.request({action:'status'});assert.deepEqual(await r.json(),{mode:'test',plan:'free',validUntil:null,cancelAtPeriodEnd:false,hasCustomer:true});assert.equal(named(b,'account').length,0);assert.equal(named(b,'apply').length,0)});
 await check('webhook signature is required before any database call',async()=>{const b=boot();const r=await b.hook(undefined,{}, {headers:{'Stripe-Signature':'forged'}});assert.equal(r.status,400);assert.equal(named(b,'claim-event').length,0)});
 await check('webhook mode/account/API-version mismatch is rejected',async()=>{for(const override of [{livemode:true},{account:'acct_foreign'},{api_version:'2020-01-01'},{id:'untrusted'},{created:'now'}]){const b=boot();assert.equal((await b.hook('invoice.paid',override)).status,400);assert.equal(named(b,'claim-event').length,0)}});
 await check('unsubscribed events are acknowledged without inspecting users',async()=>{const b=boot();assert.equal((await b.hook('product.updated')).status,200);assert.equal(named(b,'claim-event').length,0)});
 await check('duplicate webhook is acknowledged without granting twice',async()=>{const b=boot({duplicate:true});assert.equal((await b.hook()).status,200);assert.equal(b.applied.length,0)});
 await check('paid invoice resolves first-class subscription and customer IDs',async()=>{const b=boot();assert.equal((await b.hook()).status,200);assert.equal(b.applied.length,1);assert.equal(b.applied[0].subscription.id,'sub_test');assert.deepEqual(b.applied[0].invoices,[{id:'in_paid',paid_until:until}]);assert.equal(b.applied[0].mode,'test');assert.equal(named(b,'subscription-get').length,2)});
 await check('unpaid asynchronous Checkout cannot grant Premium',async()=>{const b=boot({session:{payment_status:'unpaid'}});assert.equal((await b.hook('checkout.session.completed')).status,200);assert.equal(b.applied.length,0)});
 await check('paid asynchronous Checkout is reconciled through Stripe and database',async()=>{const b=boot();assert.equal((await b.hook('checkout.session.async_payment_succeeded')).status,200);assert.equal(b.applied.length,1)});
 await check('failed renewal does not extend the paid entitlement',async()=>{const b=boot({invoice:{status:'open',amount_paid:0},sub:{status:'past_due'}});assert.equal((await b.hook('invoice.payment_failed')).status,200);assert.deepEqual(b.applied[0].invoices,[]);assert.equal(b.applied[0].subscription.status,'past_due')});
 await check('period-end cancellation is retained until paid expiry; immediate deletion changes state',async()=>{for(const sub of [{cancel_at_period_end:true},{status:'canceled'}]){const b=boot({sub});assert.equal((await b.hook('customer.subscription.updated')).status,200);assert.equal(b.applied[0].subscription.status,sub.status||'active');assert.equal(b.applied[0].subscription.cancel_at_period_end,!!sub.cancel_at_period_end)}});
 await check('foreign unmapped subscriptions are ignored',async()=>{const b=boot({unmanaged:true});assert.equal((await b.hook()).status,200);assert.equal(b.applied.length,0)});
 await check('wrong subscription price is never recorded as Premium',async()=>{const b=boot({sub:{items:{data:[{price:'price_other',quantity:1}],has_more:false}}});assert.equal((await b.hook()).status,400);assert.equal(b.applied.length,0)});
 await check('database concurrency and partial failures trigger Stripe retry',async()=>{for(const opts of [{busy:'sync-lock'},{throwAt:'apply'},{finishFails:true}]){const b=boot(opts);assert.equal((await b.hook()).status,503);assert.ok(named(b,'finish-event').some(c=>c.value.success===false))}});
 await check('full refund revokes exactly the associated invoice',async()=>{const b=boot();assert.equal((await b.hook('charge.refunded')).status,200);assert.deepEqual(b.applied[0].risk,{reason:'refund',invoice_id:'in_paid',paid_until:until});assert.deepEqual(named(b,'payments-list')[0].value.payment,{type:'payment_intent',payment_intent:'pi_test'})});
 await check('partial refund is acknowledged without removing the remaining service',async()=>{const b=boot({charge:{refunded:false,amount_refunded:100}});assert.equal((await b.hook('charge.refunded')).status,200);assert.equal(b.applied.length,0)});
 await check('dispute places a hold; a won dispute clears that same hold',async()=>{for(const [status,active]of [['needs_response',true],['won',false],['lost',true]]){const b=boot({disputeStatus:status});assert.equal((await b.hook('charge.dispute.closed')).status,200);assert.deepEqual(b.applied[0].risk,{reason:'dispute',object_id:'dp_test',active})}});
 await check('early fraud warning is a persistent hold requiring review',async()=>{const b=boot();assert.equal((await b.hook('radar.early_fraud_warning.created')).status,200);assert.deepEqual(b.applied[0].risk,{reason:'fraud',object_id:'issfr_test',active:true})});
 await check('every invoice associated with a risky payment is considered',async()=>{const b=boot({payments:[{invoice:'in_paid'},{invoice:'in_second'}]});assert.equal((await b.hook('charge.refunded')).status,200);assert.equal(b.applied.length,2)});
 await check('event subscription list includes lifecycle, paid/failed and risk events',async()=>{for(const type of ['invoice.paid','invoice.payment_failed','customer.subscription.deleted','checkout.session.async_payment_succeeded','charge.refunded','charge.dispute.created','radar.early_fraud_warning.created'])assert.ok(billingEventTypes.includes(type))});
 console.log('PASS: '+count+' billing handler scenarios. Stripe network, real OAuth and real SQL are separate release gates.');
})().catch(error=>{console.error(error);process.exitCode=1});
