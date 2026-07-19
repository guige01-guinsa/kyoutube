# Kitchen Priority Implementation Spec

Last update: 2026-07-19

## 1. Scope

This spec defines the first implementation slice for high-impact features inspired by previous "AI cooking lab" design docs, adapted to this codebase.

Included in this slice:
1. Fridge inventory management
2. Missing-ingredient shopping list generation from recipe detail
3. Home summary metrics with a single backend source of truth
4. Cook completion + lightweight feedback loop (like/dislike/rating)

Out of scope for this slice:
1. Medical diagnosis logic
2. OCR/barcode automation
3. Direct commerce checkout
4. Full i18n translation pipeline

## 2. Why this slice first

Current app already has:
1. Public/creator/user recipe entities
2. Bookmark flow
3. Supabase auth/RLS foundation

Biggest gap is "decision-to-action" flow:
1. "What can I cook now?"
2. "What do I need to buy?"
3. "What changed after I cooked?"

This slice closes that gap with minimal schema and UI risk.

## 3. Data model changes (Supabase)

Create migration: `supabase/migrations/0007_kitchen_foundation.sql`

### 3.1 New tables

#### `kitchen_ingredients`
- `id uuid primary key default gen_random_uuid()`
- `owner_id uuid not null references public.profiles(id) on delete cascade`
- `name text not null`
- `normalized_name text not null`
- `quantity numeric(12,2)`
- `unit text`
- `storage_location text`
- `expires_on date`
- `note text`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Indexes:
- `(owner_id)`
- `(owner_id, normalized_name)`
- `(owner_id, expires_on)`

#### `kitchen_shopping_lists`
- `id uuid primary key default gen_random_uuid()`
- `owner_id uuid not null references public.profiles(id) on delete cascade`
- `status text not null default 'active' check (status in ('active','completed','archived'))`
- `title text not null default 'AI generated shopping list'`
- `source_recipe_id text`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Indexes:
- `(owner_id, status)`
- `(owner_id, created_at desc)`

#### `kitchen_shopping_items`
- `id uuid primary key default gen_random_uuid()`
- `list_id uuid not null references public.kitchen_shopping_lists(id) on delete cascade`
- `owner_id uuid not null references public.profiles(id) on delete cascade`
- `name text not null`
- `normalized_name text not null`
- `quantity numeric(12,2)`
- `unit text`
- `is_checked boolean not null default false`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Indexes:
- `(owner_id, list_id)`
- `(owner_id, is_checked)`
- `(owner_id, normalized_name)`

#### `kitchen_cook_sessions`
- `id uuid primary key default gen_random_uuid()`
- `owner_id uuid not null references public.profiles(id) on delete cascade`
- `recipe_type text not null check (recipe_type in ('public','creator','user'))`
- `recipe_ref_id text not null`
- `recipe_title text not null`
- `consumed_ingredients jsonb not null default '[]'::jsonb`
- `missing_ingredients jsonb not null default '[]'::jsonb`
- `rating integer check (rating between 1 and 5)`
- `liked boolean`
- `note text`
- `created_at timestamptz not null default now()`

Indexes:
- `(owner_id, created_at desc)`
- `(owner_id, recipe_ref_id)`

### 3.2 RLS policies

Create RLS rules equivalent to existing owner-scoped tables:
1. Users can `select/insert/update/delete` only rows where `owner_id = auth.uid()`
2. No anonymous cross-user reads
3. Service role keeps full access

## 4. API contract (Edge function extension)

Extend `supabase/functions/recipe_api/index.ts` with `type=kitchen` routes.

### 4.1 Kitchen home summary

`GET /functions/v1/recipe_api?type=kitchen&view=summary`

Response:
- `ingredient_count`
- `expiring_soon_count` (expires within 3 days)
- `active_shopping_list_count`
- `open_shopping_item_count`
- `recent_cook_count_7d`

Rule: all values must be computed server-side in one helper, not recomputed in Flutter.

### 4.2 Ingredients CRUD

1. `GET ?type=kitchen&view=ingredients&limit=&offset=&q=`
2. `POST ?type=kitchen&view=ingredients`
3. `PATCH ?type=kitchen&view=ingredients&id=<ingredient_id>`
4. `DELETE ?type=kitchen&view=ingredients&id=<ingredient_id>`

Normalization:
- `normalized_name = lower(trim(name))`

### 4.3 Shopping list from recipe

