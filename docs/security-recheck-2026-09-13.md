# 보안 재점검 및 추가 보강 — 2026-09-13

기존 개인정보·유료 권한 보강 이후 사용자가 요청한 추가 점검이다. 실제 운영 설정, 보안 Advisor, 소스와 로컬 회귀 테스트를 함께 확인했다. 점검하지 않은 범위까지 안전하다고 보증하거나 임의의 보안 점수를 부여하지 않는다.

**결과:** 요청·로그·의존성 보강 함수 8개와 운영 비밀번호 정책을 반영했고 DB 직접 연결의 TLS를 강제했다. 실제 API와 관리 연결은 정상이다. 관리자 MFA 등록, 외부 복구, Google 서버 인증은 남아 있다.

## 확인한 보호 상태

- 운영 public 업무 테이블의 RLS 비활성 항목 0개, 공개 Storage 버킷 0개.
- public SECURITY DEFINER 함수 중 익명 EXECUTE 허용 0개, 고정 search_path 누락 0개. 일반 사용자는 public 스키마에 객체를 만들 수 없다.
- 유일한 공개 뷰 `ai_usage_monthly_guardrails`는 `security_invoker=true`이다.
- 이메일 확인, 안전한 이메일 변경, 비밀번호 변경 시 재인증, 갱신 토큰 회전이 활성화되어 있다. 익명 회원 가입은 비활성화되어 있다.
- 앞선 인증 포함 암호화 백업은 66개 테이블 2,907개 행 복원 일치 검증을 완료했다. 현재 Windows 계정 DPAPI 종속성은 유지된다.

## 이번 수정

1. 운영 최소 비밀번호 길이 6자를 8자로 올리고 영문+숫자를 필수화했다. 이미 앱이 요구하는 기준과 맞췄다. 기존 비밀번호·세션은 교체하지 않았다.
2. 공통 API 처리에 512 KiB 요청 본문 제한과 10초 본문 수신 제한, URL 8,192자 제한을 추가했다. Content-Length 누락·허위 값도 실제 스트림 바이트 수로 검사한다. 한도를 넘기면 실제 처리기/AI 호출 전에 거절한다. 본문 수신 시간과 AI 생성 시간은 별개다. 이미지 업로드는 별도 Storage 경로이므로 이 JSON API 제한 대상이 아니다.
3. 공통 API 응답에 `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`를 넣었다. 개인 레시피·회원 상태·서명 URL의 공유 HTTP 캐시 저장을 차단한다.
4. 회원 탈퇴·YouTube 검색 실패 로그에서 DB/외부 오류 원문을 제거했다. 사용자/DB 값이 들어올 수 있는 오류 문구 대신 고정 분류만 기록한다. 탈퇴 기능에 익명 사용자 차단을 명시했다.
5. 탈퇴·검색 인증·영상 초안 후처리의 Supabase 호출에도 15초 전송 제한을 적용했다. 쓰기를 자동 재시도하지 않는다.
6. 서버 Supabase SDK를 실제 해석하고 검사한 `2.112.3`으로 고정하고 초안 함수의 별도 구버전 ESM import를 통일했다. 모든 하위 의존성을 lockfile로 고정한 것과 같지는 않다.
7. Google 결제 인증 토큰을 공식 Google 토큰 주소로만 보내도록 고정하고 다른 token_uri 설정을 거절한다.

## 검증

- 고정 Flutter 3.44.8: analyze 지적 없음, 테스트 220개 통과, 선택 캡처 4개 생략.
- Deno 서버 테스트 69개 통과. 크기 제한 우회·늦은 본문·요청 취소·UTF-8 유지·경계값·CORS/캐시 보호를 포함한다. 함수 진입점 8개 타입 검사 통과.
- 로컬 DB 권한 계약 시험 통과. 개인정보 소유권, 무료/유료/만료 권한, 관리자 MFA 및 권한 우회를 검증하고 트랜잭션 롤백.
- OSV에 Dart 106개와 npm 11개 버전을 조회한 결과 등록된 취약점 결과 없음. 직접 고정한 SDK의 npm 그래프를 포함한다. 구버전 ESM SDK는 이번에 제거했다.
- 소스·도구·문서 347개 파일에서 검사한 비밀키 패턴 후보 없음. 값은 출력하지 않았다. 모든 비밀 형식이나 전체 Git 이력의 검사 결과는 아니다.
- Flutter doctor의 기존 전역 SDK PATH, Android 라이선스 확인, Windows Visual Studio 구성 경고는 남아 있다. 이번 분석/테스트는 고정 SDK·JDK 17로 통과했다.

## 남은 우선순위

