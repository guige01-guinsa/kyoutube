# Legacy Kitchen Reference Apply Plan

Last update: 2026-07-22

## Purpose
- Reuse proven design principles from an earlier kitchen/recipe product line.
- Filter them against the current Flutter + Supabase app so only applicable guidance remains.
- Turn reference material into immediate implementation order for this repo.

## External reference set reviewed
The following legacy design documents were reviewed outside this workspace and distilled here:
- Our home fridge diet AI design
- Kitchen flow architecture and validation
- Kitchen personal recipe reuse plan
- Kitchen recipe cooking experience plan

## What was validated against the current repo

### 1. Kitchen summary should come from a single backend rule
Legacy principle:
- Home summary numbers should be computed once on the backend and only displayed by the client.

Current repo status:
- Partially aligned.
- The app already reads kitchen summary through one repository path and one provider:
  - `RecipeRepository.getKitchenSummary()`
  - `kitchenSummaryProvider`
- Home and kitchen screens both consume the same summary structure.

Current evidence in repo:
- Home uses `kitchenSummaryProvider` in the summary card.
- Kitchen page invalidates and refreshes the same provider after mutations.

Assessment:
- Keep this rule.
- Treat backend summary as the single source of truth.
- Avoid adding front-end-only reinterpretation of summary counts.

### 2. Personal recipe reuse is a core product asset
Legacy principle:
- Public reference recipes should be copyable into a user-owned recipe space.
- Personal recipes should accumulate over time and feed downstream actions.

Current repo status:
- Strongly aligned.
- Copy-to-my-recipes, subscriber recipe listing, detail, notes update, and delete flows already exist.

Current evidence in repo:
- `createSubscriberRecipeFromPublic()` exists in the repository contract and Supabase implementation.
- Public recipe detail supports copy to my recipes.
- Subscriber recipe pages and routes already exist.

Assessment:
- Keep this rule.
- This area is already mature enough for release-phase hardening rather than redesign.

### 3. Cooking experience should be a guided flow, not only a detail page
Legacy principle:
- Users should move from recipe choice to preparation to real cooking with state continuity.
- Cooking mode should preserve step state and reduce interaction overhead.

Current repo status:
- Mostly aligned.
- The current recipe detail already has guided step progression, auto advance persistence, and voice guide integration.

Current evidence in repo:
- Auto advance preferences persist.
- Current step index persists per recipe.
- Cook completion records are saved and kitchen summary is refreshed.

Assessment:
- Keep this rule.
- The next work here is performance and polish, not architecture rework.

### 4. Validation must follow end-to-end user flow, not isolated screens only
Legacy principle:
- The important test path is: summary -> recipe -> shopping -> kitchen -> cook completion -> summary refresh.

Current repo status:
- Partially aligned.
- Manual smoke and targeted feature checks exist, but a single end-to-end validation standard for the current Flutter app is still incomplete.

Assessment:
- Adopt this rule directly.
- Future validation should measure both correctness and responsiveness across the same flow.

## What should be applied now

### Apply now: Step 4 performance hardening
These items fit the current codebase directly.

1. Add startup timing visibility
- Measure total bootstrap time until `OpsMonitorService.markReady()`.
- Record phase timings for Firebase, FCM, and Supabase initialization.
- Surface the result in logs or the operations dashboard.

2. Reduce search-triggered fetch churn
- The home screen currently changes the recipe query as the user types.
- Add a debounce or staged query commit before refetch.
- Validate reduced network churn on Android.

3. Stabilize thumbnail and list rendering
- Tune recipe thumbnail loading with explicit sizing and better cache behavior.
- Recheck long-list scroll behavior on the home feed.
- Keep placeholders error-safe and fast.

4. Add request timing on hot paths
- Public recipe list
- Kitchen summary
- Recipe detail fetch

5. Reframe manual validation around one flow
- Launch app
- Home search
- Open recipe detail
- Copy to my recipes or create shopping item
- Return and verify summary refresh
- Complete Google login path

## What should not be imported blindly

1. Health-diet analysis scope
- The older product included health-check and diet guidance scope.
- The current app does not need to expand into medical or health advisory logic now.

2. Large multi-household ownership model
- The older product assumed site, household, and resident ownership boundaries.
- The current app uses a simpler auth/profile model and should keep that smaller scope for now.

3. Broad i18n release criteria
- The legacy plan expected Korean/English/Japanese release strings.
- This repo does not yet show localization infrastructure, so Step 4 should not depend on full i18n rollout.

## Recommended implementation order for this repo

### Slice 1: observability baseline
Target files:
- `lib/app.dart`
- `lib/core/ops/ops_monitor_service.dart`
- `lib/core/ops/presentation/ops_dashboard_page.dart`

Goal:
- Make startup cost measurable before optimizing behavior.

### Slice 2: search and home feed tuning
Target files:
- `lib/features/home/presentation/home_page.dart`
- recipe provider/query path

Goal:
- Prevent avoidable refetch on every keystroke.

### Slice 3: image and list tuning
Target files:
- `lib/features/recipes/presentation/recipe_thumbnail.dart`
- home list rendering path

Goal:
- Improve perceived smoothness during scroll.

### Slice 4: end-to-end validation note
Target files:
- `docs/work-log-2026-07-22.md`
- existing smoke checklist docs

Goal:
- Record before/after measurements and the validation path used.

## Completion criteria derived from legacy references
Step 4 can be called complete only when all of the following are true:
- Startup timing is measured and visible.
- Home search no longer causes obvious fetch storms while typing.
- Recipe thumbnails and home list rendering are tuned and manually checked on Android.
- At least one end-to-end flow is revalidated after optimization.
- The result is documented with before/after observations.

## Decision
- The legacy references are useful and compatible.
- They support the current architecture direction.
- They do not require a redesign.
- They justify moving Step 4 forward as a focused hardening phase rather than a broad feature phase.
