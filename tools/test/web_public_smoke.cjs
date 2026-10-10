// Read-only smoke checks for the owned public workspace; no account or data writes.
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
process.chdir(path.resolve(__dirname,'../..'));
(async()=>{
 const site=JSON.parse(fs.readFileSync('firebase.web.json','utf8')).hosting.site;
 const origin='https://'+site+'.web.app';
 const values=Object.fromEntries(fs.readFileSync('.env.production','utf8').split(/\r?\n/).filter(l=>l.trim()&&!l.trim().startsWith('#')).map(l=>{const i=l.indexOf('=');return [l.slice(0,i).trim(),l.slice(i+1).trim().replace(/^['"]|['"]$/g,'')];}));
 const base=values.SUPABASE_URL_PRODUCTION;
 if(base!=='https://dfczeudklykypysiseck.supabase.co')throw Error('Wrong production project');
 const response=await fetch(origin+'/');
 if(response.status!==200)throw Error('Public entry is not ready: '+response.status);
 const csp=response.headers.get('content-security-policy')||'';
 if(!csp.includes("script-src 'self' 'wasm-unsafe-eval'")||response.headers.get('x-frame-options')!=='DENY')throw Error('Security headers missing');
 const deployed=await (await fetch(origin+'/release-info.json')).json();
 const local=JSON.parse(fs.readFileSync('.artifacts/web-production-verification.json','utf8'));
 if(deployed.mainJsSha256!==local.mainJsSha256)throw Error('Public build does not match verified output');
 const js=Buffer.from(await (await fetch(origin+'/main.dart.js')).arrayBuffer());
 if(crypto.createHash('sha256').update(js).digest('hex')!==local.mainJsSha256)throw Error('Deployed JavaScript hash mismatch');
 const browser=await chromium.launch({channel:'msedge',headless:true});
 const errors=[],httpErrors=[],checks=['https_entry','security_headers','exact_verified_build'];
 let currentPage,currentPhase='entry';
 try {
  // A successful Auth settings fetch does not cover the headers on kitchen writes.
  const requiredHeaders=['authorization','apikey','content-type','idempotency-key'];
  for(const action of ['create-shopping-from-recipe','complete-shopping-list','cleanup-kitchen-workspace']) {
   const preflight=await fetch(base+'/functions/v1/recipe_api?type=kitchen&action='+action,{
    method:'OPTIONS',signal:AbortSignal.timeout(30000),headers:{
     Origin:origin,'Access-Control-Request-Method':'POST',
     'Access-Control-Request-Headers':requiredHeaders.join(','),
    },
   });
   const allowed=(preflight.headers.get('access-control-allow-headers')||'').toLowerCase().split(',').map(h=>h.trim());
   const methods=(preflight.headers.get('access-control-allow-methods')||'').toUpperCase().split(',').map(m=>m.trim());
   const allowedOrigin=preflight.headers.get('access-control-allow-origin');
   if(!preflight.ok||!requiredHeaders.every(h=>allowed.includes(h))||!methods.includes('POST')||![origin,'*'].includes(allowedOrigin))throw Error('Kitchen write CORS preflight rejected');
   await preflight.body?.cancel();
  }
  checks.push('kitchen_write_cors');
  for(const [locale,tag] of [['ko-KR','ko'],['en-US','en']]) {
   const page=await browser.newPage({viewport:{width:1440,height:1000},locale});
   currentPage=page;currentPhase=tag+'_home';
   page.on('pageerror',e=>errors.push(e.message));
   page.on('console',m=>{if(m.type()==='error')errors.push(m.text().slice(0,240));});
   page.on('response',r=>{if(r.status()>=400)httpErrors.push({status:r.status(),path:new URL(r.url()).pathname});});
   await page.goto(origin+'/',{waitUntil:'domcontentloaded',timeout:60000});
   await page.locator('#loading').waitFor({state:'detached',timeout:60000});
   if(await page.locator('flt-semantics-placeholder').count())await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());
   await page.getByRole('button',{name:tag==='ko'?'레시피 가져오기':'Import recipe',exact:true}).first().waitFor({timeout:20000});
   await page.waitForTimeout(1500);
   await page.screenshot({path:'.artifacts/web-public-'+tag+'-desktop.png'});
   await page.setViewportSize({width:390,height:844});await page.waitForTimeout(600);
   await page.screenshot({path:'.artifacts/web-public-'+tag+'-mobile.png'});
   checks.push(tag+'_desktop_mobile');
   await page.goto(origin+'/#/shopping',{waitUntil:'domcontentloaded'});
   currentPhase=tag+'_shopping_login';
   await page.locator('#loading').waitFor({state:'detached',timeout:60000});
   if(await page.locator('flt-semantics-placeholder').count())await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());
   // Flutter attaches the semantics action after the route's first frame.
   await page.waitForTimeout(700);
   await page.getByRole('button',{name:tag==='ko'?'로그인하고 장보기':'Sign in to shop',exact:true}).click();
   await page.getByLabel(tag==='ko'?'이메일':'Email',{exact:true}).waitFor();
   checks.push(tag+'_shopping_guard_and_login_page');
   for(const route of ['/shopping/organize','/shopping/organize?archived=true','/business-workspaces/00000000-0000-4000-8000-000000000001/organize']) {
    currentPhase=tag+'_'+route;
    await page.goto(origin+'/#'+route,{waitUntil:'domcontentloaded'});
    await page.locator('#loading').waitFor({state:'detached',timeout:60000});
    if(await page.locator('flt-semantics-placeholder').count())await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());
    await page.waitForTimeout(700);
    await page.getByRole('button',{name:tag==='ko'?'로그인':'Sign in',exact:true}).first().click();
    await page.getByLabel(tag==='ko'?'이메일':'Email',{exact:true}).waitFor();
   }
   checks.push(tag+'_cleanup_archive_and_business_guards');
   if(tag==='ko') {
    const auth=await page.evaluate(async({base,key})=>{
     const r=await fetch(base+'/auth/v1/settings',{headers:{apikey:key}});
     const d=await r.json();return {status:r.status,google:d.external?.google,kakao:d.external?.kakao};
    },{base,key:values.SUPABASE_ANON_KEY_PRODUCTION});
    if(auth.status!==200||!auth.google||!auth.kakao)throw Error('Production Auth/CORS not available');
    checks.push('production_auth_cors_and_providers');
   }
   await page.close();
  }
  if(errors.length||httpErrors.length)throw Error('Public browser issues: '+JSON.stringify({errors,httpErrors}));
  const report={origin,checkedAt:new Date().toISOString(),readOnly:true,passed:checks,consoleErrors:errors,httpErrors,
   appVersion:deployed.version,mainJsSha256:deployed.mainJsSha256,socialLoginRoundTrip:'not covered; requires actual account sign-in'};
  fs.writeFileSync('.artifacts/web-public-smoke.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify(report));
 } catch(error) {
  if(currentPage&&!currentPage.isClosed()) {
   await currentPage.screenshot({path:'.artifacts/web-public-smoke-failure.png'});
   fs.writeFileSync('.artifacts/web-public-smoke-failure.json',JSON.stringify({phase:currentPhase,url:currentPage.url(),semantics:await currentPage.locator('body').innerText()},null,2));
  }
  console.error(JSON.stringify({message:error.message,consoleErrors:errors,httpErrors}));
  throw error;
 } finally {await browser.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
