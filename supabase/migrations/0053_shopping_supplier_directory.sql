-- Personal store management. Existing supplier ownership RLS and limits apply.
alter table public.shopping_suppliers
  add column website text not null default '',
  add column address text not null default '' check (char_length(address) <= 500),
  add column memo text not null default '' check (char_length(memo) <= 1000),
  add column is_favorite boolean not null default false;

alter table public.shopping_suppliers add constraint shopping_supplier_website_check
  check (website = '' or (
    char_length(website) <= 2048
    and website !~ '[[:space:][:cntrl:]\\]'
    and website ~ '^https://[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}(:443)?([/?#].*)?$'
    and substring(website from '^https://([^/?#]+)') !~ '\.\.'
    and lower(website) !~ '\.(local|localhost|internal)(:443)?([/?#]|$)'
  ));

grant update(website, address, memo, is_favorite) on public.shopping_suppliers to authenticated;
comment on column public.shopping_suppliers.memo is 'Private directory notes; excluded from client purchase request snapshots and shared documents.';
