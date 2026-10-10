# v86 Android AAB 생성·검증 완료 (2026-09-26)

사용자 요청으로 모바일 홈 배치·하단 `내 레시피`·Android 종료 확인 기능을 포함한 **1.0.1+86** 서명 AAB를 생성했다. [AAB](../release/recipe-scout-v86.aab) · [출시 노트](../release/recipe-scout-v86-release-notes.txt) · [검증 기록](release-v86.md).

릴리스 정적 분석 오류 없음, 전체 Flutter **658개 통과·기존 4개 제외**. 실제 AAB 버전/패키지/서명·공식 bundletool·R8·폰트/아이콘·16개 Android 진입점 검증 통과. 85번 업로드 서명 및 9개 네이티브 의존성 유지. DEX 1,544,840 bytes 유지. SHA-256 `6cac3cc632e2c4424fe2d9eadac9e277be7011e2bc5ef2e3b0adecaaf37dadd7`.

**Play 업로드·출시·86번 실기기 설치는 아직 하지 않았다.** 이번 요청은 AAB 생성이며 운영 웹·DB 배포는 하지 않았다. 아래 배포 전 기록은 구현 당시 상태이며, 해당 수정은 이제 v86 AAB에 포함되어 있다.

---

## 2026-09-26 추가 작업: 모바일 홈과 Android 종료 확인 (배포 전)

- 홈 `레시피 가져오기`·`직접 만들기` 한 행, 모바일 제목/여백 축소. 320 너비는 아이콘을 생략해 문구를 한 줄로 표시하고 큰 글자는 세로 배치.
- 하단 내비게이션은 `내 레시피`로 표시. 화면 제목/저장 위치/툴팁의 개인 이름은 유지.
- `lib/core/router/app_exit_confirmation.dart`: GoRouter가 back을 처리하지 않는 루트에서 로그인 상태와 종료 선택지를 표시. 기존 history 및 unsaved onExit가 우선. 명시적 선택 때만 기존 AccountService 로그아웃 후 SystemNavigator.pop. 실패/취소/반복 back은 자동 종료하지 않음.
- `lib/app.dart`: Android에만 custom dispatcher 및 frameworkHandlesBack 연결. 웹/iOS 기존 dispatcher 유지.
- 최종 분석 오류 없음, 전체 Flutter 658개 통과·기존 4개 제외(종료 확인 신규 10개 포함).
- 검증 로그와 한글 320/360 홈·종료창 렌더: `.artifacts/mobile-home-compact/`.
- **아직 새 AAB/운영 웹 배포 안 함. 기존 v85 파일에는 이 수정이 없음.** 실기기에서 이 변경 설치/검증도 미실시. 기존 앱 데이터를 삭제하거나 서명 불일치 설치를 강행하지 말 것.

---

# AI Handoff

## Current state — Android R8 v85 AAB ready, Play/device validation pending (2026-09-26)

User approved reducing R8/DEX warning without harming Recipe Scout and connected a phone. Enabled release minify/resource shrinking only; preserved Flutter3.44.8/AGP9.0.1/JDK17, plugin consumer rules, signing, package ID, app logic, native assets and full icon font. New release/recipe-scout-v85.aab is1.0.1+85, SHA256659ac1aea7e4dbc75b0ec41dc01a70b54eed593eafa9d63b1723b9c03f7c5533. DEX12,067,960 →1,544,840 bytes (87.2% reduction). See [release-v85.md](release-v85.md) and [android-r8-optimization.md](android-r8-optimization.md).

Analyzer and full648 tests passed,4 existing skips. Actual AAB R8 metadata/mapping,16 DEX entrypoints, identical fonts and9 native dependency binaries, unchanged v84 upload certificate verified. Official bundletool validate passed. New R8/packaged-manifest gates:12 regression checks pass. Initial finalize rejected a stale AGP intermediate manifest84 although actual optimized AAB85 was correct. Fixed gate to read actual AAB via pinned official bundletool1.18.3 at.artifacts/tools; see runbook. App324 inputs remained unchanged, so one-time artifact-only finalization followed already successful quality/build gates. Standard release script still runs analyze/test/build. No bypass switch added.

