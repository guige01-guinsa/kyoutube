// Verify the public buttons and real Supabase handoff without signing in.
// Stop at the provider redirect; do not store OAuth URLs, state, or credentials.
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path');
process.chdir(path.resolve(__dirname,'../..'));
let stage='setup';
(async()=>{
 const site=JSON.parse(fs.readFileSync('firebase.web.json','utf8')).hosting.site;
 const applied=JSON.parse(fs.readFileSync('.artifacts/web-auth-urls-applied.json','utf8'));
 if(!applied.verified||applied.site!==site)throw Error('Verified redirect configuration is required');
 const authOrigin='https://dfczeudklykypysiseck.supabase.co';
 const browser=await chromium.launch({channel:'msedge',headless:true});
 const checks=[];
 try {
  for(const host of ['web.app','firebaseapp.com']) {
   const origin='https://'+site+'.'+host;
   for(const [provider,label,providerHost] of [
    ['google','Google로 로그인','accounts.google.com'],
    ['kakao','카카오로 로그인','kauth.kakao.com'],
   ]) {
    stage=host+'/'+provider+'/open';
    const context=await browser.newContext({locale:'ko-KR'});
    try {
     let resolveHandoff,rejectHandoff;
     const handoff=new Promise((resolve,reject)=>{resolveHandoff=resolve;rejectHandoff=reject;});
     // Attach rejection handling immediately while the page starts.
     handoff.catch(()=>{});
     await context.route(authOrigin+'/auth/v1/authorize**',async route=>{
      try {
       stage=host+'/'+provider+'/parameters';
       const requestUrl=new URL(route.request().url());
       const query=requestUrl.searchParams;
       if(query.get('provider')!==provider||query.get('redirect_to')!==origin+'/')throw Error('Incorrect provider or web return address');
       if(query.get('code_challenge_method')?.toLowerCase()!=='s256'||(query.get('code_challenge')||'').length<43)throw Error('PKCE challenge missing');
       stage=host+'/'+provider+'/supabase-response';
       const response=await route.fetch({maxRedirects:0,timeout:30000});
       const location=new URL(response.headers().location||'https://invalid.invalid');
       if(response.status()!==302||location.hostname!==providerHost)throw Error('Provider handoff failed');
       if(location.searchParams.get('redirect_uri')!==authOrigin+'/auth/v1/callback')throw Error('Provider callback mismatch');
       await route.fulfill({status:200,contentType:'text/plain',body:'Read-only OAuth handoff verified. No account sign-in was performed.'});
       resolveHandoff({origin,provider,webReturnAddress:true,pkce:true,serverRedirectStatus:302,providerHost,providerCallback:true});
      }catch(error){await route.abort().catch(()=>{});rejectHandoff(error);}
     });
     const page=await context.newPage();
     await page.goto(origin+'/',{waitUntil:'domcontentloaded',timeout:60000});
     await page.locator('#loading').waitFor({state:'detached',timeout:60000});
     if(await page.locator('flt-semantics-placeholder').count())await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());
     await page.getByRole('button',{name:'로그인',exact:true}).first().click({timeout:20000});
     await page.getByRole('textbox',{name:'이메일',exact:true}).waitFor({timeout:20000});
     stage=host+'/'+provider+'/button';
     await page.getByRole('button',{name:label,exact:true}).click({timeout:20000});
     let timer;
     try {
      checks.push(await Promise.race([handoff,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('OAuth handoff timed out')),35000);})]));
     }finally{clearTimeout(timer);}
    }finally{await context.close();}
   }
  }
  const report={checkedAt:new Date().toISOString(),readOnly:true,scope:'Actual public button, PKCE parameters, and live Supabase provider redirect; stops before provider sign-in.',passed:checks,accountSignInVerified:false};
  fs.writeFileSync('.artifacts/web-oauth-entry.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify(report));
 }finally{await browser.close();}
})().catch(error=>{const known=['Incorrect provider or web return address','PKCE challenge missing','Provider handoff failed','Provider callback mismatch','OAuth handoff timed out'];console.error(JSON.stringify({failedAt:stage,reason:known.includes(error.message)?error.message:error.name}));process.exitCode=1;});
