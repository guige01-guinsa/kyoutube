# 출시 전 새 요금제 적용

2026-09-13. 사용자가 앱이 아직 출시 전이며 기존 가격·권한 보존이 필요 없다고 확인했습니다.
따라서 이전 회원을 분리해 보호하는 전환 정책을 폐기하고 다음 하나의 정책으로 정리합니다.
**2026-09-14: DB 0054·0055·0056과 함수 3개의 운영 배포, v63 서명 AAB 생성·검증을 완료했습니다.** [배포 기록](release-v63.md). Google Play 상품·서비스 계정·RTDN 설정과 실제 결제 검증은 남아 있어 결제는 비활성 상태입니다.

| 기능 | Scout 무료 | Recipe Plus | Chef Business |
|---|---:|---:|---:|
| 월간 / 연간 가격 기준 | 무료 | 9,900원 / 99,000원 | 19,000원 / 189,000원 |
| AI 초안 일 / 주 / 월 | 1 / 5 / 10 | 5 / 25 / 50 | 10 / 50 / 100 |
| 영상 분석 / 월 | 0 | 5 | 20 |
| 구매처 | 3 | 30 | 200 |
| 새 요청서 / 월 | 3 | 30 | 별도 월 제한 없음 |
| 요청서 텍스트 공유 | 제공 | 제공 | 제공 |
| 요청서 PDF 공유 | 제외 | 제공 | 제공 |
| 원가·판매가·매출 | 제외 | 제외 | 제공 |
| 레시피·장보기·인분·버전 | 제공 | 제공 | 제공 |

같은 등급은 월간·연간의 월 사용 한도가 같습니다. 연간 가격은 1년치 선결제 금액이며
결제 화면의 확정 가격은 Google Play가 반환한 현지 통화 가격을 사용합니다.
모든 영상은 최대 20분. 영상 분석을 시작하면 영상 횟수가 차감되고 초안 생성 성공 시 AI 횟수도 차감됩니다.
AI 일·주·월과 요청서·영상 월 경계는 기존과 같은 Asia/Seoul 기준입니다.
요청서 월 무제한은 총 저장 상한 1,000건을 없애는 뜻이 아닙니다.
요청서를 삭제해도 해당 월 생성 기록은 유지합니다. 기존 자료를 삭제하거나 수량·재고를 자동 변경하지 않습니다.
구독 만료 후 금융 자료는 보관하며 Business를 다시 이용할 때 접근할 수 있습니다.

## 구현

- DB 0054: 기능 프로필 기초. 파일은 변경하지 않았습니다.
- DB 0055: 새 4개 유료 플랜, 무료 기능 전환, 이전 유료 플랜 비활성화,
  AI·영상·구매처·요청서 한도, PDF 권한, 서버 결제 카탈로그.
  이전 테스트 회원 행·토큰·감사 이력은 남지만 이전 플랜에 유료 권한을 부여하지 않습니다.
- DB 0056: 서버 전용 토큰 해시 소유권 기록, 연결된 이전 토큰 폐기,
  검증 순번, 원자적인 회원 권한·이벤트 저장.
- membership 함수: Google subscriptionsv2 응답과 로그인 계정의 귀속 검증,
  productId + basePlanId 대조, 저장 후 구매 확정, 실패 시 재시도.
- membership_notifications 함수: Google OIDC 서명·발급자·대상·만료·서비스 계정 이메일 검증 후
  Play API로 현재 상태를 재조회합니다. 알림 본문의 상태·시간만으로 권한을 주지 않습니다.
  중복 조회는 같은 회원 이벤트를 다시 만들지 않습니다. 적용에 실패하면 503으로 재시도합니다.
- ai_youtube_video_assistant 함수와 공통 예약: 기존 월간 프리미엄 조건을 Plus/Business 권한으로 교체.
- Flutter: 월간/연간 선택, 정확한 base plan 선택, 실제 Play 가격, 복원, Play 관리·해지 링크,
  결제 직전 서버 상태 재확인. 기존 구독 변경은 DEFERRED로 다음 결제일에 적용합니다.
  Play의 이전 토큰을 찾고 서버 검증을 통과해야 변경을 시작하며 독립적인 두 번째 구매로 대신하지 않습니다.
- 예전 서버에서 권한 조회 RPC가 없을 때 이전 권한으로 우회하는 호환 코드는 제거했습니다.
  운영 전환은 DB·함수·새 앱을 한 묶음으로 내부 테스트해야 합니다.
- 출시 기준은 기본 요금제이며 할인 행사는 비활성입니다. 관리자 할인 데이터 편집과
  실제 할인 offer의 판매·가격 단계 안내는 별개입니다. 이번 화면은 기본 요금제만 판매합니다.

## Google Play에 만들 상품

아래 ID는 새로 등록할 **지정 ID**입니다. 실제로 등록되었다고 확인한 값이 아닙니다.
동일 ID가 이미 존재하면 내용부터 확인하고 설정을 일치시켜야 합니다.

| Product ID | Base plan ID | DB plan | 한국 기준 금액 |
|---|---|---|---:|
| recipe_scout_plus | monthly | plus_monthly | 월 9,900원 |
| recipe_scout_plus | annual | plus_annual | 연 99,000원 |
| recipe_scout_business | monthly | business_monthly | 월 19,000원 |
| recipe_scout_business | annual | business_annual | 연 189,000원 |

패키지는 `com.kyoutube.app`입니다. 모든 base plan은 자동 갱신 구독입니다.
이번 출시 구성은 무료 체험·소개 할인·할부·추가 상품 묶음을 포함하지 않습니다.
Play Console의 판매 국가별 가격과 세금 표시를 확인해야 합니다.
상품이 보이지 않거나 서버 checkout_enabled가 false이면 앱 결제 버튼이 비활성화됩니다.
제품 등록 사실과 가격을 확인하기 전에는 verified_at 및 checkout_enabled를 설정하지 않습니다.

