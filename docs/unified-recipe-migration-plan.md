# Unified Recipe Migration Plan

## Strategy

Unify the user experience first.

Do not physically merge all recipe tables immediately. This reduces risk and preserves existing data, routes, and APIs.

## Phase 0 — Design and contract freeze

Deliverables:

- Document current source types
- Document existing routes
- Document current repository contracts
- Define unified recipe concepts

No runtime behavior changes.

## Phase 1 — Unified domain contracts

Add domain models:

- RecipeIdentity
- RecipeOrigin
- RecipeAccess
- RecipeProvenance
- UnifiedRecipe

Add mappers:

- Public recipe to unified recipe
- Creator recipe to unified recipe
- User recipe to unified recipe

Tests:

- Identity parsing
- Reference formatting
- Access calculation
- Mapper field preservation

## Phase 2 — Unified repository facade

Add UnifiedRecipeRepository.

Responsibilities:

- Resolve source type
- Delegate to existing repositories
- Return unified recipe models
- Hide public/creator/user branching from UI

No DB migration required.

## Phase 3 — Unified detail page

Add UnifiedRecipeDetailPage.

Use shared components:

- Header
- Image
- Ingredients
- Steps
- Primary actions
- Ownership actions

Wire existing routes to unified detail page while keeping URLs stable.

## Phase 4 — Unified My Recipes library

My Recipes becomes a personal library, not a physical source category.

Sources:

- Saved public recipes
- Saved creator recipes
- User-owned recipes
- YouTube-generated recipes
- Copied personal versions

Suggested filters:

- All
- Saved
- Created by me
- Recently cooked

## Phase 5 — Create my version

Add copy-on-write behavior:

- Non-owned recipe
- Create my version
- User-owned editable copy

The copy preserves:

- Source type
- Source ID
- Source title
- Source URL if available
- Copied timestamp

## Phase 6 — Unified navigation

Align navigation around:

- Home
- Recipes
- Kitchen
- My Recipes
- Me

Recipe exploration should include:

- Public search
- AI search
- YouTube search
- Recommendations

## Phase 7 — Canonical recipe identity

Optional later phase.

Add recipe_catalog to assign canonical IDs to all recipe sources.

## Rollback strategy

- Keep existing routes
- Keep existing repositories
- Put unified detail page behind a feature flag if needed
- Avoid destructive DB migrations until later phases

## Recommended PR breakdown

1. feat: add unified recipe domain contracts
2. feat: add unified recipe repository
3. feat: unify recipe detail experience
4. feat: unify personal recipe library
5. feat: add personal recipe versions
6. feat: add canonical recipe identities

## Regression areas

Each phase must verify:

- Public recipe search/detail
- Creator recipe detail
- My recipe detail
- Bookmark/save behavior
- Shopping preparation
- Shopping completion
- Kitchen cleanup and undo
- YouTube recipe generation
- Login redirects
