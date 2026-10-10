# Recipe Scout v88 출시 준비 (1.0.1+88)

## 포함된 변경

- 관리자 홈의 상품 등록·공개 도우미와 상품별 확인 항목.
- 회원용 조회를 사용하는 실제 상품 노출 확인 화면.
- 구매처 검색어를 바꾸면 제휴 상품 갱신, 오류 시 재시도.
- 쿠팡 수수료 안내를 상품명 앞에 표시.

## 운영 설정

2026-09-26 사용자가 웹 활동 주소 등록을 확인했습니다. 실제 연결 상품을 확인한 진간장(001, 삼화식품 1.8L 1개)에 한해 웹·모바일 공개를 저장하고 다시 열어 두 설정을 확인했습니다. 나머지 상품은 자동 공개하지 않았습니다. 계정 최종 승인을 확인한 것은 아닙니다.

## 출시 산출물

- Android: release/recipe-scout-v88.aab
- 출시 설명: release/recipe-scout-v88-release-notes.txt
- 검증 결과: release/recipe-scout-v88-verification.json. 코드 분석 통과, 테스트 674개 통과·조건부 4개 제외, 서명·권한·필수 진입점 유지 확인, bundletool 검사 및 12개 네이티브 라이브러리 16KB 정렬 검사 통과. 실제 16KB 기기 실행 검증은 별도입니다.
- 크기: 78,379,302 bytes (약 74.7 MiB). SHA-256: 448d1beea4e43855a0d36674477c2becbfb1d2b77b50ba961a945d105100997d.

## 남은 운영 단계

현재 연결된 휴대폰은 Play에서 설치한 v86입니다. v88 AAB를 Play 테스트 트랙에 업로드한 후 해당 트랙에서 업데이트해야 합니다. 기존 앱을 삭제하거나 서명을 변경하지 않습니다.

관리자용 쿠팡 API 검색·링크 생성 화면은 포함되지만 API 키·서버 배포·실제 API 호출 검증은 아직 완료되지 않았습니다. 서버의 시간당 호출 한도 보완도 필요합니다. 발급 링크를 등록해 쿠팡으로 이동하는 기능과 API 자동화의 준비 상태를 구분해야 합니다.
## 웹 v88 반영 결과

2026-09-26 기존 사이트 https://recipe-scout-workspace.web.app 에 1.0.1+88 배포 완료. 공개 release-info와 실제 main.dart.js 해시가 검증된 파일과 일치합니다. 한국어·영어 데스크톱/모바일 화면, 로그인 화면, 보안 헤더 및 서버 CORS 검사에 통과했습니다. Google·카카오 로그인 버튼의 실제 인증 제공자 리디렉션을 확인했으며 계정 로그인 완료까지 자동 검증한 것은 아닙니다.

- 관리자 도우미: https://recipe-scout-workspace.web.app/#/membership/admin/affiliate-workflow
- 진간장 실제 노출 확인: https://recipe-scout-workspace.web.app/#/membership/admin/affiliate-display?q=%EC%A7%84%EA%B0%84%EC%9E%A5
- 두 관리자 화면은 관리자 로그인과 인증이 필요합니다.
- Play Console 업로드 및 휴대폰 v88 업데이트는 실행하지 않았습니다.