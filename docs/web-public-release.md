# 운영 웹 배포 — 공개 정보 업체와 관리자 검색 (2026-09-16)

사용자 승인으로 DB0060과 공개 업체 20곳, `supplier_discovery` 함수 v1, 공개 정보 업체 검색/추가/검토/공개 관리 웹 화면을 순서대로 운영 적용했다. 웹 반영 2026-09-16 07:06 KST. main.dart.js SHA-256 `1bdb04f66c1af9bef093b242b40c62caca99b05ec0e8662ec2f68e747e62e6ba`. 공개 웹 9개·한영 신규 경로 로그인 보호 4개 통과. 기존 OAuth 주소·프로젝트·Android AAB는 유지한다. 관리자 로그인·2단계 인증 후 실제 유료 인터넷 검색 검증은 대기 중이다. [적용 및 검증 범위](public-supplier-directory.md) · [배포 기록](../release/verify-web-v66-public-suppliers.json).

# 공급업체 화면 보완 웹 갱신 — 2026-09-15

검색 조건 겹침 수정·기본 펼침·업체 등록 안내·로그인한 전체 무료/유료 회원 공개 안내를 운영 웹에 반영했다. main.dart.js SHA-256 `6ddac9bca7a058f7ed3766ca7577d59dca4244e1dea30e2566a42152a9623cf9`. 공개 웹 9개와 업체 경로 로그인 보호 6개 통과. 기존 Android v66 AAB와 DB/서버 함수는 유지한다. [검증·배포 상세](supplier-directory-ui.md).

# v66 웹 갱신 — 2026-09-15

업체 등록·상품 이미지·공개 카탈로그·내 거래처 연결·재료별 구매요청 초안 기능을 운영 웹에 배포했다. 버전 **1.0.1+66**, 공개 main.dart.js SHA-256 `96ac69c38a02bc193939d011737587298469f92a6fe4605914153606fa673f11`. 공개 웹 8개, OAuth 연결 4개, 업체 화면 한영 로그인 보호 6개 검사가 통과했다. 기존 인증 복귀 주소를 유지했다. [v66 통합 배포 기록](release-v66.md).

이하는 최초 v65 웹 공개 당시 기록이다.

# 공개 웹 배포 — v65 소스 기반 (2026-09-15)

웹 주소: **https://recipe-scout-workspace.web.app/**

기존 Flutter 앱의 웹 릴리스이며 기존 운영 Supabase 프로젝트를 사용한다. Firebase `korea-01` 프로젝트에 `recipe-scout-workspace` 전용 Hosting 사이트를 만들었다. 기존 기본 사이트와 Android 앱 설정은 변경하지 않았다. 새 AAB, DB 마이그레이션, Edge Function 재배포는 수행하지 않았다.

## 적용 및 검증

- 고정 Flutter 3.44.8, `--release --csp --no-source-maps --no-web-resources-cdn` 빌드.
- 정적 분석 0건, 인증·작업실 회귀 검사 25개 통과. 이전 통합 웹 전체 검사 323개 통과 기록은 [웹 작업실 문서](web-workspace.md)에 있다.
- 실제 공개 사이트 8개 검사 통과: HTTPS, 보안 헤더, 배포 파일 SHA-256 일치, 한영 PC/모바일 및 로그인 화면, 운영 Auth의 CORS/Google·Kakao 활성화 상태. 콘솔 오류·HTTP 오류 0건. 이 검사는 읽기 전용이며 회원이나 레시피를 만들거나 수정하지 않았다.
- 주소 적용 후 두 공개 도메인에서 Google·Kakao 버튼 검사 4개 통과: 실제 버튼이 전송하는 웹 복귀 주소와 PKCE, 실제 Supabase의 제공자 302 응답과 callback을 확인했다. `tools/test/web_oauth_entry.cjs`는 제공자 로그인 직전에 중단하며 계정에 로그인하거나 회원 자료를 변경하지 않는다. 결과는 `.artifacts/web-oauth-entry.json`이다.
- 실제 개인 계정의 Google/Kakao 로그인 완료와 저장 자료 확인은 별도 최종 확인 대상이다. 공개 화면 및 Auth 설정 응답 확인을 소셜 로그인 완료로 기록하지 않는다.
- 웹 배포 파일에서 privileged API key/관리자 JWT/개인키 및 앱 소스맵 미포함을 검사했다. 브라우저에 필요한 공개 Supabase 키만 포함한다.
- 배포 버전: `projects/1080683616982/sites/recipe-scout-workspace/versions/e51decaef487ddb8`.
- `main.dart.js` SHA-256: `a29265c681215ca68d139bba3887a09cec94a2904baaba0cdaac54a32e7cb642`.

