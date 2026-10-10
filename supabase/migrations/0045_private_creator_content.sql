-- Owner-approved privacy transition for personal recipe content.
update public.recipes_creator set is_published=false where is_published=true;
update storage.buckets set public=false where id='creator-recipe-images';
drop policy if exists "creator_recipe_images_read_public" on storage.objects;
create policy creator_recipe_images_read_own on storage.objects for select to authenticated
using (bucket_id='creator-recipe-images' and split_part(name,'/',1)=auth.uid()::text);