Connected SM-G977N Android12/API31 has Play82. Installed Play signer differs from upload signer (compared without logging cert values). Never uninstall/clear user data to bypass this. Generated matching5-APK device set locally for compatibility only, debug signed and not for delivery. **No85 install or on-device runtime flow tests completed.** User screenshots confirm84 production review was submitted; old84 docs saying upload pending are historical. Do not cancel84 review. Next: upload85 to Play INTERNAL TEST, use enrolled tester Play account to update, then verify auth/file/photo/share/PDF/notifications/billing and meal flows before promoting. Do not claim risk-free or production deployed. No web/DB/function changes; web remains84. Preserve all unrelated dirty work. Release authorization persists for this scope, but runtime safety gate is unfinished.

Earlier records below are historical.

## Current state — v84 production web/DB deployed, signed AAB ready (2026-09-25)

User explicitly authorized production web/app rollout for the approved ivory/plum/apricot design and business meal planning. Production Hosting now serves1.0.1+84; selective DB0072 applied with migration history in the same transaction. Prior function definitions saved, final SQL and history match, RLS/anonymous/direct-write/private-helper/RPC/index postchecks passed. Do not reapply0072 or fill legacy0048/0057 gaps. No affiliate reimport/publication.

Pinned Flutter3.44.8/JDK17 release gates passed: analyzer0, entire Flutter suite648 passed/4 existing skips/0 failures. This supersedes the prior partial regression report. Android signed release/recipe-scout-v84.aab verified: version84, unchanged v83 upload certificate, nonempty fonts/manifests, MaterialIcons byte-identical to pinned SDK. Web built sequentially after Android;325 input hashes unchanged. Live production JavaScript matches the verified build. Public KO/EN PC/mobile, login entry, auth providers/CORS and kitchen preflight checks passed with no console/HTTP errors. Additional actual new-home screenshots visually inspected in Korean PC/mobile; KO/EN manual-create guest flow reaches login. See [release-v84.md](release-v84.md).

**Play v84 upload/release/device update remains unperformed.** CUA browser initialization failed twice with Windows sandbox setup errors. No browser credential/profile workaround. AAB and release/recipe-scout-v84-release-notes.txt ready. Earlier v83 release is confirmed by user screenshots. Do not imply v84 is on Play. User authorization persists; no new release permission is needed for this approved scope. Real authenticated production meal CRUD/purchase and device install tests remain outside completed checks. Preserve all unrelated dirty/untracked work.

The entries below are historical and their not-deployed statements no longer describe current web/DB status.

## Current state — approved plum/apricot concept applied in code, not deployed (2026-09-25)

User complained the meal calendar retained the old green design. Corrected common palette (ivory/plum/apricot), personal/business desktop headers, editorial home with real curated photo/search/import/manual-create actions, photo-led cards, shared headings, in-app mark, remaining fixed brand colors, and meal date/status cards. Preserved authorization, routing, private/shared data scopes, and exit guards. Android launcher/signing/version untouched. See [design-plum-apricot.md](design-plum-apricot.md) for exact scope and screenshots. Home manual creation routes guests to login. Desktop/mobile screenshots are actual Flutter fixture renders and have been visually inspected.

Final analyzer clean. Required full verify ran:645 passed/4 skips/3 failures from obsolete layout timing/copy assumptions. Fixed those tests and reran the affected suites including all3:33/33 passed (.artifacts/plum-final-regression.txt). Do not describe the original full verify log as green. Other successful checks were not repeated unnecessarily. Doctor's pre-existing warnings remain. No production deploy, DB migration, release build or AAB in this design correction. User needs new-feature release authorization before 0072+web/AAB rollout. Existing v83 remains production. Preserve all unrelated dirty files.

Below are earlier implementation records.

## Current state — business meal planning implemented, not deployed (2026-09-25)

User approved the recommended business-specific meal calendar, weekly/date copy, confirmation and purchasing connection. Implementation is in business_meal.dart, business_meal_repository.dart, business_meal_pages.dart, and new immutable migration 0072_business_meal_planning.sql. Entrypoint: business work home → meal calendar, `/business-workspaces/:workspace/meals`. Existing generic meal records remain in team recipes. Private server helpers and frozen recipe snapshots preserve reviewed portions/revisions; unique meal purchase links and idempotent copy/save/batch requests prevent duplicate work. Confirming uses menus.approve; writing/cooking recipes.write; buying existing purchasing grants. Purchased meals cannot be cancelled silently or purchased again. See [business-meal-planning.md](business-meal-planning.md).

