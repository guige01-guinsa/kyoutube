# 출시 전 전문 사용자 모집 — 로컬 구현

2026-09-14. 대상은 **전문 요리사·식당 운영자**. 현재 운영 앱은 v63이며, 아래 DB 0057·함수 2개·모집 페이지·예약 작업은 아직 운영에 적용하지 않았다. 새 AAB도 만들지 않았다.

## 구현한 흐름

1. YouTube / 카카오 공개 채널에 운영자가 실무 콘텐츠와 채널별 링크를 게시한다.
2. 방문자는 한영 모집 페이지에서 이메일 없이 인분·수율·원가 가산 판매가를 계산한다. 계산값은 저장·전송하지 않는다.
3. 안내 신청 시 이메일, 직무, 관심 기능, 언어, 허용한 유입 채널·캠페인과 동의를 기록한다. 실무 팁·프로모션은 별도 선택 동의이다.
4. CAPTCHA 확인 후 확인 이메일을 대기열에 넣는다. 이메일 링크를 연 다음 확인 버튼을 눌러야 신청 확인이 완료된다.
5. 확인 완료 안내를 보내고, 선택 동의자에게만 **확인 3일 뒤 실무 팁 1회**를 보낸다. 계속되는 뉴스레터나 출시 일괄 발송은 구현 범위에 포함되지 않는다.
6. 앱 관리자 운영 화면에서 확인된 신청자·최근 7일 확인·유입 채널·대기/실패 건수를 조회한다. 일반 사용자에게 신청자 목록을 공개하지 않는다.

외부 채널 게시, 카카오 메시지 발송, 실제 베타 초대 및 출시 공지는 자동 실행하지 않는다. 날짜·참여 조건·설치 링크를 확정한 뒤 후속 캠페인을 구현하고 발송 승인을 받아야 한다. 모집 시스템이 실제 설치·유료 전환·신규 사용자를 보장하지 않는다.

## 화면과 파일

- `playstore-site/index.html`, `prelaunch.css`, `prelaunch.js`: 기존 공개 사이트의 모집 홈. 앱 개인정보처리방침·계정 삭제 경로는 유지.
- `playstore-site/prelaunch-domain.js`: 원가 계산, 안전한 유입/공유 링크 생성.
- `playstore-site/growth-config.js`: 공개 설정만 보관. `enabled:false`, `privacyReady:false`가 기본.
- `supabase/migrations/0057_prelaunch_growth.sql`: 비공개 신청자·메일 대기열·발송 상한·관리자 집계.
- `supabase/functions/prelaunch_growth/`: 공개 접수/확인/철회. JWT 없이 동작하되 CAPTCHA·서명 토큰·입력 제한 적용.
- `supabase/functions/prelaunch_delivery/`: 전용 인증값으로만 실행하는 예약 발송자.
- `tools/ops/schedule-prelaunch-delivery.sql`: 승인 후 적용할 5분 예약 SQL. 아직 실행하지 않음.
- `tools/growth/build_content_kit.py`: 14일치 게시 초안과 고유 캠페인 링크를 Markdown/JSON으로 생성. 네트워크 접근·게시 기능 없음.

## YouTube와 카카오 설정

YouTube는 사용자가 제공한 **https://www.youtube.com/@guige01**을 연결했다. 채널 소유권이나 구독자 수는 검증하지 않았다.

사진의 카카오계정 화면은 개인 로그인 정보이다. 모집 페이지에 필요한 것은 **카카오톡 채널 공개 URL (`https://pf.kakao.com/...`)**이다. 개인 계정 이메일·전화번호·생년월일을 모집 설정에 옮기지 않는다.

