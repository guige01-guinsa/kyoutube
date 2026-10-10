import {assertEquals,assertRejects} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {discoveryHandler,discoveryBody,parseDiscovery,safeSource,DiscoveryError} from './handler.ts';
const candidate={name:'Test Foods',website:'https://foods.example.com/',phone:'',products:'Onions',categories:['produce'],delivery_regions:[],shipping_note:'Delivery area needs confirmation',business_kind:'store',source_urls:['https://foods.example.com/delivery']};
function provider(suppliers:unknown[]=[candidate]) {return {status:'completed',output:[
  {type:'web_search_call',action:{sources:[{url:'https://foods.example.com/delivery'}]}},
  {type:'message',content:[{type:'output_text',text:JSON.stringify({suppliers})}]}],usage:{input_tokens:1000,output_tokens:400}};}
const request=(body:unknown={query:'seafood suppliers'},auth='Bearer test')=>new Request('https://local.test',{method:'POST',headers:{authorization:auth},body:JSON.stringify(body)});
Deno.test('search cannot call paid provider without administrator authorization',async()=>{
  let calls=0;
  const handler=discoveryHandler({key:()=> 'test',reserve:()=>Promise.reject(new DiscoveryError('admin_required',403)),finish:async()=>{},fetch:()=>{calls++;throw Error('unexpected');}});
  assertEquals((await handler(request())).status,403);assertEquals(calls,0);
  assertEquals((await handler(request({},''))).status,401);
});
Deno.test('MFA and quota failures preserve status, never expose backend details',async()=>{
  for(const [code,status] of [['admin_mfa_required',403],['search_quota',429]] as const){
    const handler=discoveryHandler({key:()=> 'test',reserve:()=>Promise.reject(new DiscoveryError(code,status)),finish:async()=>{}});
    assertEquals((await handler(request())).status,status);
  }
});
Deno.test('bounded input rejected before quota reservation',async()=>{
  let reservations=0;
  const h=discoveryHandler({key:()=> 'test',reserve:async()=>{reservations++;return 'r';},finish:async()=>{}});
  assertEquals((await h(request({query:'x'.repeat(121)}))).status,400);
  assertEquals((await h(request({query:'x'.repeat(3000)}))).status,413);
  assertEquals(reservations,0);
});
Deno.test('safe public references exclude private addresses and URL credentials',()=>{
  for(const u of ['http://example.com','https://localhost','https://127.0.0.1','https://a.internal','https://user:pass@example.com','javascript:alert(1)','https://a..com']) assertEquals(safeSource(u),null);
});
Deno.test('uncited and duplicate businesses are removed; shipping is never inferred',()=>{
  const result=parseDiscovery(provider([candidate,candidate,{...candidate,website:'https://invented.example.com/'}]));
  assertEquals(result.suppliers.length,1);assertEquals(result.suppliers[0].delivery_regions,[]);
  assertEquals(result.suppliers[0].checked_on,'');assertEquals(result.suppliers[0].status,'candidate');
});
Deno.test('completed research returns candidates only and records bounded usage',async()=>{
  const finishes:unknown[]=[];
  const h=discoveryHandler({key:()=> 'secret-test',reserve:async()=> 'r',finish:async(...args)=>{finishes.push(args);},fetch:async(url,init)=>{
    assertEquals(url,'https://api.openai.com/v1/responses');
    const body=JSON.parse(init!.body as string);assertEquals(body.store,false);assertEquals(body.max_tool_calls,2);
    return new Response(JSON.stringify(provider()));}});
  const r=await h(request());assertEquals(r.status,200);
  assertEquals((await r.json()).suppliers.length,1);
  assertEquals(finishes,[['r','succeeded',{input_tokens:1000,output_tokens:400,web_calls:1}]]);
});
Deno.test('upstream error is sanitized and reservation accounted for',async()=>{
  const finishes:unknown[]=[];
  const h=discoveryHandler({key:()=> 'never-print',reserve:async()=> 'r',finish:async(...a)=>{finishes.push(a);},fetch:async()=>new Response('sensitive provider error',{status:500})});
  const r=await h(request());assertEquals(r.status,502);assertEquals(await r.json(),{error:'search_unavailable'});assertEquals(finishes.length,1);
});
Deno.test('refusal/incomplete output cannot become business data',async()=>{
  await assertRejects(async()=>parseDiscovery({...provider(),status:'incomplete'}),DiscoveryError);
  await assertRejects(async()=>parseDiscovery({status:'completed',output:[]}),DiscoveryError);
  assertEquals(discoveryBody('onions').model,'gpt-5.4-mini');
});
Deno.test('browser preflight supports signed-in Supabase requests',async()=>{
  const h=discoveryHandler({key:()=>'',reserve:async()=>'',finish:async()=>{}});
  const r=await h(new Request('https://local.test',{method:'OPTIONS'}));
  assertEquals(r.status,200);assertEquals(r.headers.get('access-control-allow-methods'),'POST, OPTIONS');
  assertEquals(r.headers.get('cache-control'),'no-store');
});
