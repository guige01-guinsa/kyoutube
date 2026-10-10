-- Extend chef units without changing existing schema 1/2 documents or paid RLS.
create function public.chef_unit_valid(u text) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(u in ('g','kg','oz','lb','ml','l','tsp','tbsp','cup','fl_oz','pint','quart','gallon','each','piece','slice','clove','stalk','head','dozen','pack','bag','bottle','jar','can','carton','box','case','bundle','bunch','net','container','sachet','pouch','tube','tray','roll') or
  (left(u,7)='custom:' and length(substring(u from 8)) between 1 and 20
   and substring(u from 8)=btrim(substring(u from 8)) and u !~ '[[:cntrl:]]'),false);
$$;
revoke all on function public.chef_unit_valid(text) from public,anon,authenticated;

alter function public.chef_document_v1_valid(jsonb) rename to chef_document_v1_legacy_units_valid;
create function public.chef_document_v1_valid(d jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare item jsonb; normalized jsonb:='[]'; extended boolean:=false;
begin
 if d is null or jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>262144 or
    jsonb_typeof(d->'ingredients') is distinct from 'array' then return false; end if;
 if jsonb_array_length(d->'ingredients')>200 then return false; end if;
 if d ? 'unitFormat' and d->'unitFormat' is distinct from '1'::jsonb then return false; end if;
 for item in select value from jsonb_array_elements(d->'ingredients') loop
  if jsonb_typeof(item->'unit') is distinct from 'string' or
     jsonb_typeof(item->'purchaseUnit') is distinct from 'string' or
     not public.chef_unit_valid(item->>'unit') or not public.chef_unit_valid(item->>'purchaseUnit') or
     not public.chef_number_valid(item->'purchaseUnitInUsageUnits',0.000001,1000000000,true) then return false; end if;
  extended:=extended or item->>'unit' not in ('g','kg','ml','l','each') or
   item->>'purchaseUnit' not in ('g','kg','ml','l','each') or
   (item->'purchaseUnitInUsageUnits' is not null and item->'purchaseUnitInUsageUnits'<>'null'::jsonb);
  normalized:=normalized || jsonb_build_array(item || jsonb_build_object('unit','g','purchaseUnit','g'));
 end loop;
 if extended and d->'unitFormat' is distinct from '1'::jsonb then return false; end if;
 return public.chef_document_v1_legacy_units_valid(jsonb_set(d,'{ingredients}',normalized));
end;
$$;
revoke all on function public.chef_document_v1_valid(jsonb) from public,anon,authenticated;

create or replace function public.chef_cost_per_serving(d jsonb)
returns numeric language plpgsql immutable set search_path='' as $$
declare item jsonb; total numeric; factor numeric; u text; p text;
begin
 if not public.chef_document_valid(d) or d->>'baseServings' is null or
    d->>'targetServings' is null or jsonb_array_length(d->'ingredients')=0 then return null; end if;
 total:=(d->>'extraCost')::numeric;
 for item in select value from jsonb_array_elements(d->'ingredients') loop
  if item->>'quantity' is null or item->>'purchaseQuantity' is null or item->>'purchasePrice' is null then return null; end if;
  u:=item->>'unit'; p:=item->>'purchaseUnit';
  if u=p then factor:=1;
  elsif (u in ('g','kg') and p in ('g','kg')) or (u in ('ml','l') and p in ('ml','l')) then
   factor:=(case when u in ('kg','l') then 1000 else 1 end)::numeric /
    (case when p in ('kg','l') then 1000 else 1 end);
  elsif item->>'purchaseUnitInUsageUnits' is not null then
   factor:=1/(item->>'purchaseUnitInUsageUnits')::numeric;
  else return null;
  end if;
  total:=total+(item->>'quantity')::numeric/((item->>'yieldPercent')::numeric/100)
   *factor/(item->>'purchaseQuantity')::numeric*(item->>'purchasePrice')::numeric;
 end loop;
 return total/(d->>'baseServings')::numeric;
end;
$$;

-- Old apps parse unrecognized units as grams. Reject their writes after upgrade.
alter function public.save_chef_workspace(uuid,jsonb,bigint,text,text) rename to save_chef_workspace_pre_units;
revoke all on function public.save_chef_workspace_pre_units(uuid,jsonb,bigint,text,text) from public,anon,authenticated;
create function public.save_chef_workspace(p_recipe_id uuid,p_document jsonb,p_expected_revision bigint,
 p_version_label text default null,p_version_note text default '') returns bigint
language plpgsql security definer set search_path='' as $$
declare old_doc jsonb;
begin
 if auth.uid() is null then raise exception 'CHEF_LOGIN_REQUIRED'; end if;
 perform 1 from public.recipes_creator where id=p_recipe_id and author_id=auth.uid() for update;
 if not found then raise exception 'CHEF_RECIPE_NOT_OWNED'; end if;
 select document into old_doc from public.chef_workspaces where recipe_id=p_recipe_id and owner_id=auth.uid() for update;
 if old_doc->'unitFormat'='1'::jsonb and p_document->'unitFormat' is distinct from '1'::jsonb then
  raise exception 'CHEF_UPGRADE_REQUIRED';
 end if;
 return public.save_chef_workspace_pre_units(p_recipe_id,p_document,p_expected_revision,p_version_label,p_version_note);
end;
$$;
revoke all on function public.save_chef_workspace(uuid,jsonb,bigint,text,text) from public,anon;
grant execute on function public.save_chef_workspace(uuid,jsonb,bigint,text,text) to authenticated;
