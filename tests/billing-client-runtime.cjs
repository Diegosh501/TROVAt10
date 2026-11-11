const assert=require('node:assert/strict'),vm=require('node:vm');
const {boot}=require('./runtime-regressions.cjs');
function setup(config={}){
 const b=boot({config:{billingReady:true,billingMode:'test',...config,onlineReady:false}}),c=b.context;c.TROVAT1O_CONFIG.onlineReady=true;
 const state={requests:[],response:{mode:'test',plan:'free',hasCustomer:true,validUntil:null},navigated:[],wait:null};
 c.transport=async input=>{state.requests.push(input);return state.wait?await state.wait:{data:state.response,error:null}};
 c.location.assign=url=>state.navigated.push(url);
 c.loadProfile=async()=>true;
 vm.runInContext("profile={id:'11111111-1111-4111-8111-111111111111',username:'Host',role:'host',plan:'free',demo:false};authSession={user:{id:profile.id}};supabaseClient={functions:{invoke:async(name,input)=>transport({name,...input})}}",c);
 return {...b,state};
}
let n=0;async function check(label,fn){await fn();console.log('PASS '+(++n)+': '+label)}
(async()=>{
 await check('disabled payments expose no purchase CTA and preserve Free',async()=>{const b=setup({billingReady:false});b.context.openPricing();assert.ok(!b.elements.get('billingCheckoutButton'));assert.match(b.elements.get('dialogContent').innerHTML,/Gli acquisti Premium non sono ancora disponibili/);assert.equal(b.state.requests.length,0)});
 await check('test environment is explicitly identified without real payment claims',async()=>{const b=setup();b.context.openPricing();assert.match(b.elements.get('dialogSubtitle').textContent,/prova|addebito/);assert.match(b.elements.get('dialogFoot').innerHTML,/Prova Premium/)});
 await check('checkout request contains no client price/customer/plan',async()=>{const b=setup();b.state.response={mode:'test',url:'https://checkout.stripe.com/c/pay/test'};await b.context.startPremiumCheckout();const request=b.state.requests[0];assert.equal(request.name,'billing');assert.equal(request.body.action,'checkout');assert.deepEqual(Object.keys(request.body).sort(),['action','requestId']);assert.match(request.body.requestId,/^[0-9a-f-]{36}$/);assert.equal(b.state.navigated[0],'https://checkout.stripe.com/c/pay/test')});
 await check('client refuses live/test mismatch before navigation',async()=>{const b=setup();b.state.response={mode:'live',url:'https://checkout.stripe.com/c/pay/test'};await b.context.startPremiumCheckout();assert.equal(b.state.navigated.length,0);assert.match(b.elements.get('toast').textContent,/Configurazione/)});
 await check('client refuses an unexpected payment destination',async()=>{const b=setup();b.state.response={mode:'test',url:'https://attacker.invalid/collect'};await b.context.startPremiumCheckout();assert.equal(b.state.navigated.length,0)});
 await check('double taps create one in-flight purchase request',async()=>{const b=setup();let resolve;b.state.wait=new Promise(r=>resolve=r);const first=b.context.startPremiumCheckout();await b.context.startPremiumCheckout();assert.equal(b.state.requests.length,1);resolve({data:{mode:'test',url:'https://checkout.stripe.com/c/pay/test'},error:null});await first});
 await check('logout before response prevents navigation from another account',async()=>{const b=setup();let resolve;b.state.wait=new Promise(r=>resolve=r);const first=b.context.startPremiumCheckout();b.context.clearCloudAccountState();resolve({data:{mode:'test',url:'https://checkout.stripe.com/c/pay/test'},error:null});await first;assert.equal(b.state.navigated.length,0)});
 await check('test Premium status does not change production profile entitlement',async()=>{const b=setup();b.state.response={mode:'test',plan:'premium',validUntil:new Date(Date.now()+86400000).toISOString(),hasCustomer:true,cancelAtPeriodEnd:true};b.context.openPricing();await b.context.refreshBillingStatus();assert.equal(vm.runInContext('profile.plan',b.context),'free');assert.match(b.elements.get('billingStatusText').textContent,/Premium di prova attivo fino/)});
 await check('success query alone cannot set Premium',async()=>{const b=setup();b.context.location.href='https://test.example/?billing=success';b.context.handleBillingReturn();assert.equal(vm.runInContext('profile.plan',b.context),'free');assert.match(b.elements.get('dialogTitle').textContent,/piano/)});
 await check('demo cannot invoke payment endpoints',async()=>{const b=setup();vm.runInContext('profile.demo=true',b.context);await b.context.startPremiumCheckout();assert.equal(b.state.requests.length,0)});
 console.log('PASS: '+n+' actual client billing scenarios.');
})().catch(e=>{console.error(e);process.exitCode=1});
