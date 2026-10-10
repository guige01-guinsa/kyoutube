-- Workflow recovery and dimensionally compatible inventory links.
-- Only new functions/replacements; existing records keep their identities.
begin;
create or replace function public.business_unit_factor(p_from text,p_to text) returns numeric
language plpgsql immutable set search_path='' as $$
declare a text:=lower(btrim(p_from)); b text:=lower(btrim(p_to));
begin
 if coalesce(a,'')='' or coalesce(b,'')='' then return null;end if;
 if a=b then return 1;end if;
 a:=case a when '그램' then 'g' when '킬로그램' then 'kg' when '밀리리터' then 'ml' when '리터' then 'l' when 'ea' then '개' when 'each' then '개' when 'pcs' then '개' else a end;
 b:=case b when '그램' then 'g' when '킬로그램' then 'kg' when '밀리리터' then 'ml' when '리터' then 'l' when 'ea' then '개' when 'each' then '개' when 'pcs' then '개' else b end;
 if a=b then return 1;end if;
 if (a='g' and b='kg') or (a='ml' and b='l') then return 0.001;end if;
 if (a='kg' and b='g') or (a='l' and b='ml') then return 1000;end if;
 return null;
end;$$;
revoke all on function public.business_unit_factor(text,text) from public,anon;
grant execute on function public.business_unit_factor(text,text) to authenticated;
create or replace function public.business_ingredient_default_save(p_workspace uuid,p_revision bigint,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare k text; ing jsonb; s public.business_suppliers; p public.business_supplier_products; old public.business_ingredient_defaults;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') or not public.business_can(p_workspace,'recipes.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_revision is null or p_revision<0 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>4096
 or exists(select 1 from jsonb_object_keys(p_data) x where x not in ('ingredient','supplier','supplier_revision','product','product_revision','factor','stock','confirmed'))
 or p_data->'confirmed' is distinct from 'true' or not public.business_menu_number_valid(p_data->'factor',0.000001,1e9) then raise exception 'BUSINESS_INVALID';end if;
 ing:=p_data->'ingredient';
 if jsonb_typeof(ing) is distinct from 'object' or exists(select 1 from jsonb_object_keys(ing) x where x not in ('name','spec','unit'))
 or not public.business_ingredient_lines_valid(jsonb_build_array(ing||jsonb_build_object('quantity',1))) then raise exception 'BUSINESS_INVALID';end if;
 k:=encode(extensions.digest(jsonb_build_array(lower(btrim(ing->>'name')),lower(btrim(ing->>'spec')),lower(btrim(ing->>'unit')))::text,'sha256'),'hex');
 select * into s from public.business_suppliers where id=(p_data->>'supplier')::uuid and workspace_id=p_workspace and data->'active'='true';
 select * into p from public.business_supplier_products where id=(p_data->>'product')::uuid and workspace_id=p_workspace and supplier_id=s.id and data->'active'='true';
 if s.id is null or p.id is null then raise exception 'SUPPLIER_UNAVAILABLE';end if;
 if to_jsonb(s.revision) is distinct from p_data->'supplier_revision' or to_jsonb(p.revision) is distinct from p_data->'product_revision' then raise exception 'BUSINESS_STALE';end if;
 if (p_data->>'factor')::numeric*(p.data->>'content_quantity')::numeric>1e9
 or round((p_data->>'factor')::numeric*(p.data->>'content_quantity')::numeric,6)<>(p_data->>'factor')::numeric*(p.data->>'content_quantity')::numeric then raise exception 'SUPPLIER_PACK';end if;
 if lower(btrim(ing->>'unit'))=lower(btrim(p.data->>'content_unit')) and (p_data->>'factor')::numeric<>1 then raise exception 'SUPPLIER_UNIT';end if;
 if p_data->>'stock' is not null and not exists(select 1 from public.business_stock_items i where i.workspace_id=p_workspace and i.id=(p_data->>'stock')::uuid and public.business_unit_factor(ing->>'unit',i.unit) is not null) then raise exception 'SUPPLIER_UNIT';end if;
 select * into old from public.business_ingredient_defaults where workspace_id=p_workspace and ingredient_key=k;
 if coalesce(old.revision,0)<>p_revision then raise exception 'BUSINESS_STALE';end if;
 if old.ingredient_key is null and (select count(*) from public.business_ingredient_defaults where workspace_id=p_workspace)>=1000 then raise exception 'BUSINESS_LIMIT';end if;
 insert into public.business_ingredient_defaults(workspace_id,ingredient_key,ingredient,supplier_id,product_id,supplier_revision,product_revision,factor,stock_id,updated_by)
 values(p_workspace,k,ing,s.id,p.id,s.revision,p.revision,(p_data->>'factor')::numeric,(p_data->>'stock')::uuid,auth.uid())
 on conflict(workspace_id,ingredient_key) do update set ingredient=excluded.ingredient,supplier_id=excluded.supplier_id,product_id=excluded.product_id,supplier_revision=excluded.supplier_revision,product_revision=excluded.product_revision,factor=excluded.factor,stock_id=excluded.stock_id,revision=business_ingredient_defaults.revision+1,updated_at=now(),updated_by=auth.uid() returning * into old;
 return to_jsonb(old);
end;$$;
create or replace function public.business_menu_fast_preview(p_workspace uuid,p_sources jsonb,p_use_stock boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare plan jsonb; req jsonb; d public.business_ingredient_defaults; s public.business_suppliers; p public.business_supplier_products;
 rows jsonb:='[]'; available numeric; taken numeric; packs numeric; size numeric; ready boolean; balance jsonb; used jsonb:='{}'; duplicate_count integer; result jsonb; stock_unit text; stock_factor numeric; stock_taken numeric; stock_available numeric;
begin
 if p_use_stock is null then raise exception 'BUSINESS_INVALID';end if;
 plan:=public.business_menu_plan(p_workspace,'operations',p_sources);
 for req in select value from jsonb_array_elements(plan->'requirements') loop
  select * into d from public.business_ingredient_defaults where workspace_id=p_workspace and ingredient_key=req->>'key';
  select * into s from public.business_suppliers where id=d.supplier_id and workspace_id=p_workspace;
  select * into p from public.business_supplier_products where id=d.product_id and workspace_id=p_workspace and supplier_id=s.id;
  ready:=coalesce(d.ingredient_key is not null and s.data->'active'='true' and p.data->'active'='true' and s.revision=d.supplier_revision and p.revision=d.product_revision,false);
  available:=0;taken:=0;size:=null;packs:=null;stock_taken:=0;stock_factor:=null;stock_unit:=null;
  if d.stock_id is not null then
   select i.unit into stock_unit from public.business_stock_items i where i.workspace_id=p_workspace and i.id=d.stock_id;
   stock_factor:=public.business_unit_factor(req->>'unit',stock_unit);
   if stock_factor is null then ready:=false;
   else
    balance:=public.business_stock_balance(p_workspace,d.stock_id);
    stock_available:=greatest(0,(balance->>'available')::numeric-coalesce((used->>d.stock_id::text)::numeric,0));
    available:=least(1e9,trunc(stock_available/stock_factor,6));
    if p_use_stock then
     -- Round down only stock allocation; unmet need stays in purchase quantity.
     stock_taken:=trunc(least(available,(req->>'required')::numeric)*stock_factor,6);
     taken:=stock_taken/stock_factor;
    end if;
    used:=jsonb_set(used,array[d.stock_id::text],to_jsonb(stock_taken+coalesce((used->>d.stock_id::text)::numeric,0)));
   end if;
  end if;
  if ready then size:=d.factor*(p.data->>'content_quantity')::numeric;packs:=ceil(greatest(0,(req->>'required')::numeric-taken)/size);end if;
  select count(*)::int into duplicate_count from public.business_purchase_bases b join public.business_records r on r.id=b.request_id
  where b.workspace_id=p_workspace and r.status in ('draft','review','approved','sent')
  and exists(select 1 from jsonb_array_elements(b.adjustments) a where a->>'key'=req->>'key' and a->'include'='true');
  rows:=rows||jsonb_build_array(req||jsonb_build_object('default',case when d.ingredient_key is null then null else to_jsonb(d) end,'supplier',case when s.id is null then null else to_jsonb(s) end,'product',case when p.id is null then null else to_jsonb(p) end,'ready',ready,'available',available,'stock',taken,'stock_quantity',stock_taken,'stock_unit',stock_unit,'stock_factor',stock_factor,'pack_size',size,'packs',packs,'open_requests',duplicate_count));
 end loop;
 result:=jsonb_build_object('sources',plan->'sources','rows',rows,'use_stock',p_use_stock);
 return result||jsonb_build_object('fingerprint',encode(extensions.digest(result::text,'sha256'),'hex'));
end;$$;
create or replace function public.business_menu_batch_before_meals(p_workspace uuid,p_id uuid,p_sources jsonb,p_use_stock boolean,p_preview text,p_delivery date,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare prior public.business_menu_batches; fingerprint text; view jsonb; row jsonb; supplier_id uuid; adjustments jsonb; adj jsonb; result jsonb;
 r jsonb; req_id uuid; reservations jsonb:='[]'; requests jsonb:='[]'; snap jsonb; lines jsonb; line jsonb; idx integer; products jsonb;
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') or not public.business_can(p_workspace,'recipes.read') or not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_confirmed is distinct from true or p_delivery is null or p_delivery<current_date or p_delivery>current_date+365 then raise exception 'BUSINESS_INVALID';end if;
 fingerprint:=encode(extensions.digest(jsonb_build_array(p_sources,p_use_stock,p_preview,p_delivery)::text,'sha256'),'hex');
 select * into prior from public.business_menu_batches where id=p_id;
 if prior.id is not null then
  if prior.workspace_id<>p_workspace or prior.actor_id is distinct from auth.uid() or prior.fingerprint<>fingerprint then raise exception 'BUSINESS_STALE';end if;
  return prior.result;
 end if;
 if (select count(*) from public.business_menu_batches where workspace_id=p_workspace and created_at>now()-interval '1 hour')>=100 then raise exception 'BUSINESS_LIMIT';end if;
 view:=public.business_menu_fast_preview(p_workspace,p_sources,p_use_stock);
 if view->>'fingerprint' is distinct from p_preview then raise exception 'FAST_CHANGED';end if;
 if exists(select 1 from jsonb_array_elements(view->'rows') a where a->'ready' is distinct from 'true') then raise exception 'FAST_MAPPING_REQUIRED';end if;
 for row in select value from jsonb_array_elements(view->'rows') loop
  if (row->>'stock')::numeric>0 then
   snap:=public.business_stock_action(p_workspace,gen_random_uuid(),'reserve',jsonb_build_object('item',row->'default'->>'stock_id','quantity',row->'stock_quantity','reason','메뉴 구매 준비 / Menu preparation '||p_delivery::text||' / '||p_id::text));
   reservations:=reservations||jsonb_build_array(jsonb_build_object('id',snap->'id','item',snap->'item_id','quantity',snap->'quantity'));
  end if;
 end loop;
 for supplier_id in select distinct (a->'supplier'->>'id')::uuid from jsonb_array_elements(view->'rows') a where (a->>'packs')::numeric>0 order by 1 loop
  adjustments:='[]';products:='[]';lines:='[]';idx:=0;
  for row in select value from jsonb_array_elements(view->'rows') loop
   adj:=jsonb_build_object('key',row->>'key','include',row->'supplier'->>'id'=supplier_id::text);
   if row->'supplier'->>'id'=supplier_id::text then
    adj:=adj||jsonb_build_object('stock',row->'stock','incoming',0,'pack_size',row->'pack_size','pack_unit',row->'product'->'data'->>'pack_unit','confirmed',true);
    products:=products||jsonb_build_array(jsonb_build_object('key',row->>'key','id',row->'product'->'id','revision',row->'product'->'revision','data',row->'product'->'data','factor',row->'default'->'factor'));
   end if;
   adjustments:=adjustments||jsonb_build_array(adj);
  end loop;
  req_id:=gen_random_uuid();
  select a->'supplier' into snap from jsonb_array_elements(view->'rows') a where a->'supplier'->>'id'=supplier_id::text limit 1;
  r:=public.business_menu_purchase_before_meals(p_workspace,req_id,'operations',p_sources,adjustments,snap->'data'->>'name');
  for row in select value from jsonb_array_elements(view->'rows') loop
   if row->'supplier'->>'id'=supplier_id::text and (row->>'packs')::numeric>0 then
    line:=r->'data'->'lines'->idx;idx:=idx+1;
    lines:=lines||jsonb_build_array(line||jsonb_build_object('name',row->'product'->'data'->>'name','spec',left(concat_ws(' / ',row->>'name',row->>'spec',row->'product'->'data'->>'spec',(row->>'pack_size')||' '||(row->>'unit')),300)));
   end if;
  end loop;
  r:=public.business_save_record(p_workspace,req_id,'purchase','메뉴 구매 / Menu purchase '||p_delivery::text,r->'data'||jsonb_build_object('delivery_date',p_delivery::text,'lines',lines),(r->>'revision')::bigint);
  insert into public.business_purchase_supplier_snapshots(request_id,workspace_id,supplier,products,input_hash,actor_id) values(req_id,p_workspace,snap,products,fingerprint,auth.uid());
  requests:=requests||jsonb_build_array(jsonb_build_object('id',req_id,'supplier',snap->'data'->>'name','revision',r->'revision'));
 end loop;
 result:=jsonb_build_object('id',p_id,'requests',requests,'reservations',reservations);
 insert into public.business_menu_batches(id,workspace_id,actor_id,fingerprint,sources,preview,result,delivery_date) values(p_id,p_workspace,auth.uid(),fingerprint,p_sources,view,result,p_delivery);
 return result;
end;$$;
create or replace function public.business_menu_batch_coupang(p_workspace uuid,p_id uuid,p_sources jsonb,p_use_stock boolean,p_preview text,p_delivery date,p_confirmed boolean,p_choices jsonb,p_surface text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare prior public.business_menu_batches; fingerprint text; view jsonb; row jsonb; supplier_id uuid; adjustments jsonb; adj jsonb; result jsonb;
 r jsonb; req_id uuid; reservations jsonb:='[]'; requests jsonb:='[]'; snap jsonb; lines jsonb; line jsonb; idx integer; products jsonb; choice jsonb; item jsonb; transformed jsonb:='[]'; cp constant uuid:='00000000-0000-4000-8000-000000000001';
begin
 perform 1 from public.business_workspaces where id=p_workspace for update;
 if not public.business_can(p_workspace,'purchasing.write') or not public.business_can(p_workspace,'recipes.read') or not public.business_can(p_workspace,'purchasing.read') then raise exception 'BUSINESS_DENIED';end if;
 if p_id is null or p_confirmed is distinct from true or p_delivery is null or p_delivery<current_date or p_delivery>current_date+365 then raise exception 'BUSINESS_INVALID';end if;
 fingerprint:=encode(extensions.digest(jsonb_build_array(p_sources,p_use_stock,p_preview,p_delivery,p_choices,p_surface)::text,'sha256'),'hex');
 select * into prior from public.business_menu_batches where id=p_id;
 if prior.id is not null then
  if prior.workspace_id<>p_workspace or prior.actor_id is distinct from auth.uid() or prior.fingerprint<>fingerprint then raise exception 'BUSINESS_STALE';end if;
  return prior.result;
 end if;
 if jsonb_typeof(p_choices) is distinct from 'object' or octet_length(p_choices::text)>131072 or p_surface not in ('web','mobile') then raise exception 'BUSINESS_INVALID';end if;
 if exists(select 1 from jsonb_array_elements(p_sources) x join public.business_meal_purchase_links l on l.meal_id=(x->>'id')::uuid where x->>'kind'='meal') then raise exception 'MEAL_PURCHASE_LINKED';end if;
 if (select count(*) from public.business_menu_batches where workspace_id=p_workspace and created_at>now()-interval '1 hour')>=100 then raise exception 'BUSINESS_LIMIT';end if;
 view:=public.business_menu_fast_preview(p_workspace,p_sources,p_use_stock);
 if view->>'fingerprint' is distinct from p_preview then raise exception 'FAST_CHANGED';end if;
 if exists(select 1 from jsonb_object_keys(p_choices) k where not exists(select 1 from jsonb_array_elements(view->'rows') v where v->>'key'=k)) then raise exception 'BUSINESS_INVALID';end if;
 for row in select value from jsonb_array_elements(view->'rows') loop
  choice:=p_choices->(row->>'key');
  if choice is not null then
   if not public.coupang_plan_valid(choice) or choice->>'unit'<>row->>'unit'
   or (choice->>'needed')::numeric<>greatest(0,(row->>'required')::numeric-(row->>'stock')::numeric) then raise exception 'BUSINESS_COUPANG_CHANGED';end if;
   if not exists(select 1 from public.find_shopping_affiliates_v2(row->>'name',p_surface) o
    where o.id=(choice->'offer'->>'id')::uuid and o.revision=(choice->'offer'->>'revision')::bigint
    and o.purchase_pack=choice->'offer'->'purchase_pack' and o.link=choice->'offer'->>'link') then raise exception 'BUSINESS_COUPANG_CHANGED';end if;
   select to_jsonb(o) into item from public.find_shopping_affiliates_v2(row->>'name',p_surface) o where o.id=(choice->'offer'->>'id')::uuid;
   choice:=jsonb_set(choice,'{offer}',item);
   row:=row||jsonb_build_object('coupang',choice,'ready',true,'packs',choice->'count',
    'pack_size',public.coupang_pack_quantity(choice->'offer'->'purchase_pack',row->>'unit'),
    'supplier',jsonb_build_object('id',cp,'data',jsonb_build_object('name','쿠팡')),
    'product',jsonb_build_object('id',choice->'offer'->'id','revision',choice->'offer'->'revision',
     'data',jsonb_build_object('name',choice->'offer'->>'title','spec',choice->'offer'->>'specification','pack_unit',choice->'offer'->'purchase_pack'->>'label')));
  end if;
  transformed:=transformed||jsonb_build_array(row);
 end loop;
 view:=view||jsonb_build_object('rows',transformed);
 if exists(select 1 from jsonb_array_elements(view->'rows') a where a->'ready' is distinct from 'true') then raise exception 'FAST_MAPPING_REQUIRED';end if;
 for row in select value from jsonb_array_elements(view->'rows') loop
  if (row->>'stock')::numeric>0 then
   snap:=public.business_stock_action(p_workspace,gen_random_uuid(),'reserve',jsonb_build_object('item',row->'default'->>'stock_id','quantity',row->'stock_quantity','reason','메뉴 구매 준비 / Menu preparation '||p_delivery::text||' / '||p_id::text));
   reservations:=reservations||jsonb_build_array(jsonb_build_object('id',snap->'id','item',snap->'item_id','quantity',snap->'quantity'));
  end if;
 end loop;
 for supplier_id in select distinct (a->'supplier'->>'id')::uuid from jsonb_array_elements(view->'rows') a where (a->>'packs')::numeric>0 order by 1 loop
  adjustments:='[]';products:='[]';lines:='[]';idx:=0;
  for row in select value from jsonb_array_elements(view->'rows') loop
   adj:=jsonb_build_object('key',row->>'key','include',row->'supplier'->>'id'=supplier_id::text);
   if row->'supplier'->>'id'=supplier_id::text then
    adj:=adj||jsonb_build_object('stock',row->'stock','incoming',0,'pack_size',row->'pack_size','pack_unit',row->'product'->'data'->>'pack_unit','confirmed',true);
    products:=products||jsonb_build_array(jsonb_build_object('key',row->>'key','id',row->'product'->'id','revision',row->'product'->'revision','data',row->'product'->'data','factor',row->'default'->'factor'));
   end if;
   adjustments:=adjustments||jsonb_build_array(adj);
  end loop;
  req_id:=gen_random_uuid();
  select a->'supplier' into snap from jsonb_array_elements(view->'rows') a where a->'supplier'->>'id'=supplier_id::text limit 1;
  if supplier_id=cp then
   for row in select value from jsonb_array_elements(view->'rows') where value ? 'coupang' loop
    choice:=row->'coupang';
    lines:=lines||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'name',row->>'name','spec',left(concat_ws(' / ',row->>'spec',choice->'offer'->>'specification'),300),
      'quantity',choice->'count','unit',choice->'offer'->'purchase_pack'->>'label','price',null,'coupang',choice));
   end loop;
   r:=public.business_save_record(p_workspace,req_id,'purchase','쿠팡 구매 / Coupang purchase '||p_delivery::text,
    jsonb_build_object('supplier','쿠팡','buyer',(select name from public.business_workspaces where id=p_workspace),'phone','','address','','delivery_date',p_delivery::text,'notes','쿠팡 판매 옵션과 수량을 확인한 구매 계획 / Verified sale-option plan','currency','KRW','lines',lines),0);
   insert into public.business_purchase_bases(request_id,workspace_id,purpose,sources,requirements,adjustments,input_hash,actor_id)
    values(req_id,p_workspace,'operations',view->'sources',(select jsonb_agg(v-'default'-'supplier'-'product') from jsonb_array_elements(view->'rows') v),adjustments,fingerprint,auth.uid());
  else
  r:=public.business_menu_purchase_before_meals(p_workspace,req_id,'operations',p_sources,adjustments,snap->'data'->>'name');
  for row in select value from jsonb_array_elements(view->'rows') loop
   if row->'supplier'->>'id'=supplier_id::text and (row->>'packs')::numeric>0 then
    line:=r->'data'->'lines'->idx;idx:=idx+1;
    lines:=lines||jsonb_build_array(line||jsonb_build_object('name',row->'product'->'data'->>'name','spec',left(concat_ws(' / ',row->>'name',row->>'spec',row->'product'->'data'->>'spec',(row->>'pack_size')||' '||(row->>'unit')),300)));
   end if;
  end loop;
  r:=public.business_save_record(p_workspace,req_id,'purchase','메뉴 구매 / Menu purchase '||p_delivery::text,r->'data'||jsonb_build_object('delivery_date',p_delivery::text,'lines',lines),(r->>'revision')::bigint);
  insert into public.business_purchase_supplier_snapshots(request_id,workspace_id,supplier,products,input_hash,actor_id) values(req_id,p_workspace,snap,products,fingerprint,auth.uid());
  end if;
  requests:=requests||jsonb_build_array(jsonb_build_object('id',req_id,'supplier',snap->'data'->>'name','revision',r->'revision'));
 end loop;
 result:=jsonb_build_object('id',p_id,'requests',requests,'reservations',reservations);
 insert into public.business_menu_batches(id,workspace_id,actor_id,fingerprint,sources,preview,result,delivery_date) values(p_id,p_workspace,auth.uid(),fingerprint,p_sources,view,result,p_delivery);
 for item in select value from jsonb_array_elements(p_sources) where value->>'kind'='meal' loop
  insert into public.business_meal_purchase_links values(p_workspace,(item->>'id')::uuid,p_id);
 end loop;
 return result;
end;$$;

-- Exact lookup including trash. Uses the same admin + MFA gate as editing.
create function public.admin_affiliate_recovery(p_id uuid default null,p_program text default null,p_link text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform public.assert_supplier_directory_admin();
 if p_id is null and (p_program is null or p_link is null or length(p_link)>2048) then raise exception 'AFFILIATE_INVALID';end if;
 select to_jsonb(o) into result from public.shopping_affiliate_offers o
 where (p_id is not null and o.id=p_id) or (p_id is null and o.program=p_program and o.link=p_link) limit 1;
 return result;
end;$$;
revoke all on function public.admin_affiliate_recovery(uuid,text,text) from public,anon;
grant execute on function public.admin_affiliate_recovery(uuid,text,text) to authenticated;

create function public.owner_stock_recovery(p_workspace uuid,p_id uuid,p_target_unit text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; item public.business_stock_items;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 or not exists(select 1 from public.business_workspaces where id=p_workspace and owner_id=auth.uid())
 or not public.business_can(p_workspace,'purchasing.write') then raise exception 'MANAGEMENT_DENIED';end if;
 select * into item from public.business_stock_items where workspace_id=p_workspace and id=p_id;
 if item.id is null then raise exception 'MANAGEMENT_DELETED';end if;
 select coalesce(jsonb_agg(x),'[]') into result from (
  select 'stock' kind,item.id id,item.name title
  union all
  select 'request',r.id,r.title from public.business_records r where r.workspace_id=p_workspace
   and exists(select 1 from public.business_stock_events e where e.workspace_id=p_workspace and e.item_id=p_id and e.request_id=r.id)
  union all
  select 'stock',s.id,s.name||' · '||s.unit from public.business_stock_items s where s.workspace_id=p_workspace and s.id<>p_id
   and lower(btrim(s.name))=lower(btrim(item.name)) and lower(btrim(s.spec))=lower(btrim(item.spec)) and lower(btrim(s.unit))=lower(btrim(p_target_unit))
 ) x;
 return result;
end;$$;
revoke all on function public.owner_stock_recovery(uuid,uuid,text) from public,anon;
grant execute on function public.owner_stock_recovery(uuid,uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
