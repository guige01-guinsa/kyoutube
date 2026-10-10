# 레시피 스카우트 디자인 개선

2026-09-09 · Flutter 구현 및 화면 검증 기록

## 디자인 방향

크림색 배경, 짙은 청록색, 살구색 강조를 사용한 요리 노트입니다. 사용자가 영상에서 요리를 발견하고, AI 초안을 검토하고, 레시피를 보관하고, 필요한 재료를 구매하는 흐름을 중심으로 구성했습니다.

공통 스타일은 `lib/core/theme/app_theme.dart`의 `ScoutStyle`과 `AppTheme`에서 관리합니다. 기존 Flutter 3.44.8, Riverpod, go_router 구조를 사용합니다.

## 적용한 화면

- 홈: 고정 브랜드, 검색, 영상 레시피 찾기, 재료 검색, 사용 가이드, 로그인 사용자의 장보기 요약, 이미지 중심 레시피 목록.
- 주요 화면 이동: 홈 / 내 레시피 / 장보기 하단 메뉴. 기존 경로를 사용하며 메뉴 전환 시 이동 기록이 계속 쌓이지 않습니다.
- 내 레시피: 노트형 카드, 출처 및 정보 상태, 검색과 정렬, 검색 제외 레시피의 썸네일과 일관된 카드 디자인.
- 상세: 공통 요약, 재료 목록, 번호가 있는 조리 단계 카드. 공개·직접 작성·개인 레시피가 같은 읽기 컴포넌트를 사용합니다.
- 조리: 단계 체크와 진행 표시. 체크는 화면 내 보조 표시이며 조리 완료 기록을 저장하는 동작과 분리됩니다. 기존 무음 단계 안내 기능의 설명도 실제 동작에 맞췄습니다.
- 장보기: 요약 영역을 스크롤할 수 있게 하고 재료별 반복 입력 폼을 구매 체크와 상태 메뉴로 정리했습니다. 구매·건너뜀·구매 불가 상태와 재료 수정 기능은 기존 처리 경로를 사용합니다. 검토가 필요한 재료는 구매 전에 기존 검토 창을 엽니다.
- 재료 선택: 선택 개수, 짧은 상태 설명, 하단 목록 생성 버튼. 초안 읽기 실패 시 재시도할 수 있습니다.
- AI 초안: 영상 선택 → AI 초안 → 확인 후 저장의 흐름과 현재 상태를 표시합니다.
- 빈 화면과 오류: 읽기 쉬운 안내 및 재시도. 개발용 운영·FCM 패널은 더보기의 개발 진단 화면으로 이동했습니다. 진단 경로는 릴리스에서 제공하지 않습니다.

## 검증 방법

최종 결과: `verify.ps1` 종료 코드 0, `flutter analyze` 지적 사항 없음, 전체 Flutter 테스트 137개 통과. 별도로 한글 폰트를 로드한 화면 렌더링 6개도 통과했습니다. 보조 글자와 크림색·민트색 배경의 대비는 각각 5.15:1, 4.83:1입니다.

`flutter doctor`는 기존 PATH, Android SDK 라이선스 상태, Windows 빌드 도구에 관한 환경 경고를 표시했습니다. 지정된 Flutter 3.44.8과 JDK 17은 확인했으며, 정적 분석과 위젯·단위 테스트는 완료했습니다.

저장소 표준 검증:

```powershell
powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1
```

`test/features/design/`는 주요 화면 이동, 오류 재시도, 조리 단계 체크, 작은 화면과 200% 글자 크기에서의 배치를 확인합니다. `shopping_interaction_test.dart`는 구매 체크와 상태 메뉴가 기존 revision 기반 API 호출을 사용하고, 검토가 필요한 재료가 구매 전에 검토 창을 여는지 확인합니다.

실제 Flutter 위젯을 샘플 데이터로 렌더링하는 이미지 검증:

```powershell
$env:SCOUT_PREVIEW_FONT = 'C:\Windows\Fonts\malgun.ttf'
$env:SCOUT_PREVIEW_OUTPUT = Join-Path (Get-Location) '.artifacts/design-preview'
.\.fvm\flutter_sdk\bin\flutter.bat test --no-pub test/features/design/recipe_scout_preview_test.dart
```

이미지는 `home.png`, `notebook.png`, `detail.png`, `steps.png`, `shopping.png`, `review.png`로 생성됩니다. 기본 390×844 화면을 캡처하고 320×640, 글자 200%에서도 배치를 검사합니다. 사진 없는 샘플에는 앱의 실제 대체 이미지가 표시됩니다. 생성 이미지는 Git에서 제외된 `.artifacts/`에 보관합니다.

## 로컬 실행 조건

Docker에서 주요 Supabase 컨테이너가 실행 중인 것은 확인했습니다. 이 작업 폴더에는 `.env.local`이 없어 `run-local.ps1 -AppEnv local`이 앱 시작 전에 중단됩니다. 따라서 이미지 검증은 샘플 데이터 기반이며 로그인·실제 백엔드 연동 또는 Android 실기기 검증을 대신하지 않습니다.

개선 전부터 있던 작업은 유지했습니다. 주요 화면의 비즈니스 로직은 보존하고 화면 구성과 표시, 관련 동작 검증을 중심으로 변경했습니다.
