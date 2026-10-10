-- Copying a recipe into a personal notebook is not publication.
create or replace function public.promote_subscriber_recipe_to_creator(
  p_recipe_user_id uuid,
  p_delete_source boolean default false,
  p_include_summary boolean default true,
  p_include_youtube_url boolean default true,
  p_include_image_url boolean default true,
  p_include_notes_as_tips boolean default true
)
returns public.recipes_creator
language plpgsql
security definer
set search_path = public
as $$
declare
  _uid uuid;
  _source public.recipes_user%rowtype;
  _creator public.recipes_creator%rowtype;
begin
  _uid := auth.uid();
  if _uid is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into _source
  from public.recipes_user
  where id = p_recipe_user_id
    and owner_id = _uid;

  if not found then
    raise exception 'Subscriber recipe not found';
  end if;

  if _source.promoted_creator_recipe_id is not null then
    select *
      into _creator
    from public.recipes_creator
    where id = _source.promoted_creator_recipe_id
      and author_id = _uid;

    if found then
      return _creator;
    end if;
  end if;

  insert into public.recipes_creator (
    author_id,
    title,
    summary,
    ingredients,
    steps,
    tips,
    youtube_url,
    image_path,
    is_published,
    source_user_recipe_id
  )
  values (
    _uid,
    _source.title,
    case
      when p_include_summary then nullif(trim(_source.summary), '')
      else null
    end,
    _source.ingredients,
    _source.steps,
    case
      when p_include_notes_as_tips then nullif(trim(_source.notes), '')
      else null
    end,
    case
      when p_include_youtube_url then nullif(trim(_source.youtube_url), '')
      else null
    end,
    case
      when p_include_image_url then nullif(trim(_source.image_url), '')
      else null
    end,
    false,
    _source.id
  )
  returning * into _creator;

  update public.recipes_user
  set promoted_creator_recipe_id = _creator.id,
      updated_at = now()
  where id = _source.id;

  if p_delete_source then
    delete from public.recipes_user where id = _source.id;
  end if;

  return _creator;
end;
$$;

revoke all on function public.promote_subscriber_recipe_to_creator(uuid, boolean, boolean, boolean, boolean, boolean) from public;
grant execute on function public.promote_subscriber_recipe_to_creator(uuid, boolean, boolean, boolean, boolean, boolean) to authenticated;
