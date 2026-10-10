// Isolated in-memory PostgreSQL: never connects to any production database.
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {PGlite}=require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite');
const root=path.resolve(__dirname,'../..');
(async()=>{
 const db=new PGlite();await db.waitReady;let checks=0;
 const admin='11111111-1111-4111-8111-111111111111',member='22222222-2222-4222-8222-222222222222';
 const query=async(sql,args=[]) => (await db.query(sql,args)).rows;
 const ok=(condition)=>{assert.ok(condition);checks++;};
 const deny=async(sql,args=[])=>{let denied=false;try{await query(sql,args);}catch(_){denied=true;}ok(denied);};
 const login=async(id,aal='aal2',anon=false)=>{await db.exec('reset role');await query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,aal,is_anonymous:anon})]);await db.exec('set role authenticated');};
 try {
 await db.exec(`create role anon;create role authenticated;create schema auth;
 create table auth.users(id uuid primary key);insert into auth.users values('${admin}'),('${member}');
 create table public.profiles(id uuid,role text);insert into public.profiles values('${admin}','admin');
 create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql as $$select (auth.jwt()->>'sub')::uuid$$;
 grant usage on schema auth to authenticated;`);
 const previous=fs.readFileSync(path.join(root,'supabase/migrations/0060_public_supplier_listings.sql'),'utf8');
 await db.exec(previous.match(/create function public.assert_supplier_directory_admin\(\)[\s\S]*?\$\$;/)[0]);
 await db.exec('revoke all on function public.assert_supplier_directory_admin() from public,anon,authenticated;');
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0065_shopping_affiliate_offers.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0071_affiliate_catalog_management.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0080_coupang_sale_packs.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0088_coupang_product_images.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0089_affiliate_import_image_default.sql'),'utf8'));
 const save='select public.admin_save_shopping_affiliate($1::jsonb,$2) id';
 const find='select * from public.find_shopping_affiliates($1,$2)';
 const data={program:'naver',title:'Test ingredient',specification:'500g',ingredients:['춘장','black bean paste'],link:'https://naver.me/Example1',published:false,mobile_allowed:false,web_allowed:false,review_note:'',expires_at:new Date(Date.now()+86400000).toISOString()};
 await login(member);await deny(save,[JSON.stringify(data),0]);await deny('select * from public.admin_shopping_affiliates()');
 await login(admin,'aal1');await deny(save,[JSON.stringify(data),0]);await deny('select * from public.admin_shopping_affiliates()');
 await login(admin);const id=(await query(save,[JSON.stringify(data),0]))[0].id;ok(!!id);
 await deny(save,[JSON.stringify({...data,id}),null]);
 await deny('select * from public.shopping_affiliate_offers');await deny("update public.shopping_affiliate_offers set published=true");
 ok((await query(find,['춘장','web'])).length===0);
 await deny(save,[JSON.stringify({...data,id,published:true}),1]);
 await deny(save,[JSON.stringify({...data,id,published:true,web_allowed:true}),1]);
 const pub={...data,id,published:true,web_allowed:true,review_note:'Permission verified for website on test date'};
 await query(save,[JSON.stringify(pub),1]);
 await deny(save,[JSON.stringify(pub),1]);
 await login(member);const rows=await query(find,[' 춘장 ','web']);ok(rows.length===1);ok(!('review_note' in rows[0]));ok(rows[0].link===data.link);
 ok((await query(find,['BLACK BEAN PASTE','web'])).length===1);
 ok((await query(find,['춘장','mobile'])).length===0);ok((await query(find,['쌀','web'])).length===0);
 ok((await query(find,["' OR true --",'web'])).length===0);ok((await query(find,['춘장','invalid'])).length===0);
 await login(member,'aal2',true);ok((await query(find,['춘장','web'])).length===0);
 await db.exec('reset role;set role anon');await deny(find,['춘장','web']);
 await login(admin);
 for(const link of ['http://naver.me/a','https://naver.me.evil.example/a','https://naver.me@evil.example/a','https://127.0.0.1/a','https://search.shopping.naver.com/search/all?query=test','javascript:alert(1)']) await deny(save,[JSON.stringify({...pub,link}),2]);
 await deny(save,[JSON.stringify({...pub,expires_at:new Date(Date.now()+100*86400000).toISOString()}),2]);
 await deny(save,[JSON.stringify({...pub,expires_at:new Date(Date.now()-86400000).toISOString()}),2]);
 const video={...data,program:'youtube',link:'https://www.youtube.com/watch?v=abcdefghijk',published:true,web_allowed:true,review_note:'Own channel, tagged products and permission verified'};
 await query(save,[JSON.stringify(video),0]);ok((await query(find,['춘장','web'])).length===2);
 await query(save,[JSON.stringify({...pub,published:false}),2]);ok((await query(find,['춘장','web'])).length===1);
 await db.exec("reset role;update public.shopping_affiliate_offers set expires_at=now()-interval '1 hour'");
 await login(member);ok((await query(find,['춘장','web'])).length===0);

 await login(admin);
 const item={...data,program:'coupang',link:'https://link.coupang.com/a/Test1',category:'Spices',source_code:'001'};
 const cid=(await query(save,[JSON.stringify(item),0]))[0].id;
 ok((await query('select * from public.admin_shopping_affiliates()')).every(x=>x.program!=='coupang'));
 await deny(save,[JSON.stringify(item),0]);
 await deny(save,[JSON.stringify({...item,id:cid,published:true,web_allowed:true,review_note:'Placement checked on date'}),1]);
 await query(save,[JSON.stringify({...item,id:cid,published:true,web_allowed:true,review_note:'Placement checked on date',product_verified:true}),1]);
 ok((await query(find,['black bean paste','web'])).length===1);
 const page=(await query("select public.admin_shopping_affiliate_page('Spices','published',0,25) data"))[0].data;
 ok(page.total===1 && page.rows[0].id===cid);
 await deny("select public.admin_shopping_affiliate_page('',null,0,25)");
 await deny('select * from public.shopping_affiliate_history');
 await query("select public.admin_change_shopping_affiliate($1,2,'delete')",[cid]);
 ok((await query(find,['black bean paste','web'])).length===0);
 await deny("select public.admin_change_shopping_affiliate($1,2,'restore')",[cid]);
 await deny(save,[JSON.stringify({...item,id:cid}),3]);
 ok((await query("select public.admin_shopping_affiliate_page('','trash',0,25) data"))[0].data.total===1);
 await query("select public.admin_change_shopping_affiliate($1,3,'restore')",[cid]);
 ok((await query(find,['black bean paste','web'])).length===0);
 const preview=(await query('select public.admin_preview_shopping_affiliates($1) data',[JSON.stringify([item])]))[0].data;
 ok(preview[0].id===cid && preview[0].revision===4);
 const imported=(await query('select public.admin_import_shopping_affiliates($1) data',[JSON.stringify([
 {action:'create',data:item},
 {action:'create',data:{...item,link:'https://evil.test/a'}},
 {action:'create',data:{...item,link:'https://link.coupang.com/a/Test2',published:true,product_verified:true}},
 {action:'update',data:{...item,id:cid,revision:1}},
 {action:'update',data:{...item,id:cid,revision:4,title:'Updated item'}},
 ])]))[0].data;
 ok(imported.map(x=>x.status).join(',')==='duplicate,invalid,saved,stale,saved');
 const history=await query('select * from public.admin_shopping_affiliate_history($1)',[cid]);
 ok(history.length===5 && history.some(x=>x.action==='delete') && history.some(x=>x.action==='restore'));
 const all=(await query("select public.admin_shopping_affiliate_page('','active',0,100) data"))[0].data;
 ok(all.rows.every(x=>x.program!=='coupang'||(!x.published&&!x.product_verified)));

 await deny("select public.admin_change_shopping_affiliate($1,5,null)",[cid]);
 await deny("select public.admin_preview_shopping_affiliates(null)");
 await deny('select public.admin_import_shopping_affiliates($1)',[JSON.stringify(Array(101).fill({action:'create',data:item}))]);
 await deny(save,[JSON.stringify({...item,link:'https://link.coupang.com/a/BadAlias',ingredients:['valid','']}),0]);
 await deny(save,[JSON.stringify({...item,link:'https://link.coupang.com/a/BadType',ingredients:[123]}),0]);
 const many=Array.from({length:52},(_,i)=>({action:'create',data:{...item,title:'Paged '+i,link:'https://link.coupang.com/a/Page'+i}}));
 ok((await query('select public.admin_import_shopping_affiliates($1) data',[JSON.stringify(many)]))[0].data.every(x=>x.status==='saved'));
 const first=(await query("select public.admin_shopping_affiliate_page('Paged','active',0,25) data"))[0].data;
 const second=(await query("select public.admin_shopping_affiliate_page('Paged','active',25,25) data"))[0].data;
 ok(first.total===52 && second.total===52 && first.rows.length===25 && second.rows.length===25);
 ok(first.rows.every(x=>!second.rows.some(y=>x.id===y.id)));
 ok((await query("select public.admin_shopping_affiliate_page('Paged','active',50,25) data"))[0].data.rows.length===2);
 const repeated=(await query('select public.admin_import_shopping_affiliates($1) data',[JSON.stringify(many)]))[0].data;
 ok(repeated.every(x=>x.status==='duplicate'));
 // Imports omit image_url: new rows default to blank; edits retain the image.
 const photo='https://image.coupangcdn.com/image/test/ingredient.jpg';
 const pictured={...item,title:'Image regression',link:'https://link.coupang.com/a/ImageTest',image_url:photo};
 const photoId=(await query(save,[JSON.stringify(pictured),0]))[0].id;
 const {image_url:unused,...withoutImage}=pictured;
 const editResult=(await query('select public.admin_import_shopping_affiliates($1) data',[JSON.stringify([{action:'update',data:{...withoutImage,id:photoId,revision:1}}])]))[0].data;
 ok(editResult[0].status==='saved');
 const photoRow=async()=> (await query("select public.admin_shopping_affiliate_page('Image regression','active',0,25) data"))[0].data.rows.find(x=>x.id===photoId);
 ok((await photoRow()).image_url===photo);
 await query(save,[JSON.stringify({...withoutImage,id:photoId,link:'https://link.coupang.com/a/ImageChanged'}),2]);
 ok((await photoRow()).image_url==='');
 await deny(save,[JSON.stringify({...item,link:'https://link.coupang.com/a/InvalidImage',image_url:'https://example.com/image.jpg'}),0]);
 await login(member);
 for(const rpc of ["admin_shopping_affiliate_page()","admin_preview_shopping_affiliates('[]')","admin_import_shopping_affiliates('[]')",`admin_shopping_affiliate_history('${cid}')`,`admin_change_shopping_affiliate('${cid}',5,'delete')`]) await deny('select public.'+rpc);
 await login(admin,'aal1'); await deny("select public.admin_import_shopping_affiliates('[]')");
 await login(admin);
 await db.exec('reset role');await query('delete from auth.users where id=$1',[admin]);
 ok((await query('select updated_by from public.shopping_affiliate_offers')).every(r=>r.updated_by===null));
 console.log('PASS: '+checks+' catalog database checks');
 } finally {await db.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
