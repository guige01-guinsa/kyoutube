-- Registration certificates belong to the request author, never the public catalog.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('purchase-business-documents','purchase-business-documents',false,5242880,array['image/png'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/png'];

create function public.purchase_document_path(p_path text,p_owner uuid) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(p_owner is not null and p_path ~ ('^'||p_owner::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png$'),false);
$$;
create function public.purchase_document_upload_allowed(p_path text) returns boolean
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
 if not public.purchase_document_path(p_path,u) or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then return false; end if;
 perform pg_advisory_xact_lock(hashtextextended('purchase-documents:'||u::text,0));
 return (select count(*) from storage.objects where bucket_id='purchase-business-documents' and split_part(name,'/',1)=u::text)<200;
end; $$;
create function public.purchase_document_unused(p_path text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('purchase-documents:'||auth.uid()::text,0));
 return public.purchase_document_path(p_path,auth.uid()) and not exists(
  select 1 from public.supplier_purchase_requests r where r.owner_id=auth.uid() and
   (r.data#>>'{business_registrations,buyer,image_path}'=p_path or r.data#>>'{business_registrations,supplier,image_path}'=p_path));
end; $$;
revoke all on function public.purchase_document_path(text,uuid),public.purchase_document_upload_allowed(text),public.purchase_document_unused(text) from public,anon;
grant execute on function public.purchase_document_path(text,uuid),public.purchase_document_upload_allowed(text),public.purchase_document_unused(text) to authenticated;
create policy purchase_documents_read on storage.objects for select to authenticated
 using(bucket_id='purchase-business-documents' and public.purchase_document_path(name,auth.uid()) and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false));
create policy purchase_documents_insert on storage.objects for insert to authenticated
 with check(bucket_id='purchase-business-documents' and public.purchase_document_upload_allowed(name));
create policy purchase_documents_delete on storage.objects for delete to authenticated
 using(bucket_id='purchase-business-documents' and public.purchase_document_unused(name) and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false));
-- No update policy: an image referenced by a sent request cannot be overwritten.

create function public.validate_request_business_documents() returns trigger
language plpgsql security definer set search_path='' as $$
declare b jsonb; party jsonb; k text; path text; n text;
begin
 b:=new.data->'business_registrations';
 if b is null then return new; end if;
 perform pg_advisory_xact_lock(hashtextextended('purchase-documents:'||new.owner_id::text,0));
 if jsonb_typeof(b) is distinct from 'object' or (b - array['buyer','supplier']::text[])<>'{}'::jsonb then raise exception 'REQUEST_BUSINESS_INVALID'; end if;
 foreach k in array array['buyer','supplier'] loop
  party:=b->k;
  if jsonb_typeof(party) is distinct from 'object' or (party-array['number','image_path']::text[])<>'{}'::jsonb
   or jsonb_typeof(party->'number') is distinct from 'string' or jsonb_typeof(party->'image_path') is distinct from 'string' then raise exception 'REQUEST_BUSINESS_INVALID'; end if;
  n:=party->>'number';path:=party->>'image_path';
  if n<>'' and n !~ '^\d{3}-\d{2}-\d{5}$' then raise exception 'REQUEST_BUSINESS_INVALID'; end if;
  if path<>'' then
   if n='' or not public.purchase_document_path(path,new.owner_id) or not exists(
    select 1 from storage.objects o where o.bucket_id='purchase-business-documents' and o.name=path and
     o.metadata->>'mimetype'='image/png' and (o.metadata->>'size')::bigint between 1 and 5242880
   ) then raise exception 'REQUEST_BUSINESS_IMAGE_INVALID'; end if;
  end if;
 end loop;
 return new;
end; $$;
revoke all on function public.validate_request_business_documents() from public,anon,authenticated;
create trigger request_business_documents before insert or update of data on public.supplier_purchase_requests
 for each row execute function public.validate_request_business_documents();
notify pgrst,'reload schema';

-- A compact append-only ledger of changes, without duplicating document contents.
create table public.supplier_request_events (
 id bigint generated always as identity primary key,
 request_id uuid not null references public.supplier_purchase_requests(id) on delete cascade,
 owner_id uuid not null references auth.users(id) on delete cascade,
 event text not null check(event in ('created','edited','status','baseline')),
 from_status text,
 to_status text not null,
 revision bigint not null,
 recorded_at timestamptz not null default now()
);
create index supplier_request_events_owner on public.supplier_request_events(owner_id,request_id,id);
alter table public.supplier_request_events enable row level security;
revoke all on public.supplier_request_events from anon,authenticated;
grant select on public.supplier_request_events to authenticated;
create policy request_event_read on public.supplier_request_events for select to authenticated
 using(owner_id=auth.uid() and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false));
-- Baselines explicitly mark the migration date; past transitions are not invented.
insert into public.supplier_request_events(request_id,owner_id,event,to_status,revision)
 select id,owner_id,'baseline',status,revision from public.supplier_purchase_requests;
create function public.record_supplier_request_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
  insert into public.supplier_request_events(request_id,owner_id,event,to_status,revision)
   values(new.id,new.owner_id,'created',new.status,new.revision);
 elsif old.revision is distinct from new.revision then
  insert into public.supplier_request_events(request_id,owner_id,event,from_status,to_status,revision)
   values(new.id,new.owner_id,case when old.status<>new.status then 'status' else 'edited' end,old.status,new.status,new.revision);
 end if;
 return new;
end; $$;
revoke all on function public.record_supplier_request_event() from public,anon,authenticated;
create trigger supplier_request_event after insert or update on public.supplier_purchase_requests
 for each row execute function public.record_supplier_request_event();

create function public.search_purchase_request_ledger(
 p_from timestamptz default null, p_before timestamptz default null,
 p_status text default '', p_query text default '', p_offset integer default 0, p_limit integer default 50
) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'AUTH_REQUIRED'; end if;
 if p_status is null or p_status not in ('','draft','sent','accepted','received','cancelled')
  or p_query is null or length(p_query)>120 or p_offset is null or p_offset<0 or p_offset>100000
  or p_limit is null or p_limit<1 or p_limit>1000 or (p_from is not null and p_before is not null and p_from>=p_before)
 then raise exception 'LEDGER_FILTER_INVALID'; end if;
 with filtered as materialized (
  select r.id,r.created_at,r.status,r.revision,r.data->>'buyer' buyer,r.data#>>'{supplier,name}' supplier,
   coalesce(r.data#>>'{business_registrations,buyer,number}','') buyer_number,
   coalesce(r.data#>>'{business_registrations,supplier,number}','') supplier_number,
   r.data->>'delivery_date' delivery_date,r.data->>'currency' currency,
   jsonb_array_length(r.data->'lines') item_count,
   (select count(*) from jsonb_array_elements(r.data->'lines') l where l->>'price' is null) unpriced_count,
   (select coalesce(sum(round((l->>'quantity')::numeric*(l->>'price')::numeric,
      case when r.data->>'currency'='KRW' then 0 else 2 end)),0) from jsonb_array_elements(r.data->'lines') l) priced_total
  from public.supplier_purchase_requests r
  where r.owner_id=auth.uid() and (p_from is null or r.created_at>=p_from) and (p_before is null or r.created_at<p_before)
   and (p_status='' or r.status=p_status)
   and (p_query='' or strpos(lower(concat_ws(' ',r.id::text,'PO-'||r.id::text,r.data->>'buyer',r.data#>>'{supplier,name}',
    r.data#>>'{business_registrations,buyer,number}',r.data#>>'{business_registrations,supplier,number}')),lower(trim(p_query)))>0)
 ), totals as (
  select currency,count(*) request_count,coalesce(sum(priced_total) filter(where status<>'cancelled'),0) priced_total,
   coalesce(sum(unpriced_count) filter(where status<>'cancelled'),0) unpriced_count,
   count(*) filter(where status='cancelled') cancelled_count
  from filtered group by currency
 ) select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('priced_total',p.priced_total::text) order by p.created_at desc,p.id)
  from (select * from filtered order by created_at desc,id offset p_offset limit p_limit) p),'[]'::jsonb),
  'total_count',(select count(*) from filtered),'totals',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object('priced_total',t.priced_total::text) order by t.currency) from totals t),'[]'::jsonb)) into result;
 return result;
end; $$;
revoke all on function public.search_purchase_request_ledger(timestamptz,timestamptz,text,text,integer,integer) from public,anon;
grant execute on function public.search_purchase_request_ledger(timestamptz,timestamptz,text,text,integer,integer) to authenticated;
notify pgrst,'reload schema';
