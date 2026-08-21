-- YouTube 검색 API quota 보호를 위한 사용자별 rate limit
-- 검색어 원문은 저장하지 않고, 사용자 ID / 시간 구간 / 요청 횟수만 저장한다.

create table if not exists public.youtube_search_rate_windows (
  user_id uuid not null references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0 and request_count <= 15),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, window_started_at)
);

alter table public.youtube_search_rate_windows enable row level security;

-- 클라이언트는 rate-limit 테이블을 직접 조회/수정할 수 없다.
revoke all on table public.youtube_search_rate_windows from anon;
revoke all on table public.youtube_search_rate_windows from authenticated;

-- 현재 로그인 사용자 기준으로 1분 최대 15회 검색을 허용한다.
create or replace function public.consume_youtube_search_rate_limit()
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid;
  current_window timestamptz;
begin
  current_user_id := auth.uid();

  if current_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- 1분 단위 fixed window
  current_window := date_trunc('minute', now());

  insert into public.youtube_search_rate_windows (
    user_id,
    window_started_at,
    request_count,
    updated_at
  )
  values (
    current_user_id,
    current_window,
    1,
    now()
  )
  on conflict (user_id, window_started_at)
  do update
    set request_count =
          public.youtube_search_rate_windows.request_count + 1,
        updated_at = now()
    where public.youtube_search_rate_windows.request_count < 15;

  -- INSERT 또는 UPDATE가 발생했으면 아직 quota가 남아 있다는 의미.
  if found then
    return true;
  end if;

  -- 이미 1분 15회를 모두 사용한 경우.
  return false;
end;
$$;

revoke all on function public.consume_youtube_search_rate_limit() from public;
grant execute on function public.consume_youtube_search_rate_limit() to authenticated;
