create table if not exists public.ai_assistant_feedback (
  id bigint generated always as identity primary key,
  user_id uuid references public.profiles(id) on delete set null,
  liked boolean not null,
  summary text not null,
  note text,
  recipe_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_assistant_feedback_user_created
  on public.ai_assistant_feedback(user_id, created_at desc);

alter table public.ai_assistant_feedback enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_assistant_feedback'
      and policyname = 'ai_feedback_insert_own'
  ) then
    create policy "ai_feedback_insert_own"
      on public.ai_assistant_feedback
      for insert
      to authenticated
      with check (user_id = auth.uid());
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_assistant_feedback'
      and policyname = 'ai_feedback_select_own'
  ) then
    create policy "ai_feedback_select_own"
      on public.ai_assistant_feedback
      for select
      to authenticated
      using (user_id = auth.uid());
  end if;
end
$$;

grant select, insert on table public.ai_assistant_feedback to authenticated, service_role;