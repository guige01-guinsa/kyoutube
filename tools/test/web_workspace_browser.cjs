// Local-only browser verification for the shared Flutter workspace.
// Requires the static preview on 127.0.0.1:8767, local Supabase/Edge Functions,
// Playwright with Edge, and SUPABASE_CLI or the configured Windows CLI path.
// Test credentials stay in memory; synthetic accounts are deleted in finally.
const path=require('node:path');
process.chdir(path.resolve(__dirname,'../..'));
const {chromium}=require('playwright');
const {execFileSync}=require('node:child_process');
const fs=require('node:fs');
const {randomUUID}=require('node:crypto');
(async()=>{
 fs.mkdirSync('.artifacts',{recursive:true});
 if(fs.existsSync('.artifacts/web-browser-verification.json'))fs.unlinkSync('.artifacts/web-browser-verification.json');
 const cfg=JSON.parse(execFileSync(process.env.SUPABASE_CLI || 'C:/Users/ADMIN/tools/supabase/supabase.exe',['status','-o','json'],{encoding:'utf8',stdio:['ignore','pipe','ignore']}));
 if(!['http://127.0.0.1:54321','http://localhost:54321'].includes(cfg.API_URL)) throw Error('Local only');
 const api=async(path,body,token=cfg.SERVICE_ROLE_KEY,method)=>{
   const r=await fetch(cfg.API_URL+path,{method:method??(body?'POST':'GET'),signal:AbortSignal.timeout(30000),headers:{apikey:cfg.ANON_KEY,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
   const text=await r.text(); const data=text?JSON.parse(text):null;
   if(!r.ok) throw Error(path.split('?')[0]+' '+r.status+' '+(data?.message??'')); return data;
 };
 const email='web-ui-'+randomUUID().slice(0,8)+'@example.test', password='Local-only-test-account-65!';
 let uid, p; const errors=[]; const b=await chromium.launch({channel:'msedge',headless:true});
 try {
   const user=await api('/auth/v1/admin/users',{email,password,email_confirm:true});uid=user.id;fs.writeFileSync('.artifacts/web-browser-fixture.json',JSON.stringify({id:uid,email}));
   await api('/rest/v1/profiles',{id:uid,role:'creator'});
   const rid=randomUUID();
   await api('/rest/v1/recipes_creator',{id:rid,author_id:uid,title:'테스트 당근구이',summary:'웹과 앱 공동 작업 검증용 레시피',ingredients:['당근 800 g'],steps:['당근을 손질합니다.','부드러워질 때까지 굽습니다.']});
   await api('/rest/v1/member_entitlements',{user_id:uid,plan_code:'business_monthly',status:'active',source:'admin',started_at:new Date().toISOString(),valid_until:new Date(Date.now()+86400000).toISOString()});
   const session=await api('/auth/v1/token?grant_type=password',{email,password},cfg.ANON_KEY);
   const doc={schema:1,title:'테스트 당근구이',steps:'당근을 손질합니다.\n부드러워질 때까지 굽습니다.',notes:'테스트용 자료',currency:'KRW',baseServings:4,targetServings:10,extraCost:1000,inputWeight:1000,outputWeight:750,ingredients:[{id:'carrots',name:'당근',quantity:800,unit:'g',purchaseQuantity:1,purchaseUnit:'kg',purchasePrice:8000,yieldPercent:80}]};
   await api('/rest/v1/rpc/save_chef_workspace',{p_recipe_id:rid,p_document:doc,p_expected_revision:0,p_version_label:null,p_version_note:''},session.access_token);
   const member=await api('/functions/v1/membership',{action:'status'},session.access_token);
   if(member.status!=='ok')throw Error('Local membership status failed');
   console.log('FIXTURE READY');
   p=await b.newPage({viewport:{width:1440,height:1000},locale:'ko-KR'});
   p.on('pageerror',e=>errors.push(e.message));
   p.on('response',r=>{if(r.status()>=400)console.log('HTTP ERROR',r.status(),new URL(r.url()).pathname);});
   p.on('console',m=>{if(m.type()==='error') errors.push(m.text().slice(0,180));});
   await p.goto('http://127.0.0.1:8767/',{waitUntil:'domcontentloaded',timeout:60000});
   console.log('PAGE LOADED');
   await p.locator('#loading').waitFor({state:'detached',timeout:60000});
   if(await p.locator('flt-semantics-placeholder').count()) await p.locator('flt-semantics-placeholder').evaluate(el=>el.click());
   await p.waitForLoadState('networkidle').catch(()=>{});
   await p.waitForTimeout(2500);
   await p.screenshot({path:'.artifacts/web-desktop-ko.png'});
   console.log('HOME', (await p.locator('body').innerText()).slice(0,3500));
   await p.getByRole('button',{name:'로그인',exact:true}).first().click();
   await p.getByRole('textbox',{name:'이메일',exact:true}).click();
   await p.waitForTimeout(250);
   await p.keyboard.type(email,{delay:20});
   await p.waitForTimeout(250);
   await p.getByLabel('비밀번호',{exact:true}).click();
   await p.waitForTimeout(250);
   await p.keyboard.type(password,{delay:15});
   await p.waitForTimeout(250);
   await p.getByRole('button',{name:'로그인',exact:true}).last().click();
   try {await p.getByRole('button',{name:/^테스트 당근구이/}).waitFor({timeout:30000});}
   catch(error) {
     if(!await p.getByRole('button',{name:'다시 시도',exact:true}).count()) throw error;
     await p.getByRole('button',{name:'다시 시도',exact:true}).click();
     await p.getByRole('button',{name:/^테스트 당근구이/}).waitFor({timeout:60000});
   }
   await p.screenshot({path:'.artifacts/web-signed-in.png'});
   await p.getByRole('button',{name:/^테스트 당근구이/}).click();
   await p.getByRole('textbox',{name:'목표 인분',exact:true}).waitFor({timeout:30000});
   const target=p.getByRole('textbox',{name:'목표 인분',exact:true});
   console.log('TARGET BOX',await target.boundingBox());
   await target.focus();
   await p.waitForTimeout(250);
   await p.keyboard.press('ControlOrMeta+A');
   await p.keyboard.type('20',{delay:50});
   await p.waitForTimeout(750);
   console.log('AFTER EDIT',(await p.locator('body').innerText()).slice(0,3000));
   await p.screenshot({path:'.artifacts/web-after-edit.png'});
   const saving=p.waitForResponse(r=>r.url().includes('/rpc/save_chef_workspace') && r.request().method()==='POST').catch(()=>null);
   await p.getByRole('button',{name:'작업 저장',exact:true}).last().focus();
   await p.keyboard.press('Enter');
   const saved=await saving;
   if(!saved || saved.status()!==200) throw Error('Browser save failed');
   await p.waitForTimeout(500);
   const shared=await api('/rest/v1/rpc/get_chef_workspace',{p_recipe_id:rid},session.access_token);
   if(shared[0].document.targetServings!==20 || shared[0].revision!==2) throw Error('Browser save did not reach shared backend');
   await p.keyboard.press('Tab');
   await p.waitForTimeout(4000);
   await p.screenshot({path:'.artifacts/web-chef-desktop.png'});
   console.log('CHEF', (await p.locator('body').innerText()).slice(0,4500));
   await p.setViewportSize({width:390,height:844}); await p.waitForTimeout(1000);
   await p.screenshot({path:'.artifacts/web-chef-mobile.png'});
   await p.setViewportSize({width:1440,height:1000});
   const memberResponse=p.waitForResponse(r=>new URL(r.url()).pathname==='/functions/v1/membership' && r.request().method()==='POST',{timeout:60000}).catch(()=>null);
   await p.evaluate(()=>{window.location.hash='/membership';});
   const memberResult=await memberResponse;
   if(!memberResult || memberResult.status()!==200)throw Error('Browser membership status failed');
   if(await p.getByText('Google Play 구독 복원',{exact:true}).count()) throw Error('Native restore shown on web');
   await p.getByText('웹에서는 기존 회원권을 사용할 수 있습니다. 신규 결제는 준비 중입니다.',{exact:false}).first().waitFor();
   if(await p.getByRole('button',{name:'Google Play에서 구독',exact:true}).count())throw Error('Native checkout shown on web');
   await p.screenshot({path:'.artifacts/web-membership.png'});
   await p.mouse.move(1100,750);
   await p.mouse.wheel(0,1500);
   await p.waitForTimeout(1000);
   await p.getByRole('button',{name:'Google Play에서 구독 관리·해지',exact:true}).waitFor({timeout:8000});
   if(await p.getByText('Google Play 구독 복원',{exact:true}).count())throw Error('Native restore shown at end of web page');
   const en=await b.newPage({viewport:{width:1440,height:1000},locale:'en-US'});
   await en.goto('http://127.0.0.1:8767/',{waitUntil:'networkidle'});
   await en.locator('#loading').waitFor({state:'detached',timeout:60000});
   if(await en.locator('flt-semantics-placeholder').count()) await en.locator('flt-semantics-placeholder').evaluate(el=>el.click());
   await en.getByRole('button',{name:'Sign in',exact:true}).first().waitFor();
   await en.waitForTimeout(1000);
   await en.screenshot({path:'.artifacts/web-desktop-en.png'});
   await en.setViewportSize({width:390,height:844}); await en.waitForTimeout(700);
   await en.screenshot({path:'.artifacts/web-mobile-en.png'});
   console.log('ENGLISH', (await en.locator('body').innerText()).slice(0,1800));
   if(errors.length) throw Error('Browser console errors: '+JSON.stringify(errors));
   fs.writeFileSync('.artifacts/web-browser-verification.json',JSON.stringify({environment:'local-only',passed:['email_password_sign_in','creator_recipes_loaded','browser_edit_saved_to_shared_backend','chef_desktop','chef_mobile','membership_status_and_web_checkout_notice','english_desktop','english_mobile'],consoleErrors:errors,fixtureAccountRemovedOnExit:false},null,2));
   console.log('BROWSER CHECKS PASSED');

 } catch(e) { console.log('FAILURE',e.message); console.log('BROWSER ERRORS',JSON.stringify(errors)); if(p) { console.log('BODY',(await p.locator('body').innerText()).slice(0,4500)); console.log('ACCESSIBILITY',(await p.locator('body').ariaSnapshot()).slice(0,6500)); await p.screenshot({path:'.artifacts/web-auth-failure.png'}); } throw e; } finally {try {await b.close();} finally {if(uid) {await api('/auth/v1/admin/users/'+uid,undefined,undefined,'DELETE');fs.writeFileSync('.artifacts/web-browser-fixture.json',JSON.stringify({removed:true})); if(fs.existsSync('.artifacts/web-browser-verification.json')){const report=JSON.parse(fs.readFileSync('.artifacts/web-browser-verification.json','utf8'));report.fixtureAccountRemovedOnExit=true;fs.writeFileSync('.artifacts/web-browser-verification.json',JSON.stringify(report,null,2));}}}}
})();