## 실제 결제 검증을 위한 남은 설정

읽기 전용 운영 확인 결과 다음 세 서버 설정은 아직 없었습니다. 비밀값은 조회하거나 출력하지 않았습니다.

1. `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`: Android Publisher API를 사용하고,
   Play Console에서 해당 앱 구매·구독 관리에 필요한 권한을 가진 서비스 계정.
   사용자가 JSON을 보관했다면 파일 경로만 받습니다. 키 내용은 채팅·로그·커밋에 넣지 않습니다.
2. `GOOGLE_PLAY_RTDN_AUDIENCE`: 인증된 Pub/Sub push 구독의 정확한 대상 audience.
3. `GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT_EMAIL`: push 인증에 사용하는 서비스 계정 이메일.

새 함수 URL은 프로젝트의 `/functions/v1/membership_notifications`입니다.
Pub/Sub topic에 Google Play 알림 발행 권한을 주고, authenticated push subscription을 연결합니다.
Google의 Pub/Sub 서비스 에이전트가 지정 push 서비스 계정의 OIDC 토큰을 발급할 수 있어야 합니다.
Console의 RTDN 테스트 알림에서 204 수신을 확인합니다. 실패 재시도와 dead-letter topic을 구성하고
대기 메시지·최종 503 오류를 관리자 모니터링 대상으로 설정합니다.

## 운영 반영 및 결제 개시 순서

1. **완료:** 사용자 승인, 암호화 백업/복원 검증, DB 0054·0055·0056 운영 적용. 0047·0048은 적용하지 않았습니다.
2. **완료:** membership, membership_notifications, ai_youtube_video_assistant 배포와 전체 소스/인증 설정 검증. Play용 비밀값은 아직 없습니다.
3. **완료:** v63 서명 AAB 생성, 정적 분석·테스트·서명·무결성 확인.
4. **남음:** Console의 상품/base plan, 가격·국가, 서비스 계정 및 authenticated RTDN push를 구성하고 알림 테스트를 확인합니다.
5. **남음:** 상품과 실제 반환 가격 대조 후 내부 테스트용 카탈로그의 checkout_enabled를 활성화하고 v63을 Play 내부 테스트로 배포합니다.
6. **남음:** 라이선스 테스터로 네 base plan의 신규 구매, 대기, 취소, 복원, 다음 결제일 변경, 갱신, 유예, 보류, 만료, 환불·회수 및 타 앱 계정 복원 거부를 실기기에서 확인합니다.
7. Play 상태·서버 권한·앱 표시·AI/구매 한도를 대조한 후 공개 출시합니다.

## 검증 방법과 한계

- `tools/test/run_launch_billing_contract.ps1`: 정확히 로컬 Docker DB만 대상으로
  0036–0056를 한 트랜잭션 안에 적용해 새 계약을 실행하고 모두 ROLLBACK합니다.
- Deno: Google 응답 모의 테스트, HTTP 인증 경계, 실제 테스트 키로 서명한 OIDC JWT 검증,
  영상 분석 권한 테스트. 유료 Google/AI 호출은 포함하지 않습니다.
- Flutter: base plan 매칭, 미등록/비활성 상품 차단, 회원 조회 실패 시 결제 차단,
  한영/좁은 화면의 영상 권한, 전체 정적 분석·회귀 테스트.

로컬 테스트는 실제 상품 활성화·결제수단·Play 서명 배포·Google 권한 설정을 대신하지 못합니다.
서명 키와 Firebase/Supabase 프로젝트는 유지했습니다. 앱 버전은 1.0.1+63이며 승인된 운영 DB 정책과 함수가 반영됐습니다.

### 기능 검증 결과 — 2026-09-14

- 고정 Flutter 3.44.8 정적 분석: 지적 0건.
- 전체 Flutter: **293개 통과, 기존 선택형 4개 건너뜀**.
- Deno 결제·알림 인증·영상 분석: **51개 통과**, 세 함수 엔트리포인트 타입 검사 통과.
- 로컬 DB: 새 정책·사용 한도·토큰 귀속·중복/역순 방어 계약과 실제 금융 RLS 계약 통과, 전체 롤백.
- Google Play 구독 센터 재가입의 과거 계정 정보와 구매 확정 후 사라지는 context도 처리합니다.
  Google 응답 또는 서버에 이미 등록된 토큰 소유권으로만 계정을 찾습니다.
- 한영 결제 화면, 연간 선택, 320px/200% 글자 검증 및 실제 Flutter 렌더 이미지 확인.
- 변경 파일 공백 검사 통과. **1.0.1+63 서명 AAB** 생성과 기존 v62 업로드 인증서 일치 검증을 완료했습니다.

로그: `.artifacts/launch-final-validation.log`, `.artifacts/launch-deno.log`,
`.artifacts/launch-deno-check.log`, `.artifacts/launch-billing-db.log`.
화면 예시(테스트 상품 가격): [한국어](../.artifacts/launch-billing-preview/billing-ko.png),
[영어](../.artifacts/launch-billing-preview/billing-en.png).
초기 회귀 검사에서 새 번역 항목과 셰프 안내 문구에 맞지 않는 기존 테스트 기대값을 수정한 후
전체 정적 분석·테스트를 다시 실행했습니다.

공식 근거: [구독 변경과 DEFERRED의 두 line item 처리](https://developer.android.com/google/play/billing/subscriptions),
[구독 수명주기 및 구매 확정](https://developer.android.com/google/play/billing/lifecycle/subscriptions),
[인증된 Pub/Sub push](https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions).