Final verification: tools/dev/verify.ps1 completed, analyzer clean, 647 passing Flutter tests + 4 existing conditional skips. PGlite SQL contract 280 checks passed after adding the calendar index; .artifacts/business-meals-contract.json contains matching 0072 SHA-256. Docker contract attempt could not read local Supabase status and did not run. Doctor reports pre-existing global PATH, Android license unknown, and incomplete Windows VS installation warnings. PC screenshot .artifacts/meal-calendar-desktop.png inspected with real Nanum/MaterialIcons fonts; mobile enlarged text and English layouts tested. No release build, production migration or deploy in this feature turn. Need explicit authorization for deployment of this new feature; prepare 0072 and then web/AAB rollout without applying legacy missing migrations. Preserve every unrelated dirty/untracked file.

Earlier user screenshots confirm v83 public testing released Sept25 17:34 (submission62); do not say Play upload still pending for v83. At that earlier stage the approved plum/apricot concept had not been implemented; the subsequent correction documented above now applies it in code. Existing affiliate 100 review drafts were not reimported/published.


## Current state — v83 design completion (2026-09-25)

Use [release-v83.md](release-v83.md) for current evidence. Production web v83 and signed v83 AAB are complete. Analyzer clean;639 tests passed,4 existing skips. Final AAB fonts/manifests and signing verified; MaterialIcons exactly matches SDK, certificate unchanged fromv82. Play upload/deviceupdate pending. No DB/function deployment and no affiliate draft publication in this UI release. Scope and walkthrough are in design-completion-v83.md and design-v83-user-guide.md. Preserve all unrelated uncommitted work and do not re-import100drafts.

The entries below are historical.


## Current state — v82 recovery (2026-09-24)

Use [release-v82.md](release-v82.md) as current evidence. v82 AAB built and verified, 617 tests passed / 4 skipped, analyzer clean. The actual v81 defect is empty FontManifest.json (and NOTICES.Z), not proven glyph tree shaking. The clean v82 bundle restores font registration; its complete MaterialIcons font matches the pinned SDK. Production AAB script now rejects empty/missing font registration/assets before copying a release. Never redistribute v81. Upload certificate is unchanged. Play upload/device update still pending; the connected device is Play v81, no data cleared.

100 affiliate CSV entries are now production DB review drafts (100 inserted, 0 public). Do not repeat the historical instruction below saying the catalog is empty. Product verification/publication remains unfinished because the sample destination returned HTTP 403; no verification flags were fabricated. Admin location: 관리자 홈 → 제휴 상품 관리. Preserve all unrelated uncommitted work. The prior web v82 deployment predates three final English menu translations and was not repeated during Android recovery.
2026-09-24 v81 released: the design refresh, role-aware navigation, shopping/supplier layouts, and affiliate catalog administration are now deployed. Firebase Hosting serves `1.0.1+81`; public release-info and production security headers were checked. Supabase migration `0071_affiliate_catalog_management` was selectively applied and verified. Legacy missing migrations 0048 and 0057 were intentionally untouched.

The release AAB is [recipe-scout-v81.aab](../release/recipe-scout-v81.aab), package `com.kyoutube.app`, version `1.0.1+81`, SHA-256 `8DDA641BFF656F14B52B6A6A512E435CF602F34CACAEEBA69562FF731BD35C26`; signing was verified. Flutter 3.44.8 analysis was clean and all 616 tests passed with 4 existing conditional skips. The 100 affiliate links remain local review drafts: production catalog count is 0 and nothing was auto-imported or published. Preserve all other pre-existing uncommitted work.
## Purpose

2026-09-12 update: use [CURRENT_STATUS.md](CURRENT_STATUS.md) and
[OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md) for the v53 artifact and post-v53
source. The commit/branch/test snapshots below are historical August context,
not current release evidence. Do not resume the old next-task list blindly.

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
