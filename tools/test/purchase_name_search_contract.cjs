// Isolated in-memory PostgreSQL: never connects to any production database.
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {PGlite}=require('../../.artifacts/business-db-runtime/node_modules/@electric-sql/pglite');
const root=path.resolve(__dirname,'../..');
(async()=>{
 const db=new PGlite();await db.waitReady;let checks=0;
 const admin='11111111-1111-4111-8111-111111111111',member='22222222-2222-4222-8222-222222222222';
 const query=async(sql,args=[]) => (await db.query(sql,args)).rows;
 const ok=(condition)=>{assert.ok(condition, 'check '+(checks+1));checks++;};
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
 // Isolated fixtures for the business permission boundary; production uses business_can.
 const workspace='33333333-3333-4333-8333-333333333333',other='44444444-4444-4444-8444-444444444444';
 await db.exec(`create table public.business_suppliers(id uuid,workspace_id uuid,data jsonb);
 create table public.business_supplier_products(id uuid,workspace_id uuid,supplier_id uuid,data jsonb);
 create function public.business_can(w uuid,p text) returns boolean language sql as $$
 select coalesce(auth.uid()='${member}'::uuid and w='${workspace}'::uuid and p='purchasing.read',false)$$;`);
 await query('insert into public.business_suppliers values($1,$1,$2),($3,$3,$2)',[workspace,{name:'업소 전용',active:true},other]);
 await query('insert into public.business_supplier_products values(gen_random_uuid(),$1,$1,$2),(gen_random_uuid(),$3,$3,$4),(gen_random_uuid(),$1,$1,$5)',[workspace,{name:'돼지고기 목살',spec:'2kg',active:true},other,{name:'다른업소 비밀품목',active:true},{name:'비활성 품목',active:false}]);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/0082_purchase_name_search.sql'),'utf8'));
 const search=(q,offset=0,surface='web',scope=null)=>query('select * from public.search_purchase_names($1,$2,$3,$4)',[q,surface,offset,scope]);
 await login(admin);
 const data={program:'coupang',title:'한돈 앞다리살 500g',ingredients:['돼지고기 앞다리살'],specification:'500g',brand:'한돈',link:'https://link.coupang.com/a/TestSearch',published:true,product_verified:true,web_allowed:true,mobile_allowed:true,review_note:'Verified fixture permission and product specification',expires_at:new Date(Date.now()+86400000).toISOString()};
 const save=d=>query('select public.admin_save_shopping_affiliate($1,0)',[JSON.stringify(d)]);
 await save(data);
 await save({...data,title:'뒤쪽 1kg',ingredients:['돼지고기 뒷다리살'],link:'https://link.coupang.com/a/SearchBack'});
 for(let i=0;i<12;i++) await save({...data,title:'돼지고기 추가 '+i,ingredients:['돼지고기 품명 '+String(i).padStart(2,'0')],link:'https://link.coupang.com/a/Search'+i});
 await save({...data,ingredients:['숨김 앞다리살'],published:false,link:'https://link.coupang.com/a/SearchHidden'});
 await save({...data,ingredients:['모바일 앞다리살'],web_allowed:false,link:'https://link.coupang.com/a/SearchMobile'});
 await save({...data,ingredients:['만료 앞다리살'],link:'https://link.coupang.com/a/SearchExpired'});
 await db.exec("reset role; update public.shopping_affiliate_offers set expires_at=now()-interval '1 day' where ingredients @> array['만료 앞다리살'];");
 await login(member);
 ok((await search('앞다리살')).length===1);
 ok((await search('돼지고기앞다리살'))[0].name==='돼지고기 앞다리살');
 ok((await search('앞다리 돼지'))[0].name==='돼지고기 앞다리살');
 ok((await search('한돈 500')).some(r=>r.example_title==='한돈 앞다리살 500g'));
 const names=[];for(let offset=0;;offset+=5){const rows=await search('돼지',offset);names.push(...rows.slice(0,5).map(r=>r.name));if(rows.length<=5)break;}
 ok(names.length===14);ok(new Set(names).size===14);
 ok((await search('돼지고기 앞다리살'))[0].name==='돼지고기 앞다리살');
 ok((await search('앞다리',0,'mobile')).length===2);
 for(const q of ['', '   ', '%', '_', "' OR true --", '없는재료']) ok((await search(q)).length===0);
 await deny('select * from public.search_purchase_names($1,$2,$3)',['돼지','web',-1]);
 await deny('select * from public.search_purchase_names($1,$2,$3)',['x'.repeat(251),'web',0]);
 await deny('select * from public.search_purchase_names($1,$2,$3)',['돼지','invalid',0]);
 const rows=await search('앞다리');ok(Object.keys(rows[0]).sort().join(',')==='example_title,name');
 // Candidate discovery never broadens the exact lookup used by approval validation.
 ok((await query("select * from public.find_shopping_affiliates_v2('돼지','web')")).length===0);
 ok((await query("select * from public.find_shopping_affiliates_v2('돼지고기 앞다리살','web')")).length===1);
 ok((await search('목살')).length===0);
 ok((await search('목살',0,'web',workspace))[0].name==='돼지고기 목살');
 ok((await search('비밀',0,'web',workspace)).length===0);
 ok((await search('비활성',0,'web',workspace)).length===0);
 await deny('select * from public.search_purchase_names($1,$2,$3,$4)',['목살','web',0,other]);
 await login(member,'aal2',true);ok((await search('돼지')).length===0);
 await db.exec('reset role;set role anon');await deny("select * from public.search_purchase_names('돼지','web',0)");
 console.log('PASS: '+checks+' purchase-name database checks');
 } finally {await db.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
