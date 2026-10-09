# 레시피 스카우트 v99 홍보 자동화

## 기준과 현재 상태

- 기준 소스: release/version-1.0.0-13, 330642e176dbc3dc00cf1dbacd6c90938c1cd170, 앱 1.0.1+99.
- 사용자 확인에 따라 Releases의 recipe-scout-v99.aab 내부 버전·서명·소스 재검증은 생략.
- 기존 PR #33 전체를 병합하지 않고 마케팅 관련 코드만 최신 릴리스에 통합.
- 운영 웹 문서 주소: https://recipe-scout-workspace.web.app
- Android applicationId: com.kyoutube.app. Supabase 인증·DB·함수와 Firebase 웹 호스팅·알림 구조 유지.

## 구현

계정 관리에서 별도 marketing_admins allowlist 관리자에게 마케팅 자동화 메뉴 표시. 요리 영상 검색·장보기 목록·보유 재료 검색을 주제로 한국어 초안 생성, 3개 장면 검토, 예약 승인·취소, 업로드 결과 및 조회·좋아요 확인. 관리자 작업은 서버에서 AAL2 확인. AI 요청은 최근 24시간 5회 제한, 불확실한 업로드 자동 재전송 금지. 설치·가입·재방문 분석은 미구현.

## 잠정 중지

- 새 marketing-worker.yml에는 schedule이 없고 publish 조건이 false이므로 수동 실행해도 게시하지 않음.
- 새 marketing_generate 구현은 Supabase Secret MARKETING_GENERATION_ENABLED가 정확히 true일 때만 AI 호출. 기본값/누락/false에서는 503 반환, 외부 AI 요청이나 생성 한도 소비 없음.
- 배포 워크플로는 추가하지 않음. 앱·운영 DB·함수를 이번 작업에서 배포하지 않음.
- 이 브랜치의 차단은 기존 main이나 이미 배포된 함수를 소급 중지하지 않음. 기존 운영 중지는 별도로 GitHub MARKETING_ENABLED=false, 실행 중 게시 작업 취소 및 운영 함수 접근 차단 확인 필요.
- Draft PR 자체는 실행 중지 장치가 아님.

## 재개 전 확인 순서

1. Flutter Quality와 Marketing Quality 통과, 최신 v99 기능 회귀 확인.
2. 운영 프로젝트 및 migration 이력 확인. PR #33 문서의 2026-10-07 DB/함수 적용 기록은 이 작업에서 직접 재확인하지 않음. 이미 적용된 20261007053241 마케팅 migration을 재적용하지 말 것. 기존 migration 파일 수정 금지.
3. 운영 관리자 allowlist, AAL2 로그인 및 현재 앱의 MFA 진입 경로 확인. 미완료 시 생성·예약·취소 불가.
4. OpenAI 키·모델 및 예산 설정 확인. 기존 레시피 AI 설정 유지. 키는 Secret 입력란에 직접 등록하고 채팅·코드에 넣지 않음.
5. 사용자 별도 승인 후 현재 앱 통합본과 함수만 배포. 자동 게시 중지는 유지하고 생성 기능부터 시험.
6. YouTube OAuth 채널 소유권과 worker Secrets 확인. 대상 @guige01, 최초 공개 설정 private. Shorts는 채널 프로필 Play 링크 안내.
7. 별도 재개 승인 후 예약·취소·중복 방지 검증을 거쳐 worker 실행 코드/스케줄을 복구. MARKETING_ENABLED=true만 바꾸어서는 이 브랜치의 차단이 해제되지 않음.

## 확인 명령

- node --test tools/marketing/worker.test.mjs
- deno check supabase/functions/marketing_generate/index.ts
- MARKETING_PGLITE_PATH=/path/to/pglite/dist/index.js node tools/marketing/database.test.mjs
- python tools/marketing/render_test.py
- powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1

운영 DB migration·Edge Function·앱 배포 및 홍보 게시 활성화는 별도 승인 후 진행.
