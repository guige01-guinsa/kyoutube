insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'creator-recipe-images',
  'creator-recipe-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy "creator_recipe_images_read_public"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'creator-recipe-images');

create policy "creator_recipe_images_insert_own"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'creator-recipe-images'
  and split_part(name, '/', 1) = auth.uid()::text
);

create policy "creator_recipe_images_update_own"
on storage.objects for update
to authenticated
using (
  bucket_id = 'creator-recipe-images'
  and split_part(name, '/', 1) = auth.uid()::text
)
with check (
  bucket_id = 'creator-recipe-images'
  and split_part(name, '/', 1) = auth.uid()::text
);

create policy "creator_recipe_images_delete_own"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'creator-recipe-images'
  and split_part(name, '/', 1) = auth.uid()::text
);