-- Keep raw financial documents inaccessible to free/expired accounts.
create function public.has_chef_paid_access() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.member_entitlements e join public.membership_plans p on p.code=e.plan_code
 where e.user_id=auth.uid() and p.is_active and e.plan_code in ('paid_monthly','paid_annual')
 and e.status in ('active','grace_period','canceled') and e.valid_until>now()
 and (e.started_at is null or e.started_at<=now()));
$$;
revoke all on function public.has_chef_paid_access() from public,anon;
grant execute on function public.has_chef_paid_access() to authenticated;

create function public.chef_free_document(d jsonb) returns jsonb
language sql immutable set search_path='' as $$
 select (d - 'costItems' - 'extraCost' - 'legacyExtraCost' - 'markupPercent') ||
 jsonb_build_object('extraCost',0,'legacyExtraCost',0,'costItems','[]'::jsonb,'markupPercent',0,
 'ingredients',coalesce((select jsonb_agg((x-'purchasePrice'-'purchaseQuantity') ||
 jsonb_build_object('purchasePrice',null,'purchaseQuantity',null)) from jsonb_array_elements(d->'ingredients') x),'[]'::jsonb));
$$;
revoke all on function public.chef_free_document(jsonb) from public,anon,authenticated;

alter policy chef_workspaces_read_own on public.chef_workspaces using(owner_id=auth.uid() and public.has_chef_paid_access());
alter policy chef_versions_read_own on public.chef_recipe_versions using(owner_id=auth.uid() and public.has_chef_paid_access());
alter policy chef_sales_read on public.chef_sales using(owner_id=auth.uid() and public.has_chef_paid_access());
alter policy chef_sales_edit on public.chef_sales using(owner_id=auth.uid() and public.has_chef_paid_access())
 with check(owner_id=auth.uid() and public.has_chef_paid_access());
alter policy chef_sales_remove on public.chef_sales using(owner_id=auth.uid() and public.has_chef_paid_access());

create function public.get_chef_workspace(p_recipe_id uuid) returns setof public.chef_workspaces
language sql stable security definer set search_path='' as $$
 select w.recipe_id,w.owner_id,case when public.has_chef_paid_access() then w.document else public.chef_free_document(w.document) end,
 w.revision,w.next_version,w.updated_at from public.chef_workspaces w where w.recipe_id=p_recipe_id and w.owner_id=auth.uid();
$$;
create function public.get_chef_versions(p_recipe_id uuid,p_before integer default null) returns setof public.chef_recipe_versions
language sql stable security definer set search_path='' as $$
 select v.recipe_id,v.owner_id,v.version_number,v.label,v.note,
 case when public.has_chef_paid_access() then v.document else public.chef_free_document(v.document) end,v.created_at
 from public.chef_recipe_versions v where v.recipe_id=p_recipe_id and v.owner_id=auth.uid()
 and (p_before is null or v.version_number<p_before) order by v.version_number desc limit 20;
$$;
revoke all on function public.get_chef_workspace(uuid),public.get_chef_versions(uuid,integer) from public,anon;
grant execute on function public.get_chef_workspace(uuid),public.get_chef_versions(uuid,integer) to authenticated;

alter function public.save_chef_workspace(uuid,jsonb,bigint,text,text) rename to save_chef_workspace_internal;
revoke all on function public.save_chef_workspace_internal(uuid,jsonb,bigint,text,text) from public,anon,authenticated;
create function public.save_chef_workspace(p_recipe_id uuid,p_document jsonb,p_expected_revision bigint,
 p_version_label text default null,p_version_note text default '') returns bigint
language plpgsql security definer set search_path='' as $$
declare d jsonb:=p_document; old_doc jsonb; item jsonb; old_item jsonb; items jsonb:='[]';
begin
 if auth.uid() is null then raise exception 'CHEF_LOGIN_REQUIRED'; end if;
 perform 1 from public.recipes_creator where id=p_recipe_id and author_id=auth.uid() for update;
 if not found then raise exception 'CHEF_RECIPE_NOT_OWNED'; end if;
 if not public.chef_document_valid(d) then raise exception 'CHEF_INVALID_DOCUMENT'; end if;
 if not public.has_chef_paid_access() then
  if d is distinct from public.chef_free_document(d) then raise exception 'CHEF_PAID_REQUIRED'; end if;
  select document into old_doc from public.chef_workspaces where recipe_id=p_recipe_id and owner_id=auth.uid() for update;
  if old_doc is not null then
   -- Preserve stored financial values across free edits; never erase them on expiry.
   d:=d || jsonb_build_object('currency',old_doc->'currency','extraCost',old_doc->'extraCost',
    'legacyExtraCost',coalesce(old_doc->'legacyExtraCost',old_doc->'extraCost'),'costItems',coalesce(old_doc->'costItems','[]'::jsonb),
    'markupPercent',coalesce(old_doc->'markupPercent','0'::jsonb));
   for item in select value from jsonb_array_elements(d->'ingredients') loop
    select value into old_item from jsonb_array_elements(old_doc->'ingredients') where value->>'id'=item->>'id';
    if old_item is not null then item:=item || jsonb_build_object('purchasePrice',old_item->'purchasePrice',
     'purchaseQuantity',old_item->'purchaseQuantity','purchaseUnit',old_item->'purchaseUnit'); end if;
    items:=items || jsonb_build_array(item);
   end loop;
   d:=jsonb_set(d,'{ingredients}',items);
  end if;
 end if;
 return public.save_chef_workspace_internal(p_recipe_id,d,p_expected_revision,p_version_label,p_version_note);
end;
$$;
revoke all on function public.save_chef_workspace(uuid,jsonb,bigint,text,text) from public,anon;
grant execute on function public.save_chef_workspace(uuid,jsonb,bigint,text,text) to authenticated;

alter function public.record_chef_sale(uuid,bigint,date,integer,text) rename to record_chef_sale_internal;
revoke all on function public.record_chef_sale_internal(uuid,bigint,date,integer,text) from public,anon,authenticated;
create function public.record_chef_sale(p_recipe_id uuid,p_expected_revision bigint,p_sale_date date,p_quantity integer,p_request_key text)
returns bigint language plpgsql security definer set search_path='' as $$
begin
 if not public.has_chef_paid_access() then raise exception 'CHEF_PAID_REQUIRED'; end if;
 return public.record_chef_sale_internal(p_recipe_id,p_expected_revision,p_sale_date,p_quantity,p_request_key);
end;
$$;
revoke all on function public.record_chef_sale(uuid,bigint,date,integer,text) from public,anon;
grant execute on function public.record_chef_sale(uuid,bigint,date,integer,text) to authenticated;
