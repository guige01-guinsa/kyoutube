-- Curated catalog: scoped admin writes, drafts, recoverable deletion and audit.
alter table public.shopping_affiliate_offers
 drop constraint shopping_affiliate_offers_program_check,
 add constraint shopping_affiliate_offers_program_check check(program in ('naver','youtube','coupang')),
 add column category text not null default '' check(length(category)<=80),
 add column brand text not null default '' check(length(brand)<=80),
 add column source_code text not null default '' check(length(source_code)<=80),
 add column product_verified boolean not null default false,
 add column reviewed_at timestamptz,
 add column deleted_at timestamptz;

create or replace function public.affiliate_link_valid(p_program text,p_url text) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(length(p_url) between 15 and 2048 and p_url !~ '[[:space:][:cntrl:]\\]'
 and case p_program
 when 'coupang' then p_url ~ '^https://link\.coupang\.com/a/[A-Za-z0-9]+$'
 when 'naver' then p_url ~ '^https://(naver\.me|brandconnect\.naver\.com)/[^?#]+([?#].*)?$'
 when 'youtube' then p_url ~ '^https://(www\.youtube\.com/watch\?v=[A-Za-z0-9_-]{11}(&[^#]*)?|youtu\.be/[A-Za-z0-9_-]{11}(\?[^#]*)?|www\.youtube\.com/shorts/[A-Za-z0-9_-]{11}(\?[^#]*)?)$'
 else false end,false);
$$;

create index shopping_affiliate_catalog_page on public.shopping_affiliate_offers(updated_at desc,id) where deleted_at is null;
create index shopping_affiliate_catalog_link on public.shopping_affiliate_offers(program,link);
create table public.shopping_affiliate_history (
 id bigint generated always as identity primary key,
 offer_id uuid not null references public.shopping_affiliate_offers(id),
 actor_id uuid references auth.users(id) on delete set null,
 action text not null,
 before_data jsonb,
 after_data jsonb not null,
 created_at timestamptz not null default now()
);
create index shopping_affiliate_history_offer on public.shopping_affiliate_history(offer_id,id desc);
alter table public.shopping_affiliate_history enable row level security;
revoke all on public.shopping_affiliate_history from public,anon,authenticated;

create function public.affiliate_catalog_audit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.shopping_affiliate_history(offer_id,actor_id,action,before_data,after_data)
 values(new.id,(select id from auth.users where id=auth.uid()),case when tg_op='INSERT' then 'create'
 when old.deleted_at is null and new.deleted_at is not null then 'delete'
 when old.deleted_at is not null and new.deleted_at is null then 'restore'
 when not old.published and new.published then 'publish'
 when old.published and not new.published then 'hide' else 'update' end,
 case when tg_op='UPDATE' then to_jsonb(old) else null end,to_jsonb(new));
 return new;
end; $$;
create trigger shopping_affiliate_audit after insert or update on public.shopping_affiliate_offers
 for each row execute function public.affiliate_catalog_audit();
revoke all on function public.affiliate_catalog_audit() from public,anon,authenticated;

create function public.admin_shopping_affiliate_page(p_query text default '',p_status text default 'active',p_offset integer default 0,p_limit integer default 25)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_rows jsonb; v_total bigint;
begin
 perform public.assert_supplier_directory_admin();
 if p_query is null or p_status is null or p_offset is null or p_limit is null or p_status not in ('active','draft','published','expired','trash') or p_offset<0 or p_limit not between 1 and 100 or length(p_query)>160 then raise exception 'AFFILIATE_INVALID'; end if;
 with matches as (
 select o.* from public.shopping_affiliate_offers o where
 (case p_status when 'trash' then o.deleted_at is not null
 when 'draft' then o.deleted_at is null and not o.published
 when 'published' then o.deleted_at is null and o.published and o.expires_at>now()
 when 'expired' then o.deleted_at is null and o.published and o.expires_at<=now()
 else o.deleted_at is null end)
 and (p_query='' or position(lower(p_query) in lower(concat_ws(' ',o.title,o.category,o.brand,o.specification,o.source_code,array_to_string(o.ingredients,' '))))>0)
 ), page as (select * from matches order by updated_at desc,id limit p_limit offset p_offset)
 select (select count(*) from matches),coalesce((select jsonb_agg(to_jsonb(page) order by updated_at desc,id) from page),'[]'::jsonb) into v_total,v_rows;
 return jsonb_build_object('rows',v_rows,'total',v_total);