`POST ?type=kitchen&action=create-shopping-from-recipe`

Request:
- `recipe_type`: `public|creator|user`
- `recipe_id`: string
- `recipe_title`: string
- `required_ingredients`: string[]

Server behavior:
1. Load user `kitchen_ingredients`
2. Compare by `normalized_name`
3. Create active list (or append into latest active list if requested later)
4. Insert only missing items
5. Return created list + items

### 4.4 Shopping item toggle and complete

1. `PATCH ?type=kitchen&view=shopping-item&id=<item_id>` with `is_checked`
2. `POST ?type=kitchen&action=complete-shopping-list&id=<list_id>`

Complete action behavior:
1. Mark list `completed`
2. For checked items, upsert into `kitchen_ingredients`
3. Return updated summary snapshot

### 4.5 Cook complete + feedback

`POST ?type=kitchen&action=complete-cook`

Request:
- `recipe_type`
- `recipe_id`
- `recipe_title`
- `consumed_ingredients` (optional)
- `rating` (optional)
- `liked` (optional)
- `note` (optional)

Behavior:
1. Save cook session
2. Deduct matched ingredients if quantities provided
3. Keep unmatched in session log only
4. Return updated summary

## 5. Flutter app integration

### 5.1 New feature module

Add:
1. `lib/features/kitchen/domain/`
2. `lib/features/kitchen/data/`
3. `lib/features/kitchen/application/`
4. `lib/features/kitchen/presentation/`

### 5.2 Home page changes

File: `lib/features/home/presentation/home_page.dart`

Add a compact "Kitchen summary" card above recipe list:
1. ingredients
2. expiring soon
3. active shopping lists
4. unchecked shopping items

Actions:
1. "재료 관리"
2. "장보기"

### 5.3 Recipe detail action changes

File: `lib/features/recipes/presentation/recipe_detail_page.dart`

Add CTA:
1. "부족 재료 장보기 추가"

When tapped:
1. Build required ingredient names from recipe
2. Call `create-shopping-from-recipe`
3. Show result snackbar with added item count

### 5.4 New screens

1. `kitchen_ingredients_page.dart`
- quick add row
- expiring section
- grouped list

2. `kitchen_shopping_page.dart`
- active list + checklist
- complete button

3. `kitchen_history_page.dart` (optional in this slice, can be hidden route)
- recent cook sessions
- simple feedback chips

## 6. Ranking/learning hooks (minimal)

For this slice, do not overfit model logic.

Add simple scoring signal in recommendation call path later:
1. `liked=true` recent sessions boost recipe-type/title match
2. `disliked` recent sessions apply small penalty
3. `recently_cooked` apply cooldown penalty

Store now, use in ranking phase next.

## 7. Validation and tests

### 7.1 SQL/RLS tests

Add smoke SQL checks for:
1. owner can CRUD own ingredient
2. owner cannot read another owner rows
3. shopping completion inserts checked items into ingredients

### 7.2 Edge function tests (manual script first)

Create `tools/kitchen_smoke.ps1`:
1. create ingredient
2. create shopping from recipe
3. toggle item
4. complete shopping list
5. complete cook with rating
6. fetch summary and assert counts

### 7.3 Flutter tests

Add widget/provider tests for:
1. kitchen summary card renders values
2. recipe detail CTA sends request payload
3. shopping list toggle updates UI state

## 8. Rollout plan

### Phase A (2-3 days)
1. Migration + RLS + edge routes
2. Basic smoke script green

### Phase B (2-3 days)
1. Home summary card
2. Ingredients/shopping pages
3. Recipe detail CTA

### Phase C (1-2 days)
1. Cook complete + feedback
2. test hardening + docs update

## 9. Definition of done

1. User can add fridge ingredients and see counts in home summary
2. User can create missing-ingredient shopping list from a recipe
3. User can complete shopping and auto-merge checked items into fridge
4. User can mark cook complete with rating/liked and see it in session history
5. `flutter analyze` and core widget tests pass
6. RLS prevents cross-user data access

## 10. Open decisions

1. Should shopping items aggregate into one active list by default, or create per-recipe lists?
2. Quantity matching rule: strict unit compare vs heuristic merge?
3. Initial feedback UI: star-only vs like/dislike + stars?

Recommended defaults:
1. Create per-recipe list first (lower risk)
2. Quantity optional in v1 (presence-based missing check)
3. Like/dislike first, star optional
