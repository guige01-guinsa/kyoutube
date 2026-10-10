# v84 운영 웹·식단 DB 반영 및 Android AAB (2026-09-25)

사용자의 운영 웹·앱 배포 요청으로 승인된 아이보리·플럼·살구 디자인과 업소별 식단 관리를 함께 반영했다. Firebase 운영 웹은 `1.0.1+84`, Android는 같은 버전의 서명 AAB를 생성했다. **Play Console 업로드·심사·설치된 앱의 업데이트는 아직 수행하지 않았다.**

## 제공 파일과 사용 경로

- 운영 웹: https://recipe-scout-workspace.web.app/
- Android: [recipe-scout-v84.aab](../release/recipe-scout-v84.aab), `com.kyoutube.app`, `1.0.1+84`, 81,018,976 bytes.
- [Play 출시 문구](../release/recipe-scout-v84-release-notes.txt).
- 업소·전문가 → 소속 업소 → 업무홈 → **식단 달력**.
- 개인 홈은 사진 중심 구성, 레시피 가져오기·직접 만들기, 밝은 탐색 메뉴와 새 공통 색상을 사용한다. [디자인 범위](design-plum-apricot.md) · [식단 사용법](business-meal-planning.md).

## 운영 DB

`0072_business_meal_planning.sql`만 선택 적용했다. 선행 이력 0068–0071과 변경 대상 함수 정의를 확인하고, 이전 함수 정의를 별도 보관했다. 원본 SQL과 migration history 기록은 같은 트랜잭션으로 적용했다. 적용 후 이력의 SQL이 원본과 동일함을 확인했다. 기존 누락 이력 0048·0057은 변경하지 않았다.

운영 후검증: 식단 관련 네 테이블 RLS, 익명 접근 차단, 인증 사용자 직접 쓰기 차단, 내부 스냅샷/도움 함수 실행 제한, 저장·상태 전환·복사 RPC, 달력 인덱스 및 migration history 확인. 운영에 테스트 식단을 만들지 않았다. 기존 제휴 상품 100개 검토 초안도 재등록·공개하지 않았다.

SQL SHA-256: `649339479076589ce78a915054d9393545a1c15078d0c27d885299f83dacdeac`.

## 빌드 검증

고정 Flutter 3.44.8, JDK 17로 필수 릴리스 검사를 통과했다.

- `git diff --check` 통과, `flutter analyze` 오류·경고 0.
- 전체 `flutter test`: **648 통과, 기존 조건부 4 제외, 실패 0**.
- 격리 PGlite 계약 검사 280개를 통과한 보고서와 최종 0072 SQL 해시 일치 확인. 운영 적용 후 권한·스키마 검사는 별도로 수행했다.
- Android bundleRelease 성공, 최종 AAB 서명 및 Manifest 버전 확인. v83과 업로드 인증서 동일.
- 최종 ZIP의 FontManifest·AssetManifest·NOTICES·한국어 폰트가 비어 있지 않음. MaterialIcons 1,645,184 bytes가 고정 SDK 원본과 정확히 일치한다.
- 웹과 Android를 순서대로 빌드해 공용 빌드 자산의 충돌을 방지했다. 325개 빌드 입력 파일 해시가 배포 직전까지 유지됐다.
- 웹 자격증명 검사 통과, source map 없음, 운영 환경 및 프로젝트 확인.

AAB SHA-256: `d17ab3d34939e6ae7aea311c4cfa1385953aee90b3cd55a2642057769809991e`.

웹 main.dart.js SHA-256: `e873a322704e8f3303a77a6c20ca172bb7e404831d5b4789016acc71cfbb1a23`.

## 운영 웹 확인

Firebase Hosting 배포 성공 후 운영 `release-info.json`과 실제 내려받은 `main.dart.js` 해시가 검증한 v84 빌드와 일치했다. HTTPS, 보안 헤더, 한국어·영어 PC/모바일, 이메일 로그인 진입, Google/Kakao 인증 공급자 설정 및 CORS, 기존 주방 쓰기 API OPTIONS 검사를 통과했다. 브라우저 콘솔 오류·HTTP 오류 0건.

별도 게스트 환경에서 새 홈의 레시피 가져오기/직접 만들기 버튼을 한영 PC·모바일로 검사했고, 직접 만들기가 로그인으로 연결됨을 확인했다. [실제 운영 PC 홈](../.artifacts/release-v84/home-ko-desktop.png) · [실제 운영 모바일 홈](../.artifacts/release-v84/home-ko-mobile.png)의 새 색상·사진·정상 아이콘을 시각적으로 검수했다. 캡처는 운영 웹 화면이며 사용자 계정 데이터에 쓰지 않았다.

증거: `.artifacts/release-v84/web-public-smoke.json`, `design-smoke.json`, `web-deployed.json`.

## 남은 앱 출시 단계

Play Console 브라우저 연결 도구가 두 번 모두 실행 환경 초기화 오류로 실패했다. 사용자 프로필이나 인증 정보를 우회 사용하지 않았다. AAB와 출시 문구는 준비됐지만 업로드·출시는 수행되지 않았다. 기존 설치 앱은 Play에서 새 버전을 출시하고 업데이트하기 전까지 v84가 아니다. v83 공개 테스트는 사용자가 제공한 제출 62 화면에서 출시 완료가 확인된 상태다.

인증된 계정의 실제 소셜 로그인 왕복, 운영 식단 작성·확정·구매 전 과정, 실제 Android 기기 설치 후 화면 검수는 이번 운영 읽기 전용 점검에 포함하지 않는다. SQL 계약 검사와 폰트/서명 검증을 기기 검증으로 표현하지 않는다.

증거: `.artifacts/release-v84/`의 DB 적용·검증, AAB 검증, 웹 배포 보고서와 빌드 로그. 이전 doctor의 전역 SDK PATH·Android 라이선스 상태·Windows 개발 도구 경고와 별개로 지정 SDK의 이번 Android 릴리스 빌드는 성공했다.
