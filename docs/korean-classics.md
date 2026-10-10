# Korean classics home and recipe actions

## Current implementation (included in signed v58)

The home presents fifteen editorial Korean dishes independently of Supabase
login and public recipe search. Each dish has a curated video source from a
creator other than the previously repeated single featured chef. The catalog
ships with the app; this change needs no migration, function deployment, or
per-view YouTube search call.

- Guests can browse all fifteen dishes, filter categories, and open videos.
- Cards identify the original creator. Recipes may be different variations of
  the same dish (e.g. Korean tuna bibimbap and scallion pajeon).
- AI generation remains an explicit, authenticated action. Drafts start with the
  selected source, not invented ingredients or steps. Users must check quantities
  and cooking instructions against the video before saving.
- Where a creator provides a recipe page, the card links to that source.
- Thumbnails use YouTube hqdefault. A failed image keeps the dish label and
  navigation available. Video playback opens YouTube/the browser and never
  starts automatically.
- Cooking focus text is Recipe Scout editorial guidance, not copied transcripts
  or an endorsement by the creators. No ratings, timings, servings, nutrition,
  or professional certifications are inferred.

## Recipe actions

Manual recipe creation is available through the accessible plus icon in the
notebook app bar (tooltip: New recipe / 새 레시피). The floating button has been
removed from both notebook routes so it cannot cover recipe cards. Returning
from a successful creation still refreshes the list.

Creator recipe details show Chef workspace and Prepare shopping list as equal
mint cards, with matching icon size, typography, borders, and touch targets.
Narrow layouts and large text stack the pair. The existing destinations and
shopping ingredient check are preserved. Optional AI enrichment follows the pair.

## Source register (metadata checked 2026-09-13)

All thirty links returned a title and channel successfully through YouTube's
public oEmbed endpoint. Two initially unavailable Korean candidates were replaced
before inclusion. This verifies public link metadata, not full video playback,
regional availability, the accuracy of every cooking step, or AI success rate.
Korean channel names below are shortened display credits. English videos are
by Maangchi. No video files, captions, popularity metrics, or ratings are stored.

| Dish | Korean source | English source |
| --- | --- | --- |
| 비빔밥 / Bibimbap | [하루한끼](https://www.youtube.com/watch?v=p0JEtaprf2c) | [Maangchi](https://www.youtube.com/watch?v=6QQ67F8y2b8) |
| 불고기 / Bulgogi | [Maangchi](https://www.youtube.com/watch?v=3qBjL_HGvco) | [Maangchi](https://www.youtube.com/watch?v=3qBjL_HGvco) |
| 김치찌개 / Kimchi jjigae | [Maangchi](https://www.youtube.com/watch?v=rJgb92JWMCE) | [Maangchi](https://www.youtube.com/watch?v=rJgb92JWMCE) |
| 된장찌개 / Doenjang jjigae | [Maangchi](https://www.youtube.com/watch?v=Slj_fM1jQVo) | [Maangchi](https://www.youtube.com/watch?v=Slj_fM1jQVo) |
| 잡채 / Japchae | [Maangchi](https://www.youtube.com/watch?v=i1djfV9uigc) | [Maangchi](https://www.youtube.com/watch?v=i1djfV9uigc) |
| 떡볶이 / Tteokbokki | [Maangchi](https://www.youtube.com/watch?v=TA3Uo3a9674) | [Maangchi](https://www.youtube.com/watch?v=TA3Uo3a9674) |
| 삼계탕 / Samgyetang | [여의도 육퇴클럽](https://www.youtube.com/watch?v=zuuhl1MKWss) | [Maangchi](https://www.youtube.com/watch?v=JUmFtHqwrnk) |
| 갈비찜 / Galbi jjim | [Maangchi](https://www.youtube.com/watch?v=vtGzj6cUn7Q) | [Maangchi](https://www.youtube.com/watch?v=vtGzj6cUn7Q) |
| 파전 / Pajeon | [Maangchi](https://www.youtube.com/watch?v=RXcsHj1l-Pc) | [Maangchi](https://www.youtube.com/watch?v=RXcsHj1l-Pc) |
| 김밥 / Gimbap | [Maangchi](https://www.youtube.com/watch?v=Y-Y9CXGRJPU) | [Maangchi](https://www.youtube.com/watch?v=Y-Y9CXGRJPU) |
| 김치볶음밥 / Kimchi fried rice | [Maangchi](https://www.youtube.com/watch?v=Lf44Fk7H24s) | [Maangchi](https://www.youtube.com/watch?v=Lf44Fk7H24s) |
| 순두부찌개 / Sundubu jjigae | [Maangchi](https://www.youtube.com/watch?v=BvZ9m3Bikuw) | [Maangchi](https://www.youtube.com/watch?v=BvZ9m3Bikuw) |
| 제육볶음 / Spicy pork stir-fry | [Maangchi](https://www.youtube.com/watch?v=3oFCGKmzQX8) | [Maangchi](https://www.youtube.com/watch?v=3oFCGKmzQX8) |
| 닭볶음탕 / Dakbokkeumtang | [Maangchi](https://www.youtube.com/watch?v=bDXL_g6kJ5U) | [Maangchi](https://www.youtube.com/watch?v=bDXL_g6kJ5U) |
| 미역국 / Miyeokguk | [Maangchi](https://www.youtube.com/watch?v=znpwSp0Ro2I) | [Maangchi](https://www.youtube.com/watch?v=znpwSp0Ro2I) |

## Maintenance and validation

Edit `lib/features/home/domain/korean_classics.dart` for catalog selections.
Before release, review the exact video, cooking language, dish variation, creator,
and continued availability. Catalog changes currently require an app release.
A future remotely managed catalog can retain this local list as an offline fallback.

Tests cover fifteen distinct dishes, thirty distinct video IDs, locale-selected
playback and draft seeds, guest AI gating, launcher failure recovery, all cards
at 320px with 200% text, equal action geometry and independent callbacks, and
app-bar creation followed by list refresh. Real Flutter screen previews use
fixture recipe data and are not screenshots from an installed phone build.
Android playback and live AI generation remain separate device checks.

Optional captures:

```powershell
$env:SCOUT_PREVIEW_FONT='C:/Windows/Fonts/malgun.ttf'
$env:SCOUT_PREVIEW_OUTPUT='.artifacts/home15-preview'
.fvm/flutter_sdk/bin/flutter.bat test --no-pub test/features/design/recipe_scout_preview_test.dart
```

Validation completed 2026-09-13 with the pinned Flutter 3.44.8 SDK:
`flutter analyze --no-pub` reported no issues; `flutter test --no-pub`
passed 216 tests with 4 existing opt-in skips. The separate fixture render run
passed 14 tests and produced Korean/English notebook and detail previews.
`tools/dev/verify.ps1` was also run; after its const lint was fixed, analyze and
the full suite were rerun directly as above. Doctor reported existing SDK PATH,
Android-toolchain, and Windows Visual Studio environment warnings. The subsequent signed v58 release is documented in `docs/release-notes-v58-ko.md`; no production deployment or phone installation was performed.
