-- Verified sale options, compatible-unit arithmetic and old-client compatibility.
begin;
create function public.affiliate_pack_valid(p jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare n numeric; c numeric;
begin
 if jsonb_typeof(p) is distinct from 'object' or
 exists(select 1 from jsonb_object_keys(p) k where k not in ('amount','unit','units_per_order','label','option'))
 or jsonb_typeof(p->'amount') is distinct from 'number'
 or jsonb_typeof(p->'units_per_order') is distinct from 'number'
 or coalesce(p->>'unit','') not in ('g','kg','ml','l','ea')
 or jsonb_typeof(p->'label') is distinct from 'string' or length(btrim(p->>'label')) not between 1 and 30
 or jsonb_typeof(p->'option') is distinct from 'string' or length(btrim(p->>'option')) not between 1 and 160 then return false; end if;
 n:=(p->>'amount')::numeric;c:=(p->>'units_per_order')::numeric;
 return n between 0.000001 and 1e6 and n=round(n,6) and c between 1 and 10000 and c=trunc(c) and n*c<=1e9;
exception when others then return false;
end;$$;
alter table public.shopping_affiliate_offers add column purchase_pack jsonb
 check(purchase_pack is null or (program='coupang' and public.affiliate_pack_valid(purchase_pack)));
create or replace function public.admin_save_shopping_affiliate(p_data jsonb,p_revision bigint default 0) returns uuid
language plpgsql security definer set search_path='' as $$
declare v public.shopping_affiliate_offers; v_id uuid; v_ingredients text[]; v_exists boolean;
 v_changed boolean; v_verified boolean; v_published boolean; v_expiry timestamptz; v_pack jsonb;
begin
 perform public.assert_supplier_directory_admin();
 if p_revision is null or p_revision<0 or jsonb_typeof(p_data) is distinct from 'object' or jsonb_typeof(p_data->'ingredients') is distinct from 'array' then raise exception 'AFFILIATE_INVALID'; end if;
 if not public.affiliate_link_valid(p_data->>'program',p_data->>'link') then raise exception 'AFFILIATE_INVALID'; end if;
 select array_agg(distinct lower(btrim(x))) into v_ingredients from jsonb_array_elements_text(p_data->'ingredients') x where length(btrim(x)) between 1 and 120;
 if exists(select 1 from jsonb_array_elements(p_data->'ingredients') x where jsonb_typeof(x)<>'string' or length(btrim(x#>>'{}')) not between 1 and 120) or v_ingredients is null or cardinality(v_ingredients)>20 then raise exception 'AFFILIATE_INVALID'; end if;
 v_id:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
 -- Serialize all RPC writes for a destination, including concurrent imports.
 perform pg_advisory_xact_lock(hashtextextended((p_data->>'program')||':'||(p_data->>'link'),0));
 select * into v from public.shopping_affiliate_offers where id=v_id for update;
 v_exists:=found;
 if (v_exists and v.revision<>p_revision) or (not v_exists and p_revision<>0) then raise exception 'AFFILIATE_STALE'; end if;
 if v.deleted_at is not null then raise exception 'AFFILIATE_DELETED'; end if;
 if exists(select 1 from public.shopping_affiliate_offers where program=p_data->>'program' and link=p_data->>'link' and id<>v_id) then raise exception 'AFFILIATE_DUPLICATE'; end if;
 v_expiry:=(p_data->>'expires_at')::timestamptz;
 v_published:=coalesce((p_data->>'published')::boolean,false);
 v_verified:=coalesce((p_data->>'product_verified')::boolean,v.product_verified,false);
 v_changed:=v_exists and (v.link is distinct from p_data->>'link' or v.program is distinct from p_data->>'program');
 if v_changed then v_published:=false; v_verified:=false; end if;
 v_pack:=case when p_data ? 'purchase_pack' then nullif(p_data->'purchase_pack','null'::jsonb) else v.purchase_pack end;
 -- Old editors may change the identity without understanding structured packs.
 if v_changed or (not (p_data ? 'purchase_pack') and v_exists and
 (v.title is distinct from btrim(p_data->>'title') or v.specification is distinct from p_data->>'specification'
 or v.brand is distinct from p_data->>'brand')) then v_pack:=null; end if;
 if p_data->>'program'<>'coupang' then v_pack:=null; end if;
 if v_pack is not null and not public.affiliate_pack_valid(v_pack) then raise exception 'AFFILIATE_PACK_INVALID'; end if;
 if v_expiry is null or v_expiry>now()+interval '90 days' or (v_published and v_expiry<=now()) then raise exception 'AFFILIATE_EXPIRY'; end if;
 if v_published and p_data->>'program'='coupang' and (not v_verified or length(btrim(coalesce(p_data->>'specification','')))=0) then raise exception 'AFFILIATE_REVIEW_REQUIRED'; end if;
 insert into public.shopping_affiliate_offers(id,program,title,specification,ingredients,link,review_note,mobile_allowed,web_allowed,published,expires_at,updated_by,category,brand,source_code,product_verified,reviewed_at,purchase_pack)
 values(v_id,p_data->>'program',btrim(p_data->>'title'),coalesce(p_data->>'specification',''),v_ingredients,p_data->>'link',case when v_changed then '' else coalesce(p_data->>'review_note','') end,
 not v_changed and coalesce((p_data->>'mobile_allowed')::boolean,false),not v_changed and coalesce((p_data->>'web_allowed')::boolean,false),v_published,v_expiry,auth.uid(),
 btrim(coalesce(p_data->>'category',v.category,'')),btrim(coalesce(p_data->>'brand',v.brand,'')),btrim(coalesce(p_data->>'source_code',v.source_code,'')),v_verified,case when v_changed then null when v_published then now() else v.reviewed_at end,v_pack)
 on conflict(id) do update set program=excluded.program,title=excluded.title,specification=excluded.specification,ingredients=excluded.ingredients,link=excluded.link,
 review_note=excluded.review_note,mobile_allowed=excluded.mobile_allowed,web_allowed=excluded.web_allowed,published=excluded.published,expires_at=excluded.expires_at,
 category=excluded.category,brand=excluded.brand,source_code=excluded.source_code,product_verified=excluded.product_verified,reviewed_at=excluded.reviewed_at,
 purchase_pack=excluded.purchase_pack,updated_by=auth.uid(),updated_at=now(),revision=shopping_affiliate_offers.revision+1;
 return v_id;
end; $$;
create function public.find_shopping_affiliates_v2(p_ingredient text,p_surface text)
returns table(id uuid,program text,title text,specification text,link text,revision bigint,purchase_pack jsonb)
language sql stable security definer set search_path='' as $$
 select o.id,o.program,o.title,o.specification,o.link,o.revision,
 case when o.product_verified then o.purchase_pack else null end
 from public.shopping_affiliate_offers o
 where auth.uid() is not null and coalesce(auth.jwt()->>'is_anonymous','false')='false'
 and o.deleted_at is null and o.published and o.expires_at>now()
 and o.ingredients @> array[lower(btrim(p_ingredient))]
 and ((p_surface='web' and o.web_allowed) or (p_surface='mobile' and o.mobile_allowed))
 order by o.title,o.id limit 6;
$$;
revoke all on function public.affiliate_pack_valid(jsonb) from public,anon,authenticated;
revoke all on function public.find_shopping_affiliates_v2(text,text) from public,anon;
grant execute on function public.find_shopping_affiliates_v2(text,text) to authenticated;
notify pgrst,'reload schema';
commit;
