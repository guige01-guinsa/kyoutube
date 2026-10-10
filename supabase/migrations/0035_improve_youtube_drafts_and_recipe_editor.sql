-- Recipe editor presentation preferences and privacy-safe YouTube draft metrics.

alter table public.recipes_creator
  add column if not exists content_styles jsonb not null default '{}'::jsonb;

alter table public.recipes_creator
  add constraint recipes_creator_content_styles_object
  check (
    jsonb_typeof(content_styles) = 'object'
    and octet_length(content_styles::text) <= 4096
  );

create table public.youtube_recipe_draft_metrics (
  id bigint generated always as identity primary key,
  reservation_id uuid unique references public.ai_usage_reservations(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  succeeded boolean not null,
  ingredient_count integer not null check (ingredient_count >= 0),
  step_count integer not null check (step_count >= 0),
  had_description boolean not null,
  had_transcript boolean not null,
  repair_attempted boolean not null default false,
  promotional_lines_removed integer not null default 0 check (promotional_lines_removed >= 0),
  created_at timestamptz not null default now()
);

create index youtube_recipe_draft_metrics_created_at_idx
  on public.youtube_recipe_draft_metrics(created_at desc);

alter table public.youtube_recipe_draft_metrics enable row level security;
grant all on table public.youtube_recipe_draft_metrics to service_role;
grant usage, select on sequence public.youtube_recipe_draft_metrics_id_seq to service_role;

create or replace function public.admin_get_youtube_draft_success_stats(
  p_days integer default 30
)
returns table (
  attempts bigint,
  successes bigint,
  success_rate numeric,
  transcript_attempts bigint,
  repaired_attempts bigint
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  ) then
    raise exception 'ADMIN_REQUIRED';
  end if;
  if p_days < 1 or p_days > 365 then
    raise exception 'INVALID_DAY_RANGE';
  end if;

  return query
  select
    count(*)::bigint,
    count(*) filter (where m.succeeded)::bigint,
    round(
      100.0 * count(*) filter (where m.succeeded) / nullif(count(*), 0),
      1
    ),
    count(*) filter (where m.had_transcript)::bigint,
    count(*) filter (where m.repair_attempted)::bigint
  from public.youtube_recipe_draft_metrics m
  where m.created_at >= now() - make_interval(days => p_days);
end;
$$;

revoke all on function public.admin_get_youtube_draft_success_stats(integer)
  from public, anon;
grant execute on function public.admin_get_youtube_draft_success_stats(integer)
  to authenticated, service_role;
