# Recipe Scout v63 — 2026-09-14

사용자 승인으로 DB 0054·0055·0056 운영 적용, 관련 Edge Function 3개 배포 및 v63 서명 AAB 생성·검증을 완료했습니다.
**실제 Google Play 결제는 비활성 상태입니다.** 상품/base plan, 서비스 계정, RTDN 설정과 실제 Play 테스트를 완료한 뒤 구매를 활성화합니다.

## 사용자 변경 사항

- 발견·내 레시피·장보기·셰프의 네 메뉴로 작업을 구분하고, 빈 장보기에서도 구매처와 요청서에 접근합니다.
- Scout 무료 / Recipe Plus / Chef Business의 기능·사용 한도와 월간·연간 선택 화면을 적용했습니다.
- Plus 가격 기준: 월 5,900원 / 연 59,000원. Business: 월 14,900원 / 연 149,000원. 결제 확정 가격은 Google Play의 실제 현지 통화 가격을 사용합니다.
- 원가·판매가·매출은 Business, 요청서 PDF는 Plus/Business가 사용할 수 있도록 서버에서 제한합니다. 연간·월간은 동일 등급의 기능 한도를 공유합니다.
- 영상 분석은 Plus 월 5회, Business 월 20회, 영상당 최대 20분입니다. 전체 정책은 [출시 요금제 문서](launch-billing-implementation.md)를 확인합니다.
- 새 결제 처리는 Google 응답 기반 검증, 계정 귀속, 구매 확정 재시도, 토큰 중복·역순 방어, 다음 결제일 구독 변경, 복원 및 RTDN 처리 코드를 포함합니다. 실제 결제망 검증은 아래에 별도로 남겨 두었습니다.

## 운영 배포 증거

- 프로젝트: `dfczeudklykypysiseck`. DB 완료 시각(UTC): `2026-09-13T21:03:50.403414+00:00`.
- DB 0054 `membership_feature_profiles`, 0055 `launch_membership_tiers`, 0056 `verified_billing_lifecycle`를 하나의 트랜잭션으로 적용했습니다. 운영에 기록된 SQL 3개가 로컬 원본과 일치합니다.
- 기존 RLS 정책과 설치된 함수의 보안 규칙이 보존됐습니다. 신규 비공개 테이블/RPC/시퀀스 권한, 새 가격과 AI/영상/구매 한도, 결제 비활성 조건을 검사했습니다.
- 0047·0048은 이번에 적용하지 않았고 다른 마이그레이션 이력과 비대상 함수는 전후 동일합니다.
- `membership`: revision 9, JWT 검증 Supabase gateway 활성화.
- `ai_youtube_video_assistant`: revision 3, JWT 검증 Supabase gateway 활성화.
- `membership_notifications`: revision 1, JWT 검증 Google OIDC를 함수에서 수행.
- 세 함수 각각의 모든 로컬 import 파일을 원격에서 다시 내려받아 바이트 단위로 대조했습니다.
- 회원·영상 함수의 무인증 및 익명 요청은 HTTP 401, CORS 요청은 정상 응답입니다. RTDN 무인증/잘못된 JWT는 401, 잘못된 메서드는 405로 차단됐습니다.
- 운영 테스트 계정·유료 권한·구매·주문을 생성하지 않았습니다. 비밀값은 변경하거나 출력하지 않았습니다.
- 암호화 백업은 네 스키마의 70개 테이블, 3,247개 행 전체를 네트워크 없는 임시 DB에 복원해 원본과 대조했습니다. 임시 컨테이너는 제거됐습니다. Windows 사용자 DPAPI에 묶인 로컬 백업으로, 타 장비 복원·Storage 파일 원본·서버 비밀값 복원은 별도입니다.

증거: `.artifacts/v63-db-preflight.json`, `.artifacts/v63-db-deployment.json`, `.artifacts/v63-function-deployment.json`, `.artifacts/v63-encrypted-backup-verification.json`, `.artifacts/v63-encrypted-restore-verification.json`.

## 검증

- Flutter 3.44.8 / JDK 17. 새 빌드의 정적 분석 지적 0건, Flutter 293개 통과·기존 선택형 4개 건너뜀.
- 같은 기능 소스의 Deno 51개 통과, 함수 3개 타입 검사 통과, 로컬 DB 새 결제/한도 및 금융 RLS 계약 통과(전체 롤백).
- Android release 빌드, jarsigner, ZIP 무결성, 매니페스트와 빌드 출처 해시 확인.
- 기존 v62에서도 기록된 CupertinoIcons 글꼴 경고가 남아 있습니다. 실제 단말의 시각 검증은 별도입니다.
- v62 업로드 서명 인증서와 일치. 디버그·앱 백업 비활성, 주소록·마이크 권한 없음, 공유 Provider 비공개. 한글 PDF 글꼴/OFL 라이선스 일치 및 Gemini 비밀키 미포함 확인.
- 빌드 로그: `.artifacts/v63-build.log`. 로컬 기능 검증 로그: `.artifacts/launch-deno.log`, `.artifacts/launch-deno-check.log`, `.artifacts/launch-billing-db.log`.

## AAB

- [recipe-scout-v63.aab](../release/recipe-scout-v63.aab)
- `com.kyoutube.app` / **1.0.1+63** / `production`.
- 크기 **72,517,732 bytes** (69.2 MiB).
- SHA-256: `693E481C9A836D2325A27F163A51F5CCF4F50B1F8012AF562117B1EED123F3DA`.
- [검증 기록](../release/verify-v63.json), [빌드 출처](../release/recipe-scout-v63.aab.provenance.json).
- [한국어 출시 안내](../release/recipe-scout-v63-notes-ko-KR.txt), [영어 출시 안내](../release/recipe-scout-v63-notes-en-US.txt).

## 실제 결제 활성화 전 남은 작업

1. Play Console에 `recipe_scout_plus`, `recipe_scout_business`와 각 `monthly`/`annual` base plan의 가격·판매 국가를 설정합니다.
2. 현재 없는 `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, `GOOGLE_PLAY_RTDN_AUDIENCE`, `GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT_EMAIL`을 구성합니다. 키 내용은 채팅에 보내지 않습니다.
3. RTDN 테스트 수신, 상품/가격 일치 확인 후 내부 테스트의 구매를 활성화합니다. 운영 `membership_billing_offers`의 네 항목은 현재 `checkout_enabled=false`, `verified_at=null`입니다.
4. 이 AAB를 Play 내부 테스트에 올려 라이선스 테스터로 구매·대기·구독 변경·갱신·취소·복원·유예·보류·만료·환불/회수·다른 앱 계정의 복원 거부를 실기기에서 검증합니다.

Play Console 업로드, 휴대폰 설치, 실제 결제 및 RTDN 수신 검증은 이번 완료 범위에 포함되지 않습니다.
