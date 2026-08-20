# Unified Recipe Experience Design

## Goal

Users should experience all recipes as one concept: Recipe.

Internal recipe sources remain:

- public
- creator
- user

These source types are implementation details. They should not appear as separate recipe product types to users.

## User-facing model

Users see one thing:

- Recipe

All recipes should support the same core actions where permissions allow:

- View details
- Save to My Recipes
- Prepare shopping
- Start cooking
- Share
- Rate or record cooking history

Editing is permission-based:

- Owned recipe: edit and delete
- Non-owned recipe: create my version

## Key UX decisions

### One detail experience

All recipe sources should eventually use one detail page:

- UnifiedRecipeDetailPage

Existing routes remain compatible:

- /recipes/:id
- /creator/:id
- /my-recipes/:id

Optional new unified route:

- /recipe/:source/:id

### Save vs Create my version

Save means adding the source recipe to the user library without duplicating content.

Create my version means creating a user-owned editable copy while preserving the original source reference.

### My Recipes is a library

My Recipes should contain:

- Saved recipes
- User-created recipes
- YouTube-generated recipes
- Copied or personal versions
- Recently cooked recipes

Suggested filters:

- All
- Saved
- Created by me
- Recently cooked

## Unified domain concepts

### RecipeIdentity

- sourceType: public | creator | user
- sourceId: string
- reference: sourceType:sourceId

### UnifiedRecipe

Common fields:

- identity
- title
- summary
- imageUrl
- ingredients
- steps
- origin
- access
- provenance

### RecipeAccess

Permission fields:

- canSave
- canEdit
- canDelete
- canCreatePersonalVersion
- canShop
- canCook
- canShare

## Completion criteria

The unified recipe experience is complete when:

1. All recipe sources share the same detail layout.
2. Save, shopping, cooking, and sharing are available consistently.
3. Owned recipes show edit and delete.
4. Non-owned recipes show create my version.
5. My Recipes combines saved and owned recipes.
6. Existing source references continue to work.
7. Existing routes remain compatible.
8. Analyze and tests pass.
