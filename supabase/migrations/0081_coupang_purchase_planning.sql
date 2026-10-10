-- Product plans remain draft data; existing approval and receipt controls apply.
begin;
create function public.coupang_pack_quantity(p jsonb,u text) returns numeric
language plpgsql immutable set search_path='' as $$
declare f numeric:=1; t text:=lower(btrim(u)); result numeric;
begin
 if not public.affiliate_pack_valid(p) then return null;end if;
 t:=case t when '개' then 'ea' when 'each' then 'ea' when 'pcs' then 'ea' when '그램' then 'g' when '킬로그램' then 'kg' when '밀리리터' then 'ml' when '리터' then 'l' else t end;
 if p->>'unit' in ('g','kg') and t in ('g','kg') then
  f:=case when p->>'unit'='kg' then 1000 else 1 end::numeric/case when t='kg' then 1000 else 1 end;
 elsif p->>'unit' in ('ml','l') and t in ('ml','l') then
  f:=case when p->>'unit'='l' then 1000 else 1 end::numeric/case when t='l' then 1000 else 1 end;
 elsif p->>'unit'='ea' and t='ea' then f:=1;
 else return null;end if;
 result:=(p->>'amount')::numeric*(p->>'units_per_order')::numeric*f;
 if result<=0 or result>1e9 or result<>round(result,6) then return null;end if;
 return result;
exception when others then return null;
end;$$;
create function public.coupang_plan_valid(p jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare n numeric; size numeric;
begin
 if jsonb_typeof(p) is distinct from 'object' or jsonb_typeof(p->'offer') is distinct from 'object'
 or jsonb_typeof(p->'count') is distinct from 'number' or jsonb_typeof(p->'needed') is distinct from 'number'
 or jsonb_typeof(p->'unit') is distinct from 'string' or p->'offer'->>'program' is distinct from 'coupang'
 or not public.affiliate_link_valid('coupang',p->'offer'->>'link') then return false;end if;
 perform (p->'offer'->>'id')::uuid;
 if (p->'offer'->>'id') is null or coalesce((p->'offer'->>'revision')::bigint,0)<1 then return false;end if;
 n:=(p->>'count')::numeric;
 size:=public.coupang_pack_quantity(p->'offer'->'purchase_pack',p->>'unit');
 return size is not null and n between 1 and 1000000 and n=trunc(n) and n*size<=1e9
 and (p->>'needed')::numeric between 0.000001 and 1e9;
exception when others then return false;
end;$$;
alter function public.business_data_valid(text,jsonb) rename to business_data_valid_before_coupang;
create function public.business_data_valid(p_kind text,d jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare line jsonb; stripped jsonb:='[]';
begin
 if p_kind<>'purchase' then return public.business_data_valid_before_coupang(p_kind,d);end if;
 if exists(select 1 from jsonb_array_elements(d->'lines') l where l ? 'coupang') and
 (d->>'supplier' is distinct from '쿠팡' or exists(select 1 from jsonb_array_elements(d->'lines') l where not(l ? 'coupang'))) then return false;end if;
 for line in select value from jsonb_array_elements(d->'lines') loop
  if line ? 'coupang' then
   if not public.coupang_plan_valid(line->'coupang') or line->'quantity' is distinct from line->'coupang'->'count'
    or line->>'unit' is distinct from line->'coupang'->'offer'->'purchase_pack'->>'label' then return false;end if;
  end if;
  stripped:=stripped||jsonb_build_array(line-'coupang');
 end loop;
 return public.business_data_valid_before_coupang(p_kind,d||jsonb_build_object('lines',stripped));
exception when others then return false;
end;$$;
revoke all on function public.business_data_valid_before_coupang(text,jsonb),public.business_data_valid(text,jsonb),public.coupang_pack_quantity(jsonb,text),public.coupang_plan_valid(jsonb) from public,anon,authenticated;
create function public.business_menu_batch_coupang(p_workspace uuid,p_id uuid,p_sources jsonb,p_use_stock boolean,p_preview text,p_delivery date,p_confirmed boolean,p_choices jsonb,p_surface text)
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
   snap:=public.business_stock_action(p_workspace,gen_random_uuid(),'reserve',jsonb_build_object('item',row->'default'->>'stock_id','quantity',row->'stock','reason','메뉴 구매 준비 / Menu preparation '||p_delivery::text||' / '||p_id::text));
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
create function public.business_coupang_plan_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare line jsonb; prior jsonb; offer public.shopping_affiliate_offers; plan jsonb;
begin
 if new.kind<>'purchase' then return new;end if;
 for line in select value from jsonb_array_elements(new.data->'lines') where value ? 'coupang' loop
  prior:=null;
  if tg_op='UPDATE' then
   select l->'coupang' into prior from jsonb_array_elements(old.data->'lines') l where l->>'id'=line->>'id' and l->>'name'=line->>'name';
  end if;
  plan:=line->'coupang';
  if tg_op='INSERT' or prior is distinct from plan or (new.status in ('review','approved') and old.status is distinct from new.status) then
   select * into offer from public.shopping_affiliate_offers where id=(plan->'offer'->>'id')::uuid for share;
   if offer.id is null or not offer.published or not offer.product_verified or offer.deleted_at is not null or offer.expires_at<=now()
   or not(offer.mobile_allowed or offer.web_allowed) or not (offer.ingredients @> array[lower(btrim(line->>'name'))])
   or offer.revision is distinct from (plan->'offer'->>'revision')::bigint
   or offer.purchase_pack is distinct from plan->'offer'->'purchase_pack' or offer.link is distinct from plan->'offer'->>'link'
   or offer.title is distinct from plan->'offer'->>'title' or offer.specification is distinct from plan->'offer'->>'specification'
   then raise exception 'BUSINESS_COUPANG_CHANGED';end if;
  end if;
 end loop;
 return new;
end;$$;
revoke all on function public.business_coupang_plan_guard() from public,anon,authenticated;
create trigger business_coupang_plan_guard before insert or update on public.business_records
 for each row execute function public.business_coupang_plan_guard();
revoke all on function public.business_menu_batch_coupang(uuid,uuid,jsonb,boolean,text,date,boolean,jsonb,text) from public,anon;
grant execute on function public.business_menu_batch_coupang(uuid,uuid,jsonb,boolean,text,date,boolean,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
