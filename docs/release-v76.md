# Recipe Scout v76 — 제휴 상품 연결 운영 배포

2026-09-19 사용자 승인: DB 0065 운영 적용·웹 배포·새 서명 AAB 생성.

## 반영 내용

- 회원 관리자 → 제휴 상품 관리: 초안 등록, 수정, 모바일/웹 게시 허용 근거, 공개/숨김, 30일 재확인.
- 장보기 구매처 찾기에 재료 별칭과 일치하는 네이버 제휴 상품 및 YouTube Shopping 상품 태그 영상 연결. 수수료 고지를 표시하고 일반 검색은 계속 제공한다.
- 가입 안내에서 지원 채널 연결과 레시피 스카우트 앱·웹 등록/실적 인정을 명확히 구분했다. 스페이스에 독립 앱·웹을 등록할 수 있다고 단정하지 않는다.
- 네이버·Google 쇼핑 검색 화면 개선도 포함한다. 실제 네이버/YouTube 가입·허용·수익 정산은 운영자가 별도로 진행해야 한다. 제휴 상품은 0개이며 자동 공개하지 않았다.
- 운영 DB 0064는 승인 범위 밖이므로 적용하지 않았다. 기존 business_members 응답에 profile_revision이 없으면 새 담당자 프로필 편집 버튼을 숨긴다. 기존 직원 권한 관리는 유지한다.

## 운영 DB

- 0065만 적용. 기존 마이그레이션 이력을 보존하고 적용 SQL 지문 일치를 확인했다. 현재 마지막 이력은 0063, 0065이며 0064는 미적용이다.
- 암호화 백업 복호화·해시·변조 차단 및 격리 Docker 복원 검증 통과: 98개 테이블, 4,825개 행. 평문 SQL 파일 없이 처리하고 임시 컨테이너를 제거했다.
- 제휴 테이블 RLS, 회원 직접 조회/쓰기 차단, 관리자 MFA, 익명 RPC 차단을 검증했다. 실제 비로그인 HTTP 요청 3개는 모두 401로 차단됐다.
- 첫 사후 검사에서 관리 API의 읽기 역할로 회원 전용 함수를 호출해 권한 오류가 발생했다. 마이그레이션은 이미 정상 커밋되어 재실행하지 않았다. 권한 자체를 조회하는 읽기 검사와 HTTP 차단 검사로 검증을 완료했으며 권한을 완화하지 않았다.

## 웹

- Firebase korea-01 / recipe-scout-workspace 배포 성공.
- 운영: https://recipe-scout-workspace.web.app/#/workspace
- main.dart.js SHA-256: a30a1780590756abcb34c6d76f8ef04906096050591390a1fc189a50f7b50c35
- web.app와 firebaseapp.com의 파일 일치·보안 헤더·한국어/영어·모바일/데스크톱 업무 화면·제휴 관리 경로 포함 로그인 보호 30개 검사 통과. 브라우저 오류 0개, 검증 중 실제 자료 쓰기 0건.

## Android

- `release/recipe-scout-v76.aab`: com.kyoutube.app, 1.0.1+76, 77,643,672 bytes.
- SHA-256: F8EE47FB952B085C6C0A35EE79AEFA2E406E514D59F73ED08D983263DEE2C972
- v75와 동일한 서명 확인. ZIP 무결성, 매니페스트, 운영 서버 설정, 비밀키 미포함, 한국어 PDF 글꼴, 제휴 기능 코드 포함 검증 통과.
- Google Play 업로드와 휴대폰 설치는 수행하지 않았다.

## 검증 및 기록

- Flutter 3.44.8 / JDK 17. 정적 분석 문제 없음, 전체 테스트 503개 통과·기존 4개 건너뛰기. 최종 제휴/번역 집중 테스트 12개 추가 통과.
- 격리 PostgreSQL 제휴 검사 34개 통과. 빌드 입력 파일 238개 지문 일치.
- 기존 CupertinoIcons 글꼴 경고는 빌드에 남았으며 이번 작업에서 관련 없는 패키지를 변경하지 않았다.
- 기록: release/verify-v76.json, verify-v76-db.json, verify-v76-db-http.json, verify-web-v76.json, deploy-web-v76.json, verify-web-v76-build.json, recipe-scout-v76.aab.provenance.json, recipe-scout-v76.aab.sha256.
- 실제 제휴사 계정 승인·실제 구매 전환·수수료 정산은 아직 검증하지 않았다. 다음 단계는 [가입·연결 안내](affiliate-shopping-setup.md)를 따른다.
