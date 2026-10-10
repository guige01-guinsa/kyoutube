# Ingredient representative photos

The shopping preparation and assistant cards resolve a small local photo by the
ingredient name. Existing affiliate links and product records do not need to be
edited. These are AI-generated representative ingredient images, not photographs
of the linked sale offer. The thumbnail displays `대표` / `Sample`, with an
accessible explanation. Unmapped names use the bundled generic representative
food photo, so every shopping-list row remains visually complete. Load errors
still show a neutral food icon.

## Initial photo set

25 images: the original ingredient photos plus category photos for pastes,
spices, oils, leafy vegetables, mushrooms, roots, meat cuts, seafood, shellfish,
dairy and grains. Aliases deliberately
avoid substring matching: garlic sauce, potato starch and soft tofu must not
inherit pictures of raw garlic, potatoes or firm tofu. Other ingredients use
the generic representative photo until an appropriate photograph and exact
aliases are added. This is not photo coverage of all affiliate products.

## Files and maintenance

- App assets: `assets/ingredients/*.jpg` (256 × 256), including
  `ingredient-fallback.jpg` for every unmapped ingredient.
- Name catalog: `lib/features/shopping/domain/ingredient_photo.dart`.
- Rendering: `lib/features/shopping/presentation/ingredient_thumbnail.dart`.
- Generation records and original local paths:
  `tools/data/ingredient-image-sources.json`.
- Recreate thumbnail compression from those original files with
  `tools/dev/prepare-ingredient-images.ps1` on the generation machine.

To extend the set, generate and visually verify a separate ingredient photo,
save its small image in the asset directory, then add explicit aliases and
negative matching cases. Do not use brand/product-title substring matches.
No database migration is required for this local asset catalog.

## Generation method and prompt

Created with the built-in image_gen tool (imagegen skill), one tool call per
photo. The prompt for the first onion image:

> Use case: product-mockup. Create one square ingredient representative photograph for a cooking shopping-list thumbnail. Subject: a whole golden yellow onion and half a peeled onion showing white interior. Centered isolated on warm ivory background, soft studio light, natural realistic food texture, generous safe margins, recognisable at 56px. No brand, packaging, text, label or watermark. Single photo, not a collage.

The exact prompts for the remaining 11 images are recorded in the generation
JSON. All use the same ivory background and natural studio-photo treatment.
Original generated files are preserved; small JPG copies are bundled in the app.

## Validation

`ingredient_photo_test.dart` checks identity-safe aliases, file decoding and
size, representative-image labels, fallback and 320px layout. Existing shopping
preparation widget tests cover purchase edits and 200% text layout.
Set `CAPTURE_INGREDIENT_PREVIEW=true` via Flutter's dart-define to export a small
component preview to `output/ingredient-photos/phone-preview.png`.
This preview is a thumbnail component demonstration, not a production screenshot.
