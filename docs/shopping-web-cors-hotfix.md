# 웹 장보기 생성 차단 수정 — 2026-09-15

## 확인한 원인

웹 장보기 생성 시 `KitchenApi.createShoppingList`는 중복 생성 방지를 위한 `Idempotency-Key` 헤더를 보낸다. 운영 `recipe_api` v53의 CORS 허용 헤더에는 이 항목이 빠져 있었다. 실제 운영 OPTIONS 응답은 200이지만 허용 목록은 `authorization, x-client-info, apikey, content-type`뿐이므로 브라우저는 POST 본 요청을 보내지 못한다. 화면에는 HTTP 응답 코드가 없는 일반 연결 오류로 표시된다.

운영 함수 소스와 로컬 소스가 같은 것을 확인했다. DB 열·권한 점검에서도 구매 수량이나 목록 제목 수정 권한의 누락은 없었다. 이번에 확인한 차단은 DB0059 업체 등록 스키마 변경과는 별개인 웹 통신 설정 문제다.

## 수정 범위

- `supabase/functions/recipe_api/handler.ts`의 기존 허용 목록에 **`idempotency-key` 하나만 추가**한다.
- 로그인 검증, 기존 Origin/메서드 허용 범위, 요청 크기 제한, RPC와 구매 수량, 중복 생성 방지 키를 유지한다.
- 같은 헤더를 사용하는 장보기 완료·작업 정리도 함께 정상적인 브라우저 사전 요청을 통과하게 된다.
- `handler_test.ts`에 CORS, 로그인 차단, 구매 수량 및 재시도 회귀 검사를 추가한다. 공개 웹 검사도 Auth 조회 외에 실제 장보기 쓰기 헤더를 점검하도록 보완한다.

## 검증

- 운영 읽기 전용 사전 요청: 누락 헤더 `idempotency-key` 확인. 고객 자료 생성·변경 없음.
- 수정 전 Deno: **2개 통과·CORS 검사 1개 실패**로 재현.
- 수정 후 Deno: **3개 모두 통과**. 사전 요청, 인증 없음/잘못된 토큰/익명 계정 거절, 구매량 200g·6개·5개·6개 및 구매량 미입력, 생성 201·같은 요청 재시도 200 확인. POST의 하위 Auth/DB 응답은 테스트용 모형을 사용한다.
- `recipe_api/index.ts` 전체 타입 검사 통과.
- Flutter 정적 분석 0건. 전체 Flutter **342개 통과·기존 선택형 4개 건너뜀**. 공개 웹 검사 스크립트 문법과 수정 파일의 공백 검사도 통과했다.

## 운영 반영 상태

**사용자 승인 후 운영 배포 완료.** `recipe_api` 서버 함수만 v53 → v54로 배포했다. DB·웹 산출물·AAB와 다른 함수는 변경하지 않았다. 기존 v66 앱·웹이 수정된 서버를 사용한다. 운영 완료 시각: `2026-09-15T13:08:31.933110+00:00`.

배포 직전에 운영 소스를 재보관하고 상대 import 파일 6개 중 허용 헤더 한 항목만 달라진 것을 확인했다. 배포 후 내려받은 6개 파일도 검증한 로컬 소스와 바이트 단위로 일치했다.

- 두 웹 도메인의 장보기 생성 사전 요청: 200 및 `idempotency-key` 허용.
- 미인증·익명·잘못된 토큰 POST: 401. 잘못된 메서드: 405. 기존 사용자 인증 유지.
- 장보기 생성·완료·작업 정리의 쓰기 헤더 검사와 기존 공개 웹 검사를 합쳐 **9개 통과**. 공개 웹 v66 파일 해시 일치, 한영 PC/모바일·로그인 화면·인증 CORS 확인, 브라우저/HTTP 오류 0건.
- 실제 사용자 계정의 장보기 목록은 만들지 않았다. 사용자는 기존 장보기 준비 화면에서 목록 만들기를 다시 눌러 확인할 수 있다. 앱 재설치나 새 AAB는 필요 없다.

[운영 배포·검증 기록](../release/verify-v66-shopping-cors.json).

원인·검사 로그: ignored `.artifacts/shopping-preflight-before.json`, `shopping-incident-inspection.json`, `shopping-cors-before.log`, `shopping-cors-after.log`, `shopping-cors-deno-check.log`. 배포 전 소스는 `.artifacts/shopping-incident-live-20260915`에 보관했다. 승인된 배포 도구 `.artifacts/deploy_shopping_cors.py --apply` 실행을 완료했다. 상세 보고서는 `.artifacts/shopping-cors-function-deployment.json`이며 최신 배포 전 소스는 `.artifacts/shopping-cors-function-backup-*`에 있다. 재실행 전에는 운영 상태를 먼저 조회한다.