- [카카오 공식 채널 만들기](https://kakaobusiness.gitbook.io/main/channel/start)
- [카카오 공식 채널 홍보/공유 안내](https://kakaobusiness.gitbook.io/main/partner/smb/channel/friend/1)

사용자가 채널 정보 화면과 함께 제공한 **‘레시피스카우트’ 공개 URL `https://pf.kakao.com/_TgJrX`**를 `growth-config.js`의 `kakaoUrl`에 반영했다. 관리자 화면에는 ‘채널 공개’가 켜져 있다. 모집 페이지에 한영 카카오 버튼을 표시하고 공개용 ZIP·홍보 초안의 채널 주소도 갱신했다. 실제 외부 공개 페이지의 응답은 웹 조회 도구에서 확인하지 못했으므로 관리자 화면의 공개 설정과 모집 버튼 연결 확인을 구분한다.

## 공개 전 필요한 설정

사용자는 기존 홈페이지/도메인이 없다고 확인했다. 우선 **Cloudflare Pages Free의 `pages.dev` 주소**를 권장한다. 정적 모집 페이지를 위한 별도 서버나 도메인 구매 없이 시작할 수 있다. 실제 프로젝트명·주소는 계정에서 생성한 뒤 확정하며, 특정 주소가 확보됐다고 표시하지 않는다. [공식 Free 요금표](https://pages.cloudflare.com/), [ZIP 직접 업로드 안내](https://developers.cloudflare.com/pages/get-started/direct-upload/).

검토용 업로드 ZIP은 `.artifacts/recipe-scout-prelaunch-site.zip`에 준비한다. 공개 정적 파일만 포함하며 비밀 설정·DB·앱 소스는 포함하지 않는다. Cloudflare 계정에서 Workers & Pages → Create application → Drag and drop으로 올릴 수 있지만 **현재 업로드·공개하지 않았다**. Direct Upload 방식은 나중에 Git 자동 연동으로 전환하려면 별도 프로젝트가 필요하다.

`pages.dev`는 홈페이지 주소이다. 자동 이메일 발신에 쓰는 도메인은 별도로 소유·DNS 인증해야 한다. 현재 선택한 Resend는 소유 도메인의 SPF/DKIM을 인증하는 방식이므로, 개인 Gmail/Naver 주소나 Cloudflare의 공용 도메인을 임의 발신자로 사용할 수 없다. [Resend 공식 도메인 안내](https://resend.com/docs/dashboard/domains/introduction). 발신 도메인을 마련하기 전에도 접수를 꺼 둔 원가 체험·유튜브 안내 홈페이지는 공개할 수 있다. 도메인을 구매하거나 유료 요금제를 신청하지 않았다.

공개할 HTTPS 모집 주소와 발신 도메인을 먼저 확정한다. 다음 값은 해당 서비스의 안전한 설정 화면/무시되는 로컬 파일로 관리하고 채팅·소스·로그에 비밀 값을 남기지 않는다.

| 서버 설정 이름 | 용도 |
| --- | --- |
| `GROWTH_SITE_URL` | 실제 모집 페이지 HTTPS URL. 쿼리·해시·사용자 정보 없음. 끝 경로까지 이메일 링크와 일치 |
| `GROWTH_TOKEN_KEY` | 무작위 32자 이상 서명용 비밀 값. 확인/철회·중복 방지에 사용 |
| `GROWTH_WORKER_SECRET` | 별도의 무작위 32자 이상 예약 호출 비밀 값 |
| `GROWTH_TURNSTILE_SECRET` | 실제 모집 도메인을 허용한 Cloudflare Turnstile 서버 키 |
| `GROWTH_RESEND_API_KEY` | 검증된 발신 도메인을 사용할 Resend 발송 키 |
| `GROWTH_FROM_EMAIL` | 검증된 도메인의 발신 이메일 주소 |
| `GROWTH_SENDER_NOTICE` | 실제 운영자/발신자 명칭과 연락처. 임의 명칭이나 개인정보를 추정하지 않음 |
| `GROWTH_PRIVACY_READY` | 실제 개인정보 안내 반영 완료 시에만 `true` |
| `GROWTH_DELIVERY_ENABLED` | 승인된 실제 발송 시작 시에만 `true` |

기존 Supabase URL/service role은 서버에서만 사용한다. 프런트 설정에는 접수 함수 URL(`endpoint`), 공개 Turnstile site key, 공개 채널 주소만 넣는다. 서비스 키나 발신 키를 넣지 않는다.

프런트의 `enabled`·`privacyReady`, 서버의 설정, DB `growth_controls`의 `intake_enabled`·`delivery_enabled`가 모두 준비돼야 접수가 열린다. 설정 전 신청을 받아 놓고 확인 메일을 보낸 것으로 표시하지 않는다. 스케줄·발신 도메인의 실제 작동 여부는 설정 존재만으로 보장되지 않아 운영 전 수신 테스트가 필요하다.

개인정보 안내는 **초안**이다. 실제 운영자, Supabase 저장 지역, Resend·Cloudflare 처리 항목/지역/위탁 또는 국외 처리 정보 등을 확인해 페이지의 한영 안내에 반영해야 한다. 지금의 “접수 전 세부사항 확정” 문장을 그대로 둔 채 `privacyReady`를 켜면 안 된다. 필요한 고지는 실제 운영 구조에 따라 검토한다. [KISA 불법스팸 안내](https://spam.kisa.or.kr/spam/main.do)를 참고한다.

## 운영 적용 순서 — 실행 전 승인 필요

1. 공개 주소·채널·도메인·제공업체 설정과 개인정보 안내를 확정한다.
2. 백업 및 적용 전 차이를 확인하고 **0057만 선택 적용**한다. 기존 미적용 0047·0048을 함께 밀어 넣는 일반 `db push`는 사용하지 않는다.
3. `prelaunch_growth`, `prelaunch_delivery` 두 함수와 정적 페이지를 비활성 상태로 배포한다.
4. Vault에 `growth_worker_url`(운영 함수 전체 URL)과 `growth_worker_secret`을 안전하게 등록한다. 예약 SQL은 이름이 같으면 갱신하며 중복 예약을 만들지 않는다.
5. 사용자 동의가 있는 운영자 소유 테스트 이메일 1개로 실제 CAPTCHA → 확인 수신 → 확인 → 철회까지 검증한다. 임의 이메일/타인 계정을 쓰지 않는다. 비용·발송 승인을 포함한 검증이다.
6. 처음에는 제한된 시간·낮은 상한으로 열고, 관리자 화면의 대기·실패·발송 제공업체 기록을 확인한 뒤 채널 링크를 공개한다. 팁 검증은 동의한 테스트 주소로만 수행한다.

긴급 정지는 DB의 접수·발송 플래그를 모두 끄거나 `GROWTH_DELIVERY_ENABLED=false`로 한다. 서버 접수는 멈추지만 유효한 철회 링크는 계속 처리한다. 정리 작업을 유지하려면 스케줄은 남겨 두고 발송만 정지한다. 이미 발송 제공업체로 넘어간 메일을 회수할 수는 없다.

## 비용·오류 제한

- 기본 최대 **하루 90회·UTC 월 2,500회 발송 시도**. 성공 건수 외에 실패·재시도도 상한을 소비한다. 5분에 작업 1개이므로 최대 12회/시간이며 확인 메일도 대기할 수 있다.
- 확인 + 완료 안내 2회, 선택 동의자는 팁 포함 3회. 실패가 없고 월 한도를 모두 쓰는 단순 상한은 약 **833~1,250명/월**이다. 동일 이메일은 새 확인 메일을 반복 발송하지 않는다.
- Resend 공개 Free 요금표는 확인 시점에 100회/일·3,000회/월이었다. 현재 상한은 여유를 둔 값이며 기존 발송량·약관·마케팅 발송 조건·요금 변경에 따라 다르다. [공식 요금표](https://resend.com/pricing), [공식 한도](https://resend.com/docs/knowledge-base/account-quotas-and-limits).
- AI API를 사용하지 않아 모집 콘텐츠 생성·원가 체험에 AI 호출 비용은 없다. 호스팅·도메인·기존 Supabase·이메일 서비스 비용은 선택 환경에 따라 추가될 수 있다. 총 운영비 0원을 보장하지 않는다.
- 글로벌 접수 방어: 유효 CAPTCHA 요청 기준 100회/시간·500회/24시간, 보관 신청자 최대 10,000명. 중복 요청도 요청 예산에 포함한다. 분산 공격으로 정상 접수가 제한될 수 있어 대규모 공개 전 호스팅 WAF/요청 제한을 검토한다.
- 공급자 24시간 멱등성 키를 사용하고 재시도는 20시간 안, 최대 5회로 제한한다. 발송 성공 여부가 모호하면 같은 작업 ID로 재시도한다. 재시도 기간 안에는 메일 템플릿·발신 설정을 바꾸지 않는다. [Resend 멱등성 안내](https://resend.com/docs/dashboard/emails/idempotency-keys).
- CAPTCHA는 서버에서 성공 여부·호스트·`prelaunch` action까지 검사한다. [Turnstile 서버 검증](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/).

## 보관·집계의 의미

서명 키를 바꾸면 기존 확인·철회 링크와 중복 방지 키가 달라진다. 키 교체 시 먼저 접수를 중지하고 기존 신청의 링크·중복 억제 이전 방안을 마련해야 한다.

미확인 신청 7일, 신청자 최대 180일 보관. 철회 시 이메일을 지우고 중복 발송 억제용 키를 포함한 나머지 신청·동의·처리 기록을 최대 30일 보관한다. 정기 정리가 이뤄져야 만료 행이 삭제된다. 백업/플랫폼 로그의 별도 보관 정책도 운영 안내에 반영한다.

관리자 숫자는 **현재 보관 중인 신청**이다. 이메일 확인은 앱 설치나 Google Play 테스트 참여가 아니다. 발송 제공업체의 요청 접수는 실제 받은편지함 도착을 보장하지 않는다. 조회수·클릭수·광고비·설치수는 수집하지 않아 클릭 전환율이나 고객 획득비용은 계산하지 않는다. 캠페인 코드는 DB에 보관하지만 현재 앱은 채널 단위 집계를 표시한다.

확장 우선순위는 ① 반송/스팸 신고 웹훅과 자동 발송 제외 ② 실패/대기 시간 관리자 경고 ③ 실제 베타 초대·출시 캠페인 ④ 개인정보를 노출하지 않는 캠페인별 집계 순이다. 현재 관리자 카드는 수동 새로고침 조회이며 실패 시 푸시를 보내는 기능은 포함하지 않는다.

Google Play 사전 등록과 이 페이지의 이메일 신청은 서로 별개다. 개발자 계정 종류·생성일에 따라 출시 전 테스트 요건이 다를 수 있다. [Google 사전 등록 안내](https://support.google.com/googleplay/android-developer/answer/9859047?hl=en), [신규 개인 개발자 계정 테스트 요건](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB).

## 홍보 초안 생성

바로 검토할 [14일 홍보 초안](prelaunch-channel-drafts.md)을 함께 준비했다. 공개 주소와 게시 시작일은 미확정이며 자리표시 링크를 그대로 게시하면 안 된다.

`tools/growth/build_content_kit.py --site <확정한 HTTPS 모집 주소> --start 2026-09-14 --out <새 출력 폴더>`

현재 채널을 포함하려면 `--kakao https://pf.kakao.com/_TgJrX`를 함께 지정한다. 실제 Python 실행 파일을 앞에 붙여 실행한다. 날짜는 첫 게시 제안일로 바꾼다. 기존 편집본을 덮어쓰지 않으며 Markdown과 JSON을 생성한다. 14일 제안은 매일 발송 지시가 아니며 반응에 따라 조정한다. 대량 카카오 메시지나 유료 광고 집행은 별도 의사결정이다.

## 로컬 검증

- Deno API/메일/브라우저 계산·링크 계약 12개 통과. 비밀 값·개인정보를 응답에 노출하지 않는 경우, 동의·CAPTCHA 실패·변조/만료 링크·철회·재시도 검증 포함.
- Docker 로컬 DB 계약 통과 후 전체 롤백: RLS/권한, 중복/동의 보존, 확인·철회, 일일 상한, 임대 토큰, 보관 정리, 일반 회원의 관리자 접근 거절.
- 브라우저 한영·모바일 검사: 인분 10 → 20 변경 시 원가 3,000 → 1,500원, 가산 판매가 4,500 → 2,250원. 수율 0 오류 표시, 375px 가로 넘침 없음, 미설정 신청 비활성.
- Flutter 전체 검증과 홍보 초안 생성기 검증 결과는 `docs/CURRENT_STATUS.md`의 이번 작업 항목 참조.
- 최종 정적 분석 0건. 전체 앱 테스트에서 294개 통과·기존 4개 건너뜀·번역 사전 누락 1개 발견. 누락 수정 후 번역/관리자 집계 5개 재검사 모두 통과. 수정 후 전체 회귀 테스트를 다시 실행한 것은 아니다.
- 홍보 초안 생성기 3개 테스트 통과. `flutter doctor`는 글로벌 PATH, Android 라이선스 상태 확인, 불완전한 Windows Visual Studio 설치에 대한 기존 경고가 있다. 이번에는 지정된 Flutter 3.44.8/JDK 17을 직접 사용했으며 Android 출시 빌드는 수행하지 않았다.
- 실제 운영 이메일, CAPTCHA 실서비스, 베타 앱 설치, 외부 채널 게시를 수행하지 않았다.
