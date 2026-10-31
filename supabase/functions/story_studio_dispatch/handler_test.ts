import {createDispatchHandler} from './handler.ts';
const request=()=>new Request('https://example.test/dispatch',{method:'POST',headers:{Authorization:'Bearer fixture'},body:JSON.stringify({job_id:'11111111-1111-4111-8111-111111111111'})});
function assert(value:unknown) {if(!value)throw new Error('assertion failed');}
Deno.test('missing configuration preserves queue and does not claim or call GitHub',async()=>{
 let calls=0;const h=createDispatchHandler({token:'',authorize:async()=>{calls++;return true;}});
 assert((await h(request())).status===503);assert(calls===0);
});
Deno.test('one approved dispatch cannot repeat or choose another repository',async()=>{
 let claims=0,calls=0;const h=createDispatchHandler({token:'fixture',authorize:async()=>++claims===1,
 fetcher:async(input,init)=>{calls++;assert(String(input).endsWith('/guige01-guinsa/kyoutube/actions/workflows/story-studio-worker.yml/dispatches'));
 const inputs=JSON.parse(String(init?.body)).inputs;
 assert(inputs.dry_run===false);assert(inputs.job_id==='11111111-1111-4111-8111-111111111111');return new Response(null,{status:204});}});
 assert((await h(request())).status===200);assert((await h(request())).status===200);assert(calls===1);
});
Deno.test('authorization rejection and uncertain network never disclose or retry',async()=>{
 let calls=0;const denied=createDispatchHandler({token:'fixture',authorize:async()=>{throw new Error('private');},fetcher:async()=>{calls++;throw new Error('secret');}});
 assert(!(await (await denied(request())).text()).includes('private'));assert(calls===0);
 const uncertain=createDispatchHandler({token:'fixture',authorize:async()=>true,fetcher:async()=>{calls++;throw new Error('secret');}});
 const result=await uncertain(request());assert(result.status===503);assert(!(await result.text()).includes('secret'));assert(calls===1);
});
