# 레시피 스카우트 디자인 개편 — 2026-09-24

## 적용 범위

기존 숲색·크림색 브랜드를 유지하면서 첫 행동과 자료의 소유 영역을 더 분명하게 정리했다. 홈, 업소 업무홈/자료목록, 장보기 도우미, 공급업체 관리, 공통 탐색과 제휴 상품 관리 화면에 적용했다. 3명의 담당 에이전트가 영역별 구현과 검토를 분담하고 루트에서 공통 테마·탐색과 통합 검증을 진행했다.

- **일반 사용자 홈:** 검색 → 영상/재료/저장 레시피 바로가기 → 로그인 사용자의 주방 요약 → 한식 큐레이션 순서. 큰 음식 사진보다 실제 행동을 먼저 제공한다. 저장 위치와 사용자 이름 기반 레시피명은 유지한다.
- **업소·전문가:** 개인/공동 업무의 소유·공유 안내를 유지한다. 실제 권한에 맞는 승인 대기 확인, 판매 메뉴 구매, 메뉴 관리 등을 강조한다. 긴 업무 흐름 설명과 부가 도구는 펼쳐 볼 수 있다.
- **자료 목록:** 데스크톱에는 제목·실제 상태·버전·실제 수정일 비교 열, 모바일/큰 글씨에는 간격 있는 카드. 검색은 기존대로 현재 페이지 제목 검색이며 서버 전체 검색으로 바꾸지 않았다.
- **장보기:** 구매할 재료와 필요 수량, 구매처 찾기, 구매 기록을 먼저 표시한다. 관리 도구·상세 설명은 접어 보관하며 빈 목록에는 다음 행동을 제공한다.
- **공급업체:** 최초 등록 안내와 등록 후 관리를 분리한다. 공개 상태, 배송·주문 조건, 판매 중/중지 상품을 구분하며 상품은 넓은 화면 2열·좁은 화면 1열이다. 공개 전 확인과 계정 변경 시 보호를 유지·보강했다.
- **제휴 관리자:** 목록 폭을 제한하고 상품별 간격을 늘렸다. 기존 개별/선택 등록·수정·공개·휴지통·복원·가져오기 기능은 유지한다.

## 공통 디자인과 탐색

`ScoutStyle`에서 사이드바·글자·선택 색상, 읽기 840 / 폼 900 / 업무 1200 / 사이드바 246 / 데스크톱 전환 1100 폭을 정의한다. 기존 호환용 contentWidth는 읽기 폭을 사용한다. 일반/업소의 데스크톱 사이드바를 같은 짙은 녹색과 민트 선택 배경으로 통일했고 미선택 칩과 선택 칩을 구별한다. 모바일 메뉴 이름은 항상 표시한다.

전문가의 모바일 주요 메뉴는 작업공간·레시피 수집·개인 레시피·개인 구매·더보기의 5개다. 개인 연구는 더보기의 업무 도구에서 접근한다. 데스크톱의 개인 연구 직접 메뉴는 유지한다. 업소 권한상 6개 메뉴가 필요한 경우 모바일 경영관리는 더보기 시트에 표시하며, 구매·입고/경영 권한은 실제 업소 권한으로 판단한다. 권한이 없는 메뉴를 새로 노출하지 않는다.

중복 역할 전환 버튼과 첫 화면의 반복 안내를 줄였으며 공식 사용 안내는 작업 아래에서 계속 접근할 수 있다. 로그인·데이터 소유·레시피 수집·편집 종료 보호·기존 구매 승인과 저장 동작을 유지한다.

## 검증

지정 Flutter 3.44.8 SDK의 `tools/dev/verify.ps1` **종료 코드 0**. 정적 분석 **0건**, 전체 Flutter **616개 통과·기존 4개 제외**. 로그는 `.artifacts/design-refresh-final-verify.log`에 있다.

새 검증에는 작은 화면/글자 200% 한국어·영어, 실제 권한별 업무홈, 자료목록의 상태·수정일, 모바일 경영관리 시트, 개인 연구에서 더보기로 복귀, 계정 전환과 기존 편집 종료 보호가 포함된다. 홈/업소/장보기/공급업체의 대표 미리보기 8장을 직접 확인했다. 최종 업무 폭 적용 후 캡처 9개 검사와 더보기 복귀를 포함한 탐색 15개 검사도 통과했다.

`flutter doctor`의 기존 PATH SDK 경고, Android 라이선스 상태 확인 경고, Visual Studio 설치 미완료는 남아 있다. 이번에는 웹 운영 배포·Android 빌드·실물 휴대폰 설치를 검증하지 않았다.

대표 화면은 네트워크/운영 자료 없이 fixture로 렌더링했다. 샘플 업체명·연락처·구매 기록은 가상 값이며 홈 음식 사진은 로컬 테스트 자료이다. 실제 운영 DB를 조회한 스크린샷이 아니다.

- `.artifacts/design-refresh/home-390-ko.png`
- `.artifacts/design-refresh/home-1440-ko.png`
- `.artifacts/design-refresh/business-home-1440.png`
- `.artifacts/design-refresh/business-records-1440.png`
- `.artifacts/design-refresh/business-records-390.png`
- `.artifacts/design-refresh/shopping-mobile.png`
- `.artifacts/design-refresh/supplier-desktop.png`
- `.artifacts/design-refresh/supplier-mobile.png`

캡처 재현은 지정 SDK `.fvm/flutter_sdk/bin/flutter.bat test --no-pub`에 아래 옵션/테스트를 사용한다. 한글 폰트는 번들 또는 Windows 로컬 폰트를 사용한다.

- 홈: `--dart-define=HOME_DESIGN_CAPTURE=true test/features/design/home_layout_test.dart`
- 업무: `SCOUT_REORG_PREVIEW` 환경변수를 `.artifacts/design-refresh` 절대 경로로 지정하고 `test/features/business/business_design_test.dart` 실행
- 공급업체: `--dart-define=DESIGN_TRADE_SCREENSHOTS=true test/features/suppliers/supplier_business_design_test.dart`
- 장보기: `--dart-define=SHOPPING_SCREENSHOTS=true test/features/shopping/shopping_assistant_widget_test.dart`

전체 검증은 `powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1`로 수행한다.

## 반영 상태와 후속 릴리스

v81 운영 릴리스에서 디자인 개편을 Firebase Hosting에 반영하고 새 AAB를 생성했다. 디자인 자체에는 DB/Edge Function 변경이 없지만, 같은 릴리스에서 제휴 카탈로그 migration 0071을 선택 적용했다. 100개 초안 상품은 운영에 등록·공개하지 않았으며, 기존 미커밋 작업은 보존했다. Play 업로드는 수행하지 않았다.