로그/검증 파일은 `.artifacts/web-publish-analyze.log`, `web-publish-tests.log`, `web-production-verification.json`, `web-firebase-deploy.json`, `web-public-smoke.json`이다. 공개 배포 정보는 웹의 `/release-info.json`에서도 확인할 수 있다.

## 로그인 복귀 주소 — 운영 적용 완료

사용자가 아래 네 주소의 영구 추가를 명시적으로 승인했다. 2026-09-15 07:54 KST에 운영 Supabase 허용 목록에 추가하고 재조회하여 적용을 확인했다.

- `https://recipe-scout-workspace.web.app`
- `https://recipe-scout-workspace.web.app/`
- `https://recipe-scout-workspace.firebaseapp.com`
- `https://recipe-scout-workspace.firebaseapp.com/`

기존 기본 주소 `io.supabase.kyoutube://login-callback`과 모바일 허용 목록을 보존했다. 웹의 Google/Kakao 로그인, 이메일 확인, 비밀번호 재설정은 현재 웹 origin/path를 `redirectTo` 또는 `emailRedirectTo`로 전달한다. 현재 확인/복구 이메일 템플릿은 `.ConfirmationURL`을 사용하므로 템플릿 변경은 필요하지 않다. 기존 암호/MFA 설정도 유지됐음을 재조회로 확인했다.

`tools/ops/web_auth_urls.py --apply`로 적용했다. 결과는 `.artifacts/web-auth-urls-applied.json`의 `verified: true`, 사전 검사 결과는 `.artifacts/web-auth-urls-preflight.json`, 복구용 URL 설정만 담은 기록은 `.artifacts/web-auth-urls-before.json`이다. 비밀키나 전체 인증 설정을 저장하지 않는다. 개인 계정의 실제 로그인 완료와 기존 저장 자료 확인은 아직 검증하지 않았다.

## 재배포

```powershell
powershell -ExecutionPolicy Bypass -File tools/release/build-production-web.ps1
firebase deploy --only hosting --config firebase.web.json --project korea-01 --non-interactive
```

환경 파일 값은 출력하지 않는다. `firebase.web.json`의 public 경로는 `build/web-production`만 가리킨다. 실제 배포 직후 `node tools/test/web_public_smoke.cjs`로 읽기 전용 검사를 실행한다(Playwright와 Edge 필요). 원래 Android AAB 빌드/서명 절차와 분리되어 있다.

인증 복귀 주소 적용 후에는 `node tools/test/web_oauth_entry.cjs`로 두 도메인의 Google·Kakao 연결을 확인한다. 개인 계정 최종 확인은 공개 주소에서 앱과 같은 로그인 방식/계정으로 로그인 → 내 레시피 확인 → 저장된 셰프 작업/장보기 확인 순서로 진행한다. 이 계정 확인은 자동 검사 결과에 포함하지 않는다.

## 호스팅·보안·비용

새 서버나 유료 요금제 업그레이드는 추가하지 않았다. Firebase가 제공하는 HTTPS 기본 주소를 사용한다. Hosting은 현재 공식 안내상 저장 10GB와 월 전송 10GB까지 무료 범위를 제공하며, 초과 시 동작과 비용은 프로젝트 요금제에 따른다. 이를 전체 앱 운영 비용이 무료라는 의미로 해석하지 않는다. [Firebase Hosting 사용량·요금](https://firebase.google.com/docs/hosting/usage-quotas-pricing), [기본 HTTPS 주소](https://firebase.google.com/docs/hosting/quickstart).

CSP는 동일 출처 스크립트와 WebAssembly 실행을 허용하고 임의 인라인 스크립트·외부 프레임 삽입·object 실행을 제한한다. Flutter가 HTTPS 레시피 이미지를 fetch로 가져오는 특성 때문에 HTTPS 연결/이미지/글꼴은 허용한다. 클라이언트 파일은 재검증하도록 캐시 헤더를 지정해 예전 화면이 오래 남지 않도록 했다. HSTS, nosniff, referrer 제한, frame 차단을 적용했다. 로그인 후 작업실은 검색 노출용 모집 페이지와 달리 noindex다.

서버의 회원 권한·RLS·AI 사용 한도를 앱과 공유한다. 구매 이력은 관리하지만 조리 완료에 따라 재고를 차감하지 않는다. 웹 신규 결제·웹 푸시·오프라인 업무·실시간 공동 편집은 제공하지 않는다. 외부 공유 및 PDF 다운로드는 브라우저별 최종 사용자 검증이 남아 있다.
