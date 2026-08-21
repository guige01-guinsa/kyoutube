-- 정확한 3분 이하 요리 영상 검증을 위해 YouTube API 호출량이 증가한다.
-- 사용자별 YouTube 검색 rate limit을 1분 15회에서 6회로 낮춘다.

alter table public.youtube_search_rate_windows
  drop constraint if exists youtube_search_rate_windows_request_count_check;

alter table public.youtube_search_rate_windows
  add constraint youtube_search_rate_windows_request_count_check
    check (request_count >= 0 and request_count <= 6);

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
    where public.youtube_search_rate_windows.request_count < 6;

  if found then
    return true;
  end if;

  return false;
end;
$$;