end; $$;

create or replace function public.admin_shopping_affiliates() returns setof public.shopping_affiliate_offers
language plpgsql security definer set search_path='' as $$
begin
 perform public.assert_supplier_directory_admin();
 -- Old app versions only understand Naver and YouTube in their editor.
 return query select * from public.shopping_affiliate_offers where deleted_at is null and program in ('naver','youtube') order by updated_at desc,id limit 500;
end; $$;

create or replace function public.admin_save_shopping_affiliate(p_data jsonb,p_revision bigint default 0) returns uuid
language plpgsql security definer set search_path='' as $$
declare v public.shopping_affiliate_offers; v_id uuid; v_ingredients text[]; v_exists boolean;
 v_changed boolean; v_verified boolean; v_published boolean; v_expiry timestamptz;
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
 if v_expiry is null or v_expiry>now()+interval '90 days' or (v_published and v_expiry<=now()) then raise exception 'AFFILIATE_EXPIRY'; end if;
 if v_published and p_data->>'program'='coupang' and (not v_verified or length(btrim(coalesce(p_data->>'specification','')))=0) then raise exception 'AFFILIATE_REVIEW_REQUIRED'; end if;
 insert into public.shopping_affiliate_offers(id,program,title,specification,ingredients,link,review_note,mobile_allowed,web_allowed,published,expires_at,updated_by,category,brand,source_code,product_verified,reviewed_at)
 values(v_id,p_data->>'program',btrim(p_data->>'title'),coalesce(p_data->>'specification',''),v_ingredients,p_data->>'link',case when v_changed then '' else coalesce(p_data->>'review_note','') end,
 not v_changed and coalesce((p_data->>'mobile_allowed')::boolean,false),not v_changed and coalesce((p_data->>'web_allowed')::boolean,false),v_published,v_expiry,auth.uid(),
 btrim(coalesce(p_data->>'category',v.category,'')),btrim(coalesce(p_data->>'brand',v.brand,'')),btrim(coalesce(p_data->>'source_code',v.source_code,'')),v_verified,case when v_changed then null when v_published then now() else v.reviewed_at end)
 on conflict(id) do update set program=excluded.program,title=excluded.title,specification=excluded.specification,ingredients=excluded.ingredients,link=excluded.link,
 review_note=excluded.review_note,mobile_allowed=excluded.mobile_allowed,web_allowed=excluded.web_allowed,published=excluded.published,expires_at=excluded.expires_at,
 category=excluded.category,brand=excluded.brand,source_code=excluded.source_code,product_verified=excluded.product_verified,reviewed_at=excluded.reviewed_at,
 updated_by=auth.uid(),updated_at=now(),revision=shopping_affiliate_offers.revision+1;
 return v_id;
end; $$;

create function public.admin_change_shopping_affiliate(p_id uuid,p_revision bigint,p_action text) returns void
language plpgsql security definer set search_path='' as $$
declare v public.shopping_affiliate_offers;
begin
 perform public.assert_supplier_directory_admin();
 select * into v from public.shopping_affiliate_offers where id=p_id for update;
 if not found or p_revision is null or v.revision<>p_revision then raise exception 'AFFILIATE_STALE'; end if;
 if p_action is null or p_action not in ('delete','restore','hide','publish') then raise exception 'AFFILIATE_INVALID'; end if;
 if p_action<>'restore' and v.deleted_at is not null then raise exception 'AFFILIATE_DELETED'; end if;
 if p_action='restore' and v.deleted_at is null then raise exception 'AFFILIATE_INVALID'; end if;
 if p_action='publish' and (v.expires_at<=now() or length(btrim(v.review_note))<10 or not(v.mobile_allowed or v.web_allowed)
 or (v.program='coupang' and (not v.product_verified or length(btrim(v.specification))=0))) then raise exception 'AFFILIATE_REVIEW_REQUIRED'; end if;
 update public.shopping_affiliate_offers set deleted_at=case when p_action='delete' then now() when p_action='restore' then null else deleted_at end,
 published=(p_action='publish'),reviewed_at=case when p_action='publish' then now() else reviewed_at end,
 updated_by=auth.uid(),updated_at=now(),revision=revision+1 where id=p_id;
