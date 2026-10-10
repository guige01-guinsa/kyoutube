# 공식 채널 연결 및 안정성·보안 점검 — 2026-09-20

공식 유튜브와 블로그 연결을 Flutter 앱·웹 공통 코드에 추가했다. 최종 정적 분석과 전체 테스트는 통과했다. 운영 서버는 읽기 전용으로 점검했으며, 이번 코드의 운영 배포·Android 배포 파일 생성·DB 변경은 수행하지 않았다.

## 공식 채널 연결

- 유튜브: https://www.youtube.com/@guige01
- 블로그: https://blog.naver.com/toktoknr
- 일반 홈의 검색·영상 진입 안내 다음, 개인/공급업체 홈, 전문가 업무 홈, 내 정보/더보기, 체험 튜토리얼에 공통 `공식 사용 안내` 카드를 표시한다.
- 기존 검색·분류·메뉴를 먼저 사용할 수 있도록 배치했다. 한국어·영어 UI를 지원하며 영어 안내에는 콘텐츠가 한국어임을 표시한다.
- 사용자가 누를 때만 고정 HTTPS 주소를 외부 앱 또는 브라우저 새 탭으로 연다. 계정·세션·업무 데이터나 추적용 쿼리를 주소에 추가하지 않는다. 영상·블로그를 자동 임베드하거나 가져오지 않는다.
- 링크 실행 실패/예외에는 복사 가능한 공개 주소를 보여 준다. 플랫폼 오류 내용은 노출하지 않는다. 중복 클릭과 화면 종료 후 비동기 응답을 처리한다.
- 웹의 기존 `url_launcher_web 2.4.2` 구현은 `noopener,noreferrer`를 사용한다. 웹 팝업 차단을 항상 감지할 수 있다는 의미는 아니다.

변경: `lib/core/config/official_channels.dart`, `lib/core/widgets/official_channels_card.dart`, `lib/core/localization/ui_translations.dart`, 홈·업무·튜토리얼 화면 4개 파일. 새 패키지·권한·DB 마이그레이션은 없다. 작업 전부터 존재하던 다른 변경은 보존했다.

## 이번 실행의 검증 결과

| 검사 | 결과 | 근거 |
| --- | --- | --- |
| 고정 Flutter 3.44.8 / JDK 17 환경 점검 | bootstrap 재실행 성공 | 초기 버전 조회 실패 후 동일 SDK 직접 조회·재실행으로 정상 확인 |
| `tools/dev/verify.ps1` | 종료 코드 0, analyze 문제 없음, 테스트 **511개 통과 / 기존 4개 제외** | `.artifacts/official-channels-verify-final.log` |
| 새 링크·오류·중복 클릭·화면 종료·다국어·320px/200% 글씨 테스트 | 6개 통과, 전체 테스트에 포함 | `test/core/widgets/official_channels_card_test.dart` |
| 390px/1100px 화면 렌더링 | 2개 통과, 글씨·아이콘·버튼 시각 검토 완료 | `test/core/widgets/official_channels_preview_test.dart`, `.artifacts/official-channels-preview-*.png` |
| Deno 서버 함수 테스트 | **151개 통과** | `.artifacts/official-channels-deno.log` |
| 업무·샘플·직원 권한 DB 계약 검사 | **146개 통과**, 격리 PGlite, 운영 쓰기 0건 | `.artifacts/official-channels-staff-db.log` |
| 제휴 상품 DB 계약 검사 | **34개 통과**, 격리 PGlite | `.artifacts/official-channels-affiliate-db.log` |
| 운영 API 인증/요청 크기/공개 조회 | **8개 기대 응답 일치** | `.artifacts/official-channels-live-http.json` |
| 운영 웹 두 도메인 HTTPS·보안 헤더 | 두 도메인 모두 정상 | `.artifacts/official-channels-web-security.json` |
| 공개 취약점 데이터베이스 조회 | Pub 138개 + membership npm 그래프 10개, 일치 항목 0개 | `.artifacts/official-channels-dependencies.json` |
| 현재 소스의 비밀키 패턴 검사 | 370개 파일, 후보 0개 | `.artifacts/official-channels-source-scan.json` |

초기 전체 실행에서 새 문구 6개의 번역 목록 누락 및 카드가 기존 버튼을 밀어낸 메뉴 테스트 실패를 발견했다. 문구를 등록하고 배치를 조정한 후 전체 검증을 다시 통과했다. 기존 테스트를 제거하거나 실패 조건을 완화하지 않았다.

## 운영 보안 확인

운영 Supabase 관리 API의 설정/보안 진단 GET, `read_only: true` SELECT 및 인증 없는 HTTP 요청만 사용했다. 운영 레코드·인증 설정·함수·마이그레이션 변경은 없다. 인증 자료의 값은 출력하거나 보고서에 저장하지 않았다.

