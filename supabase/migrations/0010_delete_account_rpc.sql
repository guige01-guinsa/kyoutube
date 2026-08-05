-- 현재 로그인한 사용자의 계정을 삭제하는 RPC 함수
-- profiles 행은 auth.users cascade delete로 자동 삭제됩니다.
-- 단, creator recipes / subscriber recipes 등은 cascade 처리되어 있으므로 별도 처리 불필요.

create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _uid uuid;
begin
  _uid := auth.uid();
  if _uid is null then
    raise exception 'Not authenticated';
  end if;

  -- auth.users 삭제 -> profiles 및 관련 cascade rows 자동 삭제
  delete from auth.users where id = _uid;
end;
$$;

-- 인증된 사용자만 자신의 계정을 삭제할 수 있습니다.
revoke all on function public.delete_account() from anon;
grant execute on function public.delete_account() to authenticated;
