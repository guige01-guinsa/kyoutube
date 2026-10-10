# Recipe Scout v89 (1.0.1+89)

## 변경 사항

- 장보기 도우미 → 장보기 목록 정리 메뉴를 웹·Android 공통 화면에 추가했습니다.
- 선택한 장보기 목록을 분류별로 취합하고 필요량·확인한 보유량·구매 예정량을 구분합니다.
- AI가 분류와 동일 재료를 추천합니다. 이름이 다른 재료는 사용자가 확인한 경우에만 합칩니다.
- kg/g, L/ml와 호환되는 개수 단위를 합산합니다. 불명확한 포장·조리 단위는 추정하지 않습니다.
- 목록 확정, 복사, 구매처 찾기, 합치기 취소를 제공합니다.

## 운영 AI 배포 (2026-09-27)

사용자 승인으로 기존 `ai_purchase_request_review` 함수를 버전 4로 배포했습니다. 기존 함수 소스를 백업했으며 배포된 7개 소스 파일이 로컬과 일치합니다. 인증 검증을 유지하고 다른 함수·DB 마이그레이션·프로젝트 설정은 변경하지 않았습니다.

- 서버 처리 테스트 17개 통과.
- 비인증·잘못된 인증·익명 키 요청 401, 웹 CORS 검사 통과.
- 임시 테스트 계정으로 실제 AI 호출 1회 성공(HTTP 200): 양파/onion 동일 재료 추천, 당근 및 진간장 분류 확인.
- 사용량 기록 성공 확인. 테스트 계정과 관련 사용량 자료 삭제 확인.
- 배포 기록: `.artifacts/v89-purchase-review-function-deployment.json`.
- 실제 호출 검증: `release/verify-v89-ai-live.json`.

## Android 출시 파일

- 파일: `release/recipe-scout-v89.aab` (78,602,947 bytes, 약 75 MiB).
- 앱 ID `com.kyoutube.app`, 버전 `1.0.1+89`, targetSdk 36 확인.
- SHA-256: `5610a5be49fcf53c6310b6f1a80a31057d78035e09c8763d83932656a6f8f6f6`.
- 정적 분석 통과, Flutter 테스트 689개 통과·조건부 4개 제외.
- 기존 v88과 업로드 서명·권한 동일, 필수 Android/plugin 진입점 16개 유지.
- 글꼴·자산·R8 메타데이터·Google bundletool 검사 통과.
- 네이티브 라이브러리 12개 ELF 16KB 정렬 및 번들의 PAGE_ALIGNMENT_16K 확인. 실제 16KB 기기 실행 검증은 별도입니다.
- 기록한 소스 파일 327개가 빌드 중 변경되지 않았고 기존 v88 AAB 해시도 유지됐습니다.
- 상세 검증: `release/recipe-scout-v89-verification.json`.
- Play 출시 설명: `release/recipe-scout-v89-release-notes.txt`.

## 웹 운영 배포 완료 (2026-09-27)

- 운영 주소: https://recipe-scout-workspace.web.app/
- 새 메뉴: https://recipe-scout-workspace.web.app/#/shopping-preparation (첫 방문자는 이용 목적 선택 후 장보기 → 장보기 목록 정리로 이동).
- Firebase Hosting 버전: `projects/1080683616982/sites/recipe-scout-workspace/versions/43e3fc12e60856ea`.
- 공개 `release-info.json`의 버전 `1.0.1+89`와 실제 `main.dart.js` SHA-256 `b672192bfc9904bd4308b2206c572b2176d2ef4ffdca1f9355c5330db3c4d312`가 검증된 빌드와 일치합니다.
- HTTPS·보안 헤더·서버 CORS·한국어/영어 PC·모바일 및 로그인 화면 검사 9개 통과. 콘솔 오류·HTTP 오류 없음.
- 새 경로는 한영 각각 최초 이용 목적 선택 → 비로그인 안내 → 로그인 화면 연결을 확인했습니다. 최초 검사에서는 이용 목적 선택 절차가 빠져 실패했으며, 절차를 보완한 검사에서 통과했습니다. 제품 소스 변경은 없었습니다.
- 로그인된 계정의 전체 구매 흐름과 Android 실기기 동작은 이번 배포 후 브라우저 검사에 포함하지 않았습니다. 화면 동작은 Flutter 테스트, 실제 AI 서버 연결은 별도 임시 계정 호출로 검증했습니다.
- 상세 기록: `release/recipe-scout-v89-deployment.json`.

## 사용 범위

- AI 비교는 선택한 최대 20개 재료 범위 안에서 진행합니다.
- 정리 결과는 기기·브라우저별로 저장하며 웹·앱 간 자동 동기화하지 않습니다.
- 이름이 다른 재료를 합친 결과는 구매 준비용입니다. 실제 구매 기록은 원래 재료별로 입력합니다.
- Google Play Console 업로드·심사 제출 및 휴대폰 설치는 별도입니다.
- 이번 배포는 재료 분류 AI에 관한 것입니다. 쿠팡 파트너스 API의 키 등록·서버 배포·실제 호출 검증 완료를 뜻하지 않습니다.
