// Trusted, explicit provisioning. Never pass secrets as command-line arguments.
const base=process.env.SUPABASE_URL?.replace(/\/$/,''),service=process.env.SUPABASE_SERVICE_ROLE_KEY;
const userId=process.env.TROVAT1O_ADMIN_USER_ID,email=process.env.TROVAT1O_ADMIN_EMAIL?.trim().toLowerCase();
const action=process.env.TROVAT1O_ADMIN_ACTION||'grant';
if(!base||!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(base)||!service||!userId||!/^[0-9a-f-]{36}$/i.test(userId)||!email||!['grant','revoke'].includes(action)){
 console.error('Set private SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, TROVAT1O_ADMIN_USER_ID, TROVAT1O_ADMIN_EMAIL and optional TROVAT1O_ADMIN_ACTION=grant|revoke.');process.exit(2)
}
const headers={apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'};
const userUrl=`${base}/auth/v1/admin/users/${encodeURIComponent(userId)}`;
try{
 const lookup=await fetch(userUrl,{headers});if(!lookup.ok)throw new Error();const user=await lookup.json();
 if(user.id!==userId||user.email?.toLowerCase()!==email)throw new Error();
 if(action==='grant'&&(!user.email_confirmed_at||user.is_anonymous))throw new Error();
 const roleChange=await fetch(`${base}/rest/v1/rpc/provision_platform_admin`,{method:'POST',headers,body:JSON.stringify({p_user_id:userId,p_enabled:action==='grant'})});
 if(!roleChange.ok)throw new Error();
 // Metadata is only a navigation hint. The private database allowlist is the
 // permission source, including after revocation and before JWT refresh.
 const metadata={...(user.app_metadata||{})};if(action==='grant')metadata.role='admin';else if(metadata.role==='admin')delete metadata.role;
 const hint=await fetch(userUrl,{method:'PUT',headers,body:JSON.stringify({app_metadata:metadata})});
 if(!hint.ok){console.error('Database permission updated; navigation hint could not be updated. Retry the same action.');process.exit(1)}
 console.log(action==='grant'?'Admin permission assigned. Enroll and verify TOTP before opening the console.':'Admin permission revoked. Existing tokens cannot authorize further admin operations.');
}catch{console.error('Provisioning failed. Verify the selected account, private configuration and installed admin-security migration.');process.exit(1)}
