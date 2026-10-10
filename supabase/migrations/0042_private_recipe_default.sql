-- New directly inserted notebooks are private unless explicitly published.
-- Historical published rows are deliberately not changed by this migration.
-- Deploy with the recipe_api and client private-save fixes.
alter table public.recipes_creator alter column is_published set default false;
