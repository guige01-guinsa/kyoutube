# 기존 일정관리 소스와 재사용 기준

2026년 10월 10일 기준. 원본은 [guige01-guinsa/ai-schedule](https://github.com/guige01-guinsa/ai-schedule), 개발 기준은 `main`의 `19879b6aeffe7c10f4e636f26bf7075fbcbd96f3`다. 이 커밋의 개발 시각은 **2026년 10월 9일 15:36:34 한국 시간**이며 Google Calendar 동기화의 DB 오류 처리를 수정했다. GitHub에는 같은 커밋의 Vercel production 배포 성공 기록이 있다. 사용자 계정으로 로그인한 운영 기능 검사는 개발 착수 검수에 포함한다.

새 요리사 앱은 원본의 업무별 템플릿과 일정 규칙을 활용하는 독립 Flutter 앱으로 만든다. 원본의 Next.js 화면과 관리자 DB 접근 코드는 모바일로 복사하지 않는다. 원본 일정관리, 새 요리사 앱, 레시피 스카우트의 자료와 배포를 분리한다.

## 확인한 원본 구성

| 구성 | 확인된 내용 | 새 앱에 반영할 내용 |
|---|---|---|
| 기술 | Next.js 16.3.6, React 19.2.8, TypeScript, Supabase Auth·PostgreSQL | 화면은 Flutter, 순수 규칙은 Dart와 서버 TypeScript로 이식 |
| 회원 | 이메일·비밀번호, Google, 카카오; 사용자 profile과 시간대 | 기존 로그인 유지, 공동 로그인은 별도 시험 후 연결 |
| 업무 구성 | 직무 pack → 업무 module → task template; 개인별 활성화 | 첫 출시의 요리사 6개 흐름을 catalog로 제공 |
| 식당 업무 | `restaurant_buyer`에 8개 모듈·16개 업무 템플릿 | 구매·재고·납품·원가 관련 체크리스트의 기초 |
| 반복 | 근무 요일, 기본 14일 생성, 일간·주간·월간 | 첫 앱은 일간·주간; 월간은 명시적 규칙으로 후속 개발 |
| 실행 | 대기·진행·완료·미루기·취소, 실제 시간과 미룬 횟수 | 동일 개념과 건너뛰기, 불변 실행 이력 추가 |
| 개선 | 완료 기록의 최근 20개 중앙값, 시간대 선호, 겹침 검사 | 최소 표본·변화 상한·개인 승인·템플릿 버전 추가 |
| 자연어 | 한국어 날짜와 업무 키워드 규칙 | 요리 업무 사전으로 바꾸고 모호한 입력은 확인 |
| 달력 연동 | Google Calendar 별도 인증·동기화·충돌 처리 | 1.1 이후 선택 기능; 공동 로그인과 별개 |

버전 근거는 [package.json](https://github.com/guige01-guinsa/ai-schedule/blob/19879b6aeffe7c10f4e636f26bf7075fbcbd96f3/package.json), 회원 화면은 [auth-gate.tsx](https://github.com/guige01-guinsa/ai-schedule/blob/19879b6aeffe7c10f4e636f26bf7075fbcbd96f3/app/auth-gate.tsx), 직무 구성은 [템플릿 migration](https://github.com/guige01-guinsa/ai-schedule/blob/19879b6aeffe7c10f4e636f26bf7075fbcbd96f3/supabase/migrations/20261002_work_profiles_and_templates.sql)에 있다. migration에 있는 정의와 운영 DB의 적용 상태는 착수 검수에서 대조한다.

## 식당 구매 담당자 모듈 활용

| 원본 모듈 | 원본 업무 | 새 요리사 앱의 연결 |
|---|---|---|
| 발주 | 일일 발주량 검토, 품절·긴급발주 | 구매 준비, 부족 재료 대응 |
| 재고 | 주요 식재료 확인, 장기재고·폐기예정 점검 | 영업 준비, 마감 재료 확인 |
| 납품검수 | 수량·품질 검수, 거래명세서 대조 | 납품 예정 업무, 입고 확인 안내 |
| 공급업체 | 납품이슈 기록, 월간 평가 | 문제 기록과 원본 업체 자료 안내 |
| 원가·가격 | 주간 단가변동, 월간 구매원가 | 신메뉴·주간 메뉴의 원가 확인 |
| 식품안전 | 소비기한·유통기한, 냉장·냉동 보관상태 | 담당자의 확인 항목; 자동 안전 판정 없음 |
| 정산 | 주간 거래명세, 월말 매입정산 | 후속 월간 업무 후보 |
| 수요예측 | 예약·판매예상, 행사·성수기 구매 | 예약·행사 준비와 주간 계획 |

처음부터 16개 업무를 모두 자동 생성하지 않는다. 최초 6개 흐름·30개 업무의 해당 확인 항목에 반영하며 각 업무의 `sourceRefs`에 원본 template ID를 기록한다. 모듈 단위 추가 선택과 월간 정산은 후속 범위다. 원본의 09:00·10:00 등 고정 시각은 새 앱으로 강제 이전하지 않고 업소의 영업·납품·제공 시각으로 계산한다.

## 파일별 재사용 결정

아래 경로는 모두 위 기준 커밋의 원본 저장소 기준이다. 출처가 있는 함수와 새 제품 정책을 분리해 검수한다.

| 파일 | 재사용 방법 | 변경하거나 제외할 부분 |
|---|---|---|
| `utils/work-schedule-policy.ts` | 요일·날짜·시간대와 회차 판정의 순수 로직 이식 | 주간 선택 요일과 영업일 경계를 새 정책으로 확장 |
| `utils/work-schedule-engine.ts` | 회차 unique key와 재시도 개념 | Node·관리자 client·시설 점검 의존 제외, 원자 생성 RPC로 재작성 |
| `utils/work-templates.ts` | pack·module·template 관계와 정렬 | 게시 버전, checklist, 선행 업무와 기준 시간 추가 |
| `utils/tasks.ts` | 실행 상태와 실제 시간 미기록 구분 | 계정별 offline queue·revision·삭제 이력 별도 구현 |
| `utils/recommendation.ts` | 중앙값·수동 시간 보존·겹침 검토 | 제목 단어 매칭을 업무 key로, 06:00 시작 제약을 업소 영업시간으로 변경 |
| `utils/recommendation-store.ts`와 추천 migration | 미리보기·입력 snapshot·승인·재시도 구조 | 새 DB의 권한·previewHash·원자 적용으로 재설계 |
| `utils/korean-work-datetime.ts` | 엄격한 날짜와 한국어 날짜 해석 | 업소 시간대와 명시적 확인, 초기에는 구조화 입력 우선 |
| `utils/work-assistant.ts` | 업무 후보 점수와 사용자 선택 원칙 | 시설관리 사전 제외, 요리사 사전·목적별 가이드 연결 |
| `utils/work-assistant-engine.ts` | 사용자 선택 모듈을 기준으로 후보 제안 | 관리자 저장 코드 제외, 새 API에서 사용자 검증 |
| `utils/calendar/sync-policy.ts` | 양쪽 변경 시 충돌로 보류하는 원칙 | Google 토큰·동기화 서버와 신규 계정 저장 별도 구현 |
| `utils/calendar/database-error.ts` | 내부 자료를 숨기는 고정 오류 코드 | 일정·연동 API 공통 오류 형식에 맞춤 |
| `utils/profile.ts`, `utils/auth/*`, `proxy.ts` | 로그인과 표시 정보의 개념 참고 | 원본 세션·환경 설정·DB ID를 새 앱에 복제하지 않음 |

원본 테스트의 [일정 규칙](https://github.com/guige01-guinsa/ai-schedule/blob/19879b6aeffe7c10f4e636f26bf7075fbcbd96f3/tests/work-schedule.test.mjs), [추천](https://github.com/guige01-guinsa/ai-schedule/blob/19879b6aeffe7c10f4e636f26bf7075fbcbd96f3/tests/recommendation.test.mjs), [동기화 오류](https://github.com/guige01-guinsa/ai-schedule/blob/19879b6aeffe7c10f4e636f26bf7075fbcbd96f3/tests/calendar-sync-errors.test.mjs)를 회귀 사례로 활용한다. Dart와 서버 양쪽 구현에 적용할 설계 입력은 [policy-fixtures.v1.json](policy-fixtures.v1.json)에 둔다. 설계 자료 검증과 실제 앱 구현 테스트 통과는 구분한다.

## 원본과 달라지는 새 앱 정책

| 항목 | 원본 코드 기준 | 새 요리사 앱 결정 |
|---|---|---|
| 자동 생성 | profile에 기본 활성화, 근무일 기본 월~금 | 처음은 비활성, 영업 요일·시각 미리보기 후 사용자가 켬 |
| 주간 일정 | 해당 주 첫 근무일 | 사용자가 선택한 요일, 휴무 예외 우선 |
| 월간 일정 | 설명에 ‘월말’ 포함 여부로 첫/마지막 근무일 판단 | 1.0 제외, 이후 구조화된 monthlyRule 사용 |
| 날짜 | 시간대의 달력 날짜 | 달력 날짜와 영업일을 별도 저장; 기본 영업일 경계 04:00 |
| 시간 추천 | 06:00 이후부터 하루 안의 후보 | 새벽 준비·자정 이후 마감까지 명시한 영업 구간 안에서 계산 |
| 업무 매칭 | 제목과 단어가 겹치는 완료 기록 | 안정된 업무 key·버전 계보·작업량 구간 |
| 시간 개선 | 최근 20개 중앙값, 0분 기록도 후보 | 1~480분 유효 기록 5개 이상, 20% 상한, 사용자 승인 |
| 저장 | 업무 upsert 뒤 회차 upsert | 계획·업무·회차·멱등 결과를 한 트랜잭션으로 저장 |
| 배치 생성 | 기본 한 번에 profile 최대 100개 | cursor로 모든 대상 순회, 처리 위치와 실패 회차 보존 |
| 업무 분류 | `public`은 화면에서 ‘공적’, `personal`은 ‘개인’ | 업무 분류와 자료 공개 권한 분리; 처음은 개인 소유 비공개 |

이 차이는 원본 기능 오류를 단정하는 표가 아니다. 조리 현장·독립 모바일 제품의 요구에 맞춘 변경이며 원본 시스템에는 자동 적용하지 않는다.

## 기술과 배포 결정

새 앱은 Flutter·Riverpod·go_router·SQLite로 구현한다. 서버는 별도 Supabase의 Edge Functions와 PostgreSQL RPC를 사용한다. 순수 날짜·회차 함수는 Dart와 TypeScript 각각으로 이식하고 같은 fixture로 결과를 비교한다. Node 전용 `crypto`, `server-only`, Next.js request/response, 관리자 client를 Flutter나 Deno로 그대로 가져오지 않는다. 회차 식별은 새 DB unique 제약과 멱등 UUID로 처리한다.

새 앱의 웹은 연결 안내와 시험 범위를 먼저 제공한다. 원본 Next.js를 모바일 WebView로 감싸는 방식을 기본 제품으로 삼지 않는다. 원본 저장소의 `main` push는 Vercel 배포로 이어질 수 있으므로 새 앱 작업은 별도 저장소·CI에서 진행한다. 원본 수정은 회원 연결과 선택형 가이드에 한정한 별도 PR로 검토한다.

원본 루트에서 LICENSE 파일을 확인하지 못했으므로 사용자 소유 코드의 출처를 남기고 제3자 package·폰트·영상 자료의 이용 조건은 가져오는 항목별로 점검한다. 실제 사용자 DB, 환경 파일, 서비스 키, 기존 프로젝트 설정과 서명키는 가져오지 않는다.

## 인증과 보안 적용 기준

원본은 Supabase의 Google·카카오 로그인을 사용한다. 이 사실만으로 원본이 다른 앱에 공동 로그인을 제공하는 OIDC 서버라는 뜻은 아니다. 원본의 OAuth 서버 활성화·서명 방식·동의 화면과 레시피 스카우트의 고정 SDK 지원을 시험해야 한다. 상세 절차는 [회원 설계](MEMBERSHIP_KO.md)를 따른다.

새 서버는 profile을 읽지 못했거나 계정 상태를 확인하지 못하면 회원 연결·이용권 등록·비공개 자료 접근을 보류한다. 원본 `fallbackProfile`의 표시용 `active` 기본값을 새 서비스의 권한 판단에 사용하지 않는다. 원본의 `public` 업무 분류를 인터넷 공개 권한으로 해석하지 않는다.

관리자 DB 접근과 배치 생성은 서버에만 둔다. 사용자 요청은 검증된 서비스 세션의 사용자 ID에서 시작하며 클라이언트가 보낸 소유자 ID를 신뢰하지 않는다. 새 RPC는 사용자·workspace·업무 소유권, 계정 상태, 기대 revision, 요청 UUID와 입력 범위를 함께 검사한다. 부분 저장과 충돌을 성공으로 기록하지 않고 공개 오류에는 업무 제목·DB 원문·개인 URL을 넣지 않는다.

## 착수 검수에서 확정할 사항

1. 시험 계정으로 원본 로그인·업무 생성·완료·미루기·추천·Google Calendar 흐름을 기록하고 운영 DB와 migration을 대조한다.
2. 공동 로그인 POC를 기존·신규·유료 회원, 다른 이메일, 계정 정지·삭제, 모바일 복귀까지 시험한다.
3. 새 앱과 서버의 날짜·회차 fixture를 통과시키고 정책 변경 사례를 별도 검수한다.
4. 선택형 가이드의 실제 도착 화면·무료와 업소 권한을 확인하고 레시피 스카우트 기존 가이드와 연결한다.
5. 새 배포 대상·도구 버전·비용 경보와 운영 복구를 확인한 뒤 구현 릴리스 기준을 고정한다.

원본 일정관리의 소스 기준은 확인됐으며 회원 연결의 운영 설정과 새 앱 구현 검수는 개발 작업으로 남는다.
