-- Curated outbound referrals only. No checkout, attribution or income claims.
create function public.affiliate_link_valid(p_program text, p_url text) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(length(p_url) between 15 and 2048
  and p_url !~ '[[:space:][:cntrl:]\\]'
  and case p_program
   when 'naver' then p_url ~ '^https://(naver\.me|brandconnect\.naver\.com)/[^?#]+([?#].*)?$'
   when 'youtube' then p_url ~ '^https://(www\.youtube\.com/watch\?v=[A-Za-z0-9_-]{11}(&[^#]*)?|youtu\.be/[A-Za-z0-9_-]{11}(\?[^#]*)?|www\.youtube\.com/shorts/[A-Za-z0-9_-]{11}(\?[^#]*)?)$'
   else false end,false);
$$;
create table public.shopping_affiliate_offers (
 id uuid primary key default gen_random_uuid(),
 program text not null check(program in ('naver','youtube')),
 title text not null check(length(btrim(title)) between 1 and 120),
 specification text not null default '' check(length(specification)<=160),
 ingredients text[] not null check(cardinality(ingredients) between 1 and 20),
 link text not null check(public.affiliate_link_valid(program,link)),
 review_note text not null default '' check(length(review_note)<=2000),
 mobile_allowed boolean not null default false,
 web_allowed boolean not null default false,
 published boolean not null default false,
 expires_at timestamptz not null,
 revision bigint not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null,
 check(not published or (length(btrim(review_note))>=10 and (mobile_allowed or web_allowed)))
);
alter table public.shopping_affiliate_offers enable row level security;
revoke all on public.shopping_affiliate_offers from public,anon,authenticated;
create index shopping_affiliate_ingredients on public.shopping_affiliate_offers using gin(ingredients) where published;

create function public.admin_shopping_affiliates() returns setof public.shopping_affiliate_offers
language plpgsql security definer set search_path='' as $$
begin
 perform public.assert_supplier_directory_admin();
 return query select * from public.shopping_affiliate_offers order by updated_at desc limit 500;
end; $$;

create function public.admin_save_shopping_affiliate(p_data jsonb,p_revision bigint default 0) returns uuid
language plpgsql security definer set search_path='' as $$
declare v public.shopping_affiliate_offers; v_id uuid; v_ingredients text[];
begin
 perform public.assert_supplier_directory_admin();
 if p_revision is null or p_revision<0 then raise exception 'AFFILIATE_STALE'; end if;
 select array_agg(distinct lower(btrim(x))) into v_ingredients
 from jsonb_array_elements_text(p_data->'ingredients') x where length(btrim(x)) between 1 and 120;
 if v_ingredients is null or cardinality(v_ingredients)>20 then raise exception 'AFFILIATE_INVALID'; end if;
 v_id:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
 select * into v from public.shopping_affiliate_offers where id=v_id for update;
 if (found and v.revision<>p_revision) or (not found and p_revision<>0) then raise exception 'AFFILIATE_STALE'; end if;
 if (p_data->>'expires_at')::timestamptz is null or (p_data->>'expires_at')::timestamptz>now()+interval '90 days'
  or (coalesce((p_data->>'published')::boolean,false) and (p_data->>'expires_at')::timestamptz<=now()) then raise exception 'AFFILIATE_EXPIRY'; end if;
 insert into public.shopping_affiliate_offers(id,program,title,specification,ingredients,link,review_note,mobile_allowed,web_allowed,published,expires_at,updated_by)
 values(v_id,p_data->>'program',btrim(p_data->>'title'),coalesce(p_data->>'specification',''),v_ingredients,p_data->>'link',coalesce(p_data->>'review_note',''),
 coalesce((p_data->>'mobile_allowed')::boolean,false),coalesce((p_data->>'web_allowed')::boolean,false),coalesce((p_data->>'published')::boolean,false),(p_data->>'expires_at')::timestamptz,auth.uid())
 on conflict(id) do update set program=excluded.program,title=excluded.title,specification=excluded.specification,ingredients=excluded.ingredients,
 link=excluded.link,review_note=excluded.review_note,mobile_allowed=excluded.mobile_allowed,web_allowed=excluded.web_allowed,published=excluded.published,
 expires_at=excluded.expires_at,updated_by=auth.uid(),updated_at=now(),revision=shopping_affiliate_offers.revision+1;
 return v_id;
end; $$;

create function public.find_shopping_affiliates(p_ingredient text,p_surface text)
returns table(id uuid,program text,title text,specification text,link text)
language sql stable security definer set search_path='' as $$
 select o.id,o.program,o.title,o.specification,o.link from public.shopping_affiliate_offers o
 where auth.uid() is not null and coalesce(auth.jwt()->>'is_anonymous','false')='false'
 and o.published and o.expires_at>now() and o.ingredients @> array[lower(btrim(p_ingredient))]
 and ((p_surface='web' and o.web_allowed) or (p_surface='mobile' and o.mobile_allowed))
 order by o.title,o.id limit 6;
$$;
revoke all on function public.affiliate_link_valid(text,text),public.admin_shopping_affiliates(),public.admin_save_shopping_affiliate(jsonb,bigint),public.find_shopping_affiliates(text,text) from public,anon,authenticated;
grant execute on function public.admin_shopping_affiliates(),public.admin_save_shopping_affiliate(jsonb,bigint),public.find_shopping_affiliates(text,text) to authenticated;