| 우선순위 | 항목 | 현재 상태와 다음 조치 |
| --- | --- | --- |
| 높음 | 관리자 MFA | 실제 등록 팩터 0개. 관리자가 v59의 인증 앱 등록을 마친 뒤 준비된 0047·0048 적용. 등록 전 강제해서 유일한 관리자 접근을 차단하지 않는다. Supabase/Google 콘솔 계정 자체 MFA도 앱 MFA와 별개로 확인 필요 |
| 높음 | 앱 보안 수정 배포 | 휴대폰은 Play 설치 v58. v59는 Play 테스트 트랙을 통한 업데이트 필요. 이번 추가 변경은 서버 중심이며 기존 v59 AAB를 덮어쓰지 않음 |
| 높음 | 외부 백업·독립 키 복구 | 로컬 암호화 백업은 검증됐지만 PC/Windows 계정 동시 손실을 보호하지 못함. 공급자 백업 또는 별도 키 관리의 외부 보관 필요 |
| 높음 | 결제/관리자 푸시 | Google 서버 인증 연결과 실제 구매·푸시 시험 필요. 결제 갱신/환불 RTDN·재검증은 별도 구현 과제 |
| 중간 | 유출 비밀번호 차단 | 현 플랜에서 설정 API가 402로 거절됐던 항목. 지원 플랜 선택 필요. 이번 작업은 유료 플랜을 구매하지 않음 |
| 중간 | 대규모 공격·호출 비용 | 이번 크기/시간 제한은 전체 DDoS나 분산 요청 폭주 방어를 대신하지 않음. 외부 관문 제한, 계정별 요청 예산, CAPTCHA는 실제 가입/검색 UX와 함께 설계 필요 |
| 중간 | 지속 검증 | 자동 의존성 점검, 함수별 lockfile, 전체 Git 이력 비밀 검사, 정기 외부 복원 훈련·침투 테스트 보강 필요 |

보안 Advisor의 SECURITY DEFINER 호출 가능 경고는 로그인 사용자용 RPC에서 남을 수 있다. 역할/소유권 검사를 통과해야 실제 기능을 수행하므로, 경고 숫자만 줄이려고 정상 API를 일괄 차단하지 않았다. RLS가 활성이고 정책이 없는 내부 운영/과금 테이블은 기본 거부 설계다. public의 pg_net 확장은 호출 경로와 이전 호환성을 별도로 검토할 항목이다.

기준 문서: [Supabase 운영 체크리스트](https://supabase.com/docs/guides/deployment/going-into-prod), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [인증 설정 API](https://supabase.com/docs/reference/api/v1-update-auth-service-config), [DB TLS 강제](https://supabase.com/docs/guides/platform/ssl-enforcement).

증거: `.artifacts/security-current-audit.json`, `security-password-policy-applied.json`, `security-recheck-deno.log`, `security-recheck-deno-check.log`, `security-recheck-flutter.log`, `security-recheck-sql.log`, `security-recheck-dependencies.json`, `security-recheck-source-scan.json`. 최종 운영 배포·TLS·HTTP 결과는 아래에 기록한다.

## 최종 운영 결과

- 함수 8개 배포 완료. 실제 배포 소스를 다시 내려받아 변경 진입점·공통 파일 12개의 SHA-256 일치를 확인했다. JWT 검증 설정은 이전과 동일하다.
- 배포 버전: recipe_api v50, youtube_search v35, ai_recipe_assistant v27, delete-account v20, youtube_recipe_context v27, ai_youtube_recipe_assistant v29, membership v5, operations_monitor v2.
- 배포 전 소스 백업: `C:\Users\ADMIN\K-youtube-release-v1.0.0-13\.local-backups\security-recheck-functions-20260913T050233Z`. public_recipe_sync는 변경하지 않았다.
- DB 직접 접속 TLS 강제: `database=false` → `true`, `appliedSuccessfully=true`. 짧은 DB 재시작 후 읽기 쿼리·Auth 상태·공개 레시피 정상 응답을 확인했다. 기존 CLI의 `pg_stat_ssl` 조회도 `connection_uses_tls=true`였다. 정확한 서비스 중단 시간을 계측한 것은 아니다.
- 운영 HTTP: 개인 레시피·회원 탈퇴·회원·영상 정보·검색 익명 요청 401, 512 KiB 초과 요청 413, Auth 상태/공개 레시피 200. 함수 응답의 no-store 및 nosniff 확인. 별도 검사에서 AI 2개와 유료 RPC도 익명 요청 401, 익명 개인 레시피 SELECT는 빈 결과였다. 실제 회원 탈퇴·결제·유료 AI 생성은 시험하지 않았다.
- 기존 앱 소스·서명 AAB는 이번 작업에서 변경하지 않았다. 서버/인증 정책 수정은 현재 운영에 반영되었다. v59 앱 배포 및 관리자 인증 앱 등록이 필요하다는 기존 제한은 남는다.
- 추가 증거: `.artifacts/security-recheck-deployment.json`, `security-recheck-ssl.json`, `security-recheck-db-tls.log`, `security-recheck-http.json`, `security-recheck-private-api.json`.
