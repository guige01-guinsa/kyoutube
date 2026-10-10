begin;
-- Discovery only. Exact affiliate matching and purchase validation are unchanged.
create function public.search_purchase_names(p_query text, p_surface text, p_offset integer default 0, p_workspace uuid default null)
returns table(name text, example_title text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' then return; end if;
 if p_query is null or length(p_query)>250 or p_surface not in ('web','mobile')
    or p_surface is null or p_offset is null or p_offset<0 then
   raise exception 'SEARCH_INVALID';
 end if;
 if p_workspace is not null and not coalesce(public.business_can(p_workspace,'purchasing.read'),false) then
   raise exception 'BUSINESS_DENIED';
 end if;
 if btrim(p_query)='' then return; end if;
 return query
 with candidates as (
   select i.value as ingredient, o.title,
     lower(regexp_replace(concat_ws(' ',i.value,o.title,o.brand,o.specification), '\s+', '', 'g')) as haystack
   from public.shopping_affiliate_offers o
   cross join lateral unnest(o.ingredients) i(value)
   where o.program='coupang' and o.deleted_at is null and o.published
     and o.expires_at>now() and length(btrim(i.value)) between 1 and 200
     and ((p_surface='web' and o.web_allowed) or (p_surface='mobile' and o.mobile_allowed))
   union all
   select p.data->>'name', concat_ws(' · ',s.data->>'name',p.data->>'spec'),
     lower(regexp_replace(concat_ws(' ',p.data->>'name',p.data->>'spec',s.data->>'name'), '\s+', '', 'g'))
   from public.business_supplier_products p
   join public.business_suppliers s on s.id=p.supplier_id and s.workspace_id=p.workspace_id
   where p_workspace is not null and p.workspace_id=p_workspace
     and p.data->>'active'='true' and s.data->>'active'='true'
 ), matches as (
   select c.ingredient, min(c.title) as sample from candidates c
   where not exists (
     select 1 from regexp_split_to_table(lower(btrim(p_query)), '\s+') w(word)
     where strpos(c.haystack,w.word)=0
   ) group by c.ingredient
 )
 select m.ingredient,m.sample from matches m
 order by case when lower(regexp_replace(m.ingredient,'\s+','','g'))=
                    lower(regexp_replace(p_query,'\s+','','g')) then 0 else 1 end,
          m.ingredient collate "C"
 limit 6 offset p_offset;
end; $$;
revoke all on function public.search_purchase_names(text,text,integer,uuid) from public,anon;
grant execute on function public.search_purchase_names(text,text,integer,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