end; $$;

create function public.admin_shopping_affiliate_history(p_id uuid,p_before bigint default null) returns setof public.shopping_affiliate_history
language plpgsql security definer set search_path='' as $$
begin
 perform public.assert_supplier_directory_admin();
 return query select * from public.shopping_affiliate_history where offer_id=p_id and (p_before is null or id<p_before) order by id desc limit 25;
end; $$;

create function public.admin_preview_shopping_affiliates(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb:='[]'; d jsonb; v public.shopping_affiliate_offers;
begin
 perform public.assert_supplier_directory_admin();
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>100 then raise exception 'AFFILIATE_INVALID'; end if;
 for d in select value from jsonb_array_elements(p_rows) loop
 select * into v from public.shopping_affiliate_offers where program=d->>'program' and link=d->>'link' order by updated_at desc,id limit 1;
 result:=result||jsonb_build_array(case when found then jsonb_build_object('id',v.id,'revision',v.revision,'title',v.title,'deleted',v.deleted_at is not null) else '{}'::jsonb end);
 end loop;
 return result;
end; $$;

create function public.admin_import_shopping_affiliates(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb:='[]'; entry jsonb; d jsonb; v_id uuid; v_revision bigint; msg text;
begin
 perform public.assert_supplier_directory_admin();
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>100 then raise exception 'AFFILIATE_INVALID'; end if;
 for entry in select value from jsonb_array_elements(p_rows) loop
 begin
 d:=entry->'data';
 if entry->>'action'='update' then
 if nullif(d->>'id','') is null or (d->>'revision')::bigint is null then raise exception 'AFFILIATE_INVALID'; end if;
 v_revision:=(d->>'revision')::bigint;
 if v_revision<1 then raise exception 'AFFILIATE_INVALID'; end if;
 elsif entry->>'action'='create' then
 d:=d-'id'-'revision'; v_revision:=0;
 else raise exception 'AFFILIATE_INVALID'; end if;
 -- Imported rows never imply product or placement approval.
 d:=d||jsonb_build_object('published',false,'mobile_allowed',false,'web_allowed',false,'product_verified',false,'review_note','','expires_at',now()+interval '30 days');
 v_id:=public.admin_save_shopping_affiliate(d,v_revision);
 result:=result||jsonb_build_array(jsonb_build_object('status','saved','id',v_id));
 exception when others then
 get stacked diagnostics msg=message_text;
 result:=result||jsonb_build_array(jsonb_build_object('status',case when msg='AFFILIATE_DUPLICATE' then 'duplicate' when msg='AFFILIATE_STALE' then 'stale' when msg='AFFILIATE_DELETED' then 'deleted' else 'invalid' end));
 end;
 end loop;
 return result;
end; $$;

create or replace function public.find_shopping_affiliates(p_ingredient text,p_surface text)
returns table(id uuid,program text,title text,specification text,link text)
language sql stable security definer set search_path='' as $$
 select o.id,o.program,o.title,o.specification,o.link from public.shopping_affiliate_offers o
 where auth.uid() is not null and coalesce(auth.jwt()->>'is_anonymous','false')='false'
 and o.deleted_at is null and o.published and o.expires_at>now() and o.ingredients @> array[lower(btrim(p_ingredient))]
 and ((p_surface='web' and o.web_allowed) or (p_surface='mobile' and o.mobile_allowed))
 order by o.title,o.id limit 6;
$$;

revoke all on function public.admin_shopping_affiliate_page(text,text,integer,integer),public.admin_change_shopping_affiliate(uuid,bigint,text),public.admin_shopping_affiliate_history(uuid,bigint),public.admin_preview_shopping_affiliates(jsonb),public.admin_import_shopping_affiliates(jsonb) from public,anon,authenticated;
grant execute on function public.admin_shopping_affiliate_page(text,text,integer,integer),public.admin_change_shopping_affiliate(uuid,bigint,text),public.admin_shopping_affiliate_history(uuid,bigint),public.admin_preview_shopping_affiliates(jsonb),public.admin_import_shopping_affiliates(jsonb) to authenticated;
