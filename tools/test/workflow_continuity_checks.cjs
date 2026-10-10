// Runs against the disposable database created by business_workspaces_contract.cjs.
module.exports=async ({db,q,scalar,denied,ok,login,crypto,fs,root,workspace,owner,buyer,other})=>{
 const path=require('path'),id=()=>crypto.randomUUID();
 await db.exec('reset role');
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0083_workflow_continuity.sql'),'utf8'));
 ok(true,'workflow recovery migration compiles');
 await login(owner);
 for(const [from,to,want] of [['g','kg',.001],['kg','그램',1000],['mL','L',.001],['리터','ml',1000],['ea','개',1],['봉','봉',1],['g','ml',null],['박스','g',null],['','g',null]]) {
  const got=await scalar('select public.business_unit_factor($1,$2)',[from,to]);
  ok(want===null?got===null:Number(got)===want,`unit factor ${from}/${to}`);
 }
 const recipe=await scalar("select public.business_save_record($1,$2,'recipe','환산 연결 검증',$3,0)",[workspace,id(),{servings:1,ingredients:'',steps:'조리',notes:'',ingredient_lines:[{name:'환산 양파 A',spec:'',unit:'g',quantity:1500},{name:'환산 양파 B',spec:'',unit:'g',quantity:1000}]}]);
 const review=await scalar("select public.business_recipe_review($1,$2,$3,0,'testing','시험 완료')",[workspace,recipe.id,recipe.revision]);
 await scalar("select public.business_recipe_review($1,$2,$3,$4,'approved','출시 승인')",[workspace,recipe.id,recipe.revision,review.id]);
 const menu=await scalar('select public.business_menu_save($1,$2,0,$3)',[workspace,id(),{name:'환산 검증',category:'',description:'',price:5000,currency:'KRW',recipe_id:recipe.id,recipe_revision:recipe.revision,status:'on_sale'}]);
 const sources=[{kind:'menu',id:menu.id,revision:menu.revision,servings:1}];
 const sup=await scalar('select public.business_supplier_save($1,$2,0,$3)',[workspace,id(),{name:'환산 공급처',contact:'',phone:'',address:'',website:'',active:true}]);
 const prod=await scalar('select public.business_supplier_product_save($1,$2,$3,0,$4)',[workspace,sup.id,id(),{name:'환산 양파',spec:'',content_quantity:500,content_unit:'g',pack_unit:'봉',active:true}]);
 const stock=await scalar("select public.business_stock_action($1,$2,'item',$3)",[workspace,id(),{name:'환산 양파',spec:'',unit:'kg'}]);
 await scalar("select public.business_stock_action($1,$2,'adjust',$3)",[workspace,id(),{item:stock.id,quantity:2,reason:'실사'}]);
 const mapping=name=>({ingredient:{name,spec:'',unit:'g'},supplier:sup.id,supplier_revision:1,product:prod.id,product_revision:1,factor:1,stock:stock.id,confirmed:true});
 for(const name of ['환산 양파 A','환산 양파 B']) await scalar('select public.business_ingredient_default_save($1,0,$2)',[workspace,mapping(name)]);
 ok(true,'g recipe links to kg inventory without changing stock identity');
 let view=await scalar('select public.business_menu_fast_preview($1,$2,true)',[workspace,sources]);
 ok(view.rows.every(r=>r.ready&&r.stock_unit==='kg'&&Number(r.stock_factor)===.001),'preview carries verified stock conversion');
 ok(view.rows.reduce((n,r)=>n+Number(r.stock),0)===2000,'shared stock allocated once in ingredient units');
 ok(view.rows.reduce((n,r)=>n+Number(r.stock_quantity),0)===2,'reservations expressed in physical stock units');
 const date=await scalar('select current_date::text');
 const token=id(),args=[workspace,token,sources,true,view.fingerprint,date,true];
 const batch=await scalar('select public.business_menu_batch_create($1,$2,$3,$4,$5,$6,$7)',args);
 const balance=(await scalar('select public.business_stock_overview($1)',[workspace])).find(r=>r.id===stock.id);
 ok(Number(balance.reserved)===2&&Number(balance.available)===0,'batch reserves two kg, never 2000 kg');
 const again=await scalar('select public.business_menu_batch_create($1,$2,$3,$4,$5,$6,$7)',args);
 ok(again.id===batch.id,'converted batch retry remains idempotent');
 await login(other); await denied('select public.owner_stock_recovery($1,$2,null)',[workspace,stock.id],'MANAGEMENT_DENIED','outsider cannot inspect dependencies');
 await login(buyer); await denied('select public.owner_stock_recovery($1,$2,null)',[workspace,stock.id],'MANAGEMENT_DENIED','only owner can inspect deletion dependencies');
 await login(owner);
 const related=await scalar('select public.owner_stock_recovery($1,$2,null)',[workspace,stock.id]);
 ok(related.some(r=>r.kind==='stock'&&r.id===stock.id),'blocked reservation links to exact inventory item');
 // Another batch takes the Coupang-aware path with the same compatible inventory link.
 await scalar("select public.business_stock_action($1,$2,'adjust',$3)",[workspace,id(),{item:stock.id,quantity:1,reason:'추가 실사'}]);
 view=await scalar('select public.business_menu_fast_preview($1,$2,true)',[workspace,sources]);
 await scalar('select public.business_menu_batch_coupang($1,$2,$3,true,$4,$5,true,$6,$7)',[workspace,id(),sources,view.fingerprint,date,{},'web']);
 ok(Number((await scalar('select public.business_stock_overview($1)',[workspace])).find(r=>r.id===stock.id).reserved)===3,'Coupang-aware batch also reserves kg quantities');
 // Sub-resolution stock never erases unmet ingredient demand.
 await scalar("select public.business_stock_action($1,$2,'adjust',$3)",[workspace,id(),{item:stock.id,quantity:.000001,reason:'소량 실사'}]);
 const tinySources=sources;
 const tiny=await scalar('select public.business_menu_fast_preview($1,$2,true)',[workspace,tinySources]);
 ok(tiny.rows.every(r=>Number(r.stock_quantity)>=0&&Number(r.stock)<=Number(r.required)), 'tiny allocation never exceeds required quantity');
 ok(tiny.rows.reduce((n,r)=>n+Number(r.stock_quantity),0)<=.000001,'tiny shared stock allocation stays within real balance');
 ok(tiny.rows.some(r=>Number(r.required)>Number(r.stock)&&Number(r.packs)>0),'sub-resolution remainder remains a purchase need');
 const stale=await scalar('select public.business_menu_fast_preview($1,$2,true)',[workspace,sources]);
 await scalar("select public.business_stock_action($1,$2,'adjust',$3)",[workspace,id(),{item:stock.id,quantity:1,reason:'잔량 변경'}]);
 await denied('select public.business_menu_batch_create($1,$2,$3,true,$4,$5,true)',[workspace,id(),sources,stale.fingerprint,date],'FAST_CHANGED','changed stock balance requires a fresh preview');
 await q("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:owner,aal:'aal2',is_anonymous:false})]);
 const offer={program:'coupang',title:'복구 테스트',specification:'500g',ingredients:['양파'],link:'https://link.coupang.com/a/Recovery'+id().replaceAll('-',''),review_note:'Verified test product and publication',mobile_allowed:true,web_allowed:true,published:false,product_verified:true,expires_at:new Date(Date.now()+86400000).toISOString()};
 const oid=await scalar('select public.admin_save_shopping_affiliate($1,0)',[offer]);
 let found=await scalar('select public.admin_affiliate_recovery(null,$1,$2)',[offer.program,offer.link]);
 ok(found.id===oid,'exact duplicate recovery finds offer by destination');
 await scalar("select public.admin_change_shopping_affiliate($1,1,'delete')",[oid]);
 found=await scalar('select public.admin_affiliate_recovery($1,null,null)',[oid]);
 ok(found.deleted_at!==null,'recovery includes trashed offer for explicit restore');
 await login(buyer);await denied('select public.admin_affiliate_recovery($1,null,null)',[oid],null,'non-admin cannot use recovery lookup');
};
