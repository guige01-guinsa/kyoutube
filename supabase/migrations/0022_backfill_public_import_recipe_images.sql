-- 공개 레시피를 내 레시피로 저장한 기존 데이터의 표시 정보를 복구한다.
--
-- 과거 앱 버전은 recipes_user에 제목/재료/조리순서만 저장하고
-- summary, image_url, source_type을 저장하지 않았다.
--
-- title이 동일한 recipes_public 레코드를 찾는 경우에만
-- 이미지/요약/출처를 보정한다.
--
-- 원본 공개 레시피에 image_url이 없으면 기본 썸네일이 유지될 수 있다.

update public.recipes_user as user_recipe
set
  summary = coalesce(
    nullif(btrim(user_recipe.summary), ''),
    public_recipe.summary
  ),
  image_url = coalesce(
    nullif(btrim(user_recipe.image_url), ''),
    public_recipe.image_url
  ),
  source_type = case
    when user_recipe.source_type = 'manual' then 'public_import'
    else user_recipe.source_type
  end,
  updated_at = now()
from public.recipes_public as public_recipe
where lower(btrim(user_recipe.title)) = lower(btrim(public_recipe.title))
  and (
    nullif(btrim(user_recipe.summary), '') is null
    or nullif(btrim(user_recipe.image_url), '') is null
    or user_recipe.source_type = 'manual'
  );