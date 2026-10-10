import {createReadinessHandler,integrationChecks} from './handler.ts';
const eq=(a:unknown,b:unknown)=>{if(JSON.stringify(a)!==JSON.stringify(b))throw Error('Mismatch');};
Deno.test('readiness needs administrator MFA and never returns secret values',async()=>{
 let reads=0;
 const denied=createReadinessHandler({authorize:async()=>false,getEnv:()=>{reads++;return 'secret';}});
 eq((await denied(new Request('https://local',{headers:{authorization:'Bearer test'}}))).status,403);eq(reads,0);
 const allowed=createReadinessHandler({authorize:async()=>true,getEnv:()=>'PRIVATE_KEY_VALUE'});
 const res=await allowed(new Request('https://local',{headers:{authorization:'Bearer test'}}));
 eq(res.status,200);eq((await res.text()).includes('PRIVATE_KEY_VALUE'),false);
 eq((await allowed(new Request('https://local'))).status,401);
});
Deno.test('readiness distinguishes complete accounts from nonempty malformed secrets',()=>{
 const results=integrationChecks(()=>'{invalid}');
 eq(results.find(r=>r.id==='play_billing')!.configured,false);
 eq(results.find(r=>r.id==='operations_push')!.configured,false);
 const configured=integrationChecks(n=>n.includes('SERVICE_ACCOUNT_JSON')?JSON.stringify({client_email:'worker@project.iam.gserviceaccount.com',private_key:'BEGIN PRIVATE KEY',project_id:'project'}):'x'.repeat(32));
 eq(configured.find(r=>r.id==='play_billing')!.configured,true);
 eq(configured.find(r=>r.id==='operations_push')!.configured,true);
});
