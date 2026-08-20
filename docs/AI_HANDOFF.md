# AI Handoff

## Purpose

This document allows a restarted AI/Codex session to resume work without relying on chat memory.

The chat history is not the source of truth.

Use repository files, Git history, AGENTS.md, and docs/CURRENT_STATUS.md.

## Required startup procedure

When starting work, run or inspect:

cd C:\Users\ADMIN\K-youtube-youtube-integration

Get-Content .\AGENTS.md
Get-Content .\docs\CURRENT_STATUS.md
Get-Content .\docs\AI_HANDOFF.md
git status
git log --oneline -10

Then inspect:

Get-Content .\docs\unified-recipe-experience-design.md
Get-Content .\docs\unified-recipe-migration-plan.md

## Tooling rules

Follow AGENTS.md.

Important:

- Flutter 3.44.8 is pinned by .fvmrc.
- Use the FVM SDK under .fvm/flutter_sdk.
- Do not silently use or upgrade a global Flutter SDK.
- Validate changes with:

powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1

## Current branch

feat/unified-recipe-experience

## Current local commits

At the time of this handoff, recent local commits include:

- e7f61ec feat: add unified recipe detail layout
- 14a2846 feat: apply unified layout to recipe detail routes
- 54c67de fix: persist YouTube thumbnail for generated recipes

Always confirm with:

git status
git log --oneline -10

## Current completed work

Unified detail layout:

- lib/features/recipes/presentation/widgets/unified_recipe_detail_layout.dart
- test/features/recipes/presentation/unified_recipe_detail_layout_test.dart

Existing detail route wiring:

- lib/features/recipes/presentation/creator_recipe_detail_page.dart
- lib/features/recipes/presentation/subscriber_recipe_detail_page.dart

YouTube thumbnail fix:

- lib/features/youtube/data/youtube_recipe_creation_service.dart
- lib/features/youtube/domain/youtube_thumbnail_url.dart
- test/features/youtube/domain/youtube_thumbnail_url_test.dart

## Last verification

Command:

powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1

Result:

- flutter analyze: No issues found
- flutter test: 64 tests passed

flutter doctor has local environment warnings. They are known and not caused by the current feature changes.

## Known image behavior

New YouTube-generated recipes should now save:

https://i.ytimg.com/vi/VIDEO_ID/hqdefault.jpg

as image_path.

Existing YouTube recipes with image_path null are not automatically fixed.

Subscriber/user recipes currently do not persist image fields.

Public recipes depend on upstream image_url availability.

## Recommended next work

1. Commit docs/CURRENT_STATUS.md and docs/AI_HANDOFF.md.
2. Push the branch after user approval.
3. Run the app:

powershell -ExecutionPolicy Bypass -File run-local.ps1 -AppEnv local

4. Create a new YouTube recipe.
5. Open the generated recipe detail page.
6. Confirm the thumbnail appears.
7. If needed, add placeholder UI for recipes with no image.
8. Defer subscriber image/provenance preservation to Unified Recipe Phase 5.

## Do not do without explicit approval

- Package upgrades
- Supabase DB reset
- Supabase DB push
- Existing migration edits
- Edge Function deployment
- Production migration
- Release build
- Signing or keystore changes
- Firebase/Supabase project config changes
- Destructive Git cleanup commands
