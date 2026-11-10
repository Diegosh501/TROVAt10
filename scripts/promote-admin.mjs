// One-time provisioning helper. Never pass credentials as command-line args.
const base=process.env.SUPABASE_URL,service=process.env.SUPABASE_SERVICE_ROLE_KEY,email=process.env.TROVAT1O_ADMIN_EMAIL?.trim().toLowerCase();
if(!base||!service||!email){console.error('Set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, TROVAT1O_ADMIN_EMAIL in your private environment.');process.exit(2)}
const headers={apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'};let page=1,found=null;
while(!found){const r=await fetch(`${base.replace(/\/$/,'')}/auth/v1/admin/users?page=${page}&per_page=100`,{headers});if(!r.ok){console.error('Unable to check Auth users.');process.exit(1)}const d=await r.json(),users=d.users||[];found=users.find(u=>u.email?.toLowerCase()===email);if(users.length<100)break;page++}
if(!found){console.error('No matching confirmed account found.');process.exit(1)}if(!found.email_confirmed_at){console.error('The account email must be confirmed first.');process.exit(1)}
const r=await fetch(`${base.replace(/\/$/,'')}/auth/v1/admin/users/${encodeURIComponent(found.id)}`,{method:'PUT',headers,body:JSON.stringify({app_metadata:{...(found.app_metadata||{}),role:'admin'}})});if(!r.ok){console.error('Unable to assign admin role.');process.exit(1)}console.log('Admin role assigned. Enroll MFA before using the console.');