- 점검한 public 테이블 중 RLS 비활성 테이블 0개, 공개 Storage 버킷 0개.
- public SECURITY DEFINER 함수 중 익명 실행 허용 0개, 고정 search_path 누락 0개. anon/authenticated의 public 스키마 CREATE 권한 없음.
- 관리자 함수 26개에서 관리자 역할 및 MFA를 요구하는 공통 검사 함수 호출을 확인했다. 24개는 `assert_admin_mfa`, 제휴 관리 2개는 역할/MFA를 별도로 확인하는 `assert_supplier_directory_admin`를 호출한다. 이는 정의 확인이며 실제 관리자 로그인 성공을 검증한 것은 아니다.
- 이메일 확인, 이메일 변경 보호, 비밀번호 변경 재인증, refresh token 회전, TOTP 등록/검증이 활성화되어 있다. 익명 회원가입은 비활성화다.
- 인증 없는 개인 레시피·탈퇴·회원·YouTube 기능 요청은 401, 제한을 넘는 요청 본문은 413, 인증 health 및 공개 레시피 조회는 200이었다. 실제 탈퇴·구매·AI 생성 요청은 수행하지 않았다.
- Firebase 두 호스트에서 CSP, nosniff, iframe 차단, referrer/permissions 정책, COOP, 캐시 정책을 확인했다. HSTS 실제 값은 `max-age=31556926; includeSubDomains; preload`로 설정 파일의 1년 기준보다 강하다. 최초 단순 문자열 비교의 불일치를 값의 의미로 재검증했다.
- 현재 마지막 DB 마이그레이션은 0065다. 0064는 기존 배포 기록상 미적용이므로 번호가 작다는 이유로 적용되었다고 간주하지 않는다. 이번 격리 직원 계약 검사가 운영 0064 적용을 의미하지 않는다.

## 남은 항목과 우선순위

1. **유출된 비밀번호 차단이 꺼져 있다.** 현재 `password_hibp_enabled=false`이며 운영 보안 진단도 경고한다. 요금제/기능 사용 가능 여부를 확인한 뒤 운영 설정으로 활성화하고 결과를 재검증해야 한다. 이번 점검에서 인증 정책이나 요금제를 변경하지 않았다.
2. **관리자 인증 복구를 실제로 확인해야 한다.** 검증 완료된 관리자 MFA 등록이 1개 있으나, 사용자가 앞서 6자리 코드를 찾지 못했다고 했으므로 등록 유무만으로 접근 가능하다고 결론 내릴 수 없다. 본인 인증 앱 확인 또는 본인 확인을 거친 공식 복구가 필요하며, MFA를 우회·삭제하지 않았다.
3. **보안 진단의 추가 검토 항목:** `pg_net`의 public 확장 배치 1건, authenticated가 호출 가능한 SECURITY DEFINER 함수 83건, RLS는 켜져 있지만 정책이 없는 테이블 31건. 정책 없는 테이블은 기본 거부 상태이며 RPC를 통한 내부 접근 목적일 수 있다. 이 수치만으로 외부 유출이라고 판단하지 않는다. 업무/제휴 계약 검사를 통과했지만 모든 함수의 모든 인가 분기를 수동 검토한 것은 아니다. 확장 이전이나 권한 일괄 삭제는 수행하지 않았다.
4. **개발 환경 경고:** PATH는 별도 전역 Flutter를 가리키지만 모든 검증은 고정 SDK 경로로 수행했다. Android SDK 라이선스 상태 확인 불가와 Windows Visual Studio 불완전 설치 경고가 남았다. Android 빌드 전에 라이선스 상태를 확인해야 한다. Windows 데스크톱 빌드는 이번 범위가 아니다.

## 점검 범위의 한계

- 운영 웹은 기존 배포본을 점검했다. 새 공식 채널 버튼은 로컬 코드와 위젯 렌더링으로 검증했으며, 배포 후 브라우저·실기기에서 다시 확인해야 한다.
- Docker 데몬이 실행되지 않아 전체 로컬 Supabase 스택 재현 대신 격리 PGlite 계약 검사와 서버 함수 테스트를 사용했다.
- 부하/장시간 장애 주입, 실사용자 계정의 모든 동작, 실제 결제·AI 비용 발생·FCM 수신, Android 설치 검증은 수행하지 않았다.
- 최근 백업 복구 성공은 별도 `docs/release-v76.md`의 이전 실행 기록이다. 이번에 새 백업이나 복원 훈련을 수행한 것은 아니다.
- 의존성 검사는 현재 Pub lockfile 및 membership npm 그래프에 한정된다. Gradle·운영체제·다른 모든 원격 의존성이나 알려지지 않은 취약점까지 보증하지 않는다. 비밀키 검사는 선택한 현재 소스의 패턴 검사이며 Git 전체 이력/바이너리를 포함하지 않는다.

다음 단계는 승인 후 운영 웹 빌드·배포 및 실제 링크 열기 확인이다. 저장소 `AGENTS.md`는 release build와 deployment에 명시적 승인을 요구하므로 이 보고서 작성 시점에는 배포하지 않았다.
