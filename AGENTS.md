# Kyoutube — Codex Agent Instructions

이 파일은 OpenAI Codex CLI가 이 저장소에서 작업할 때 참조하는 컨텍스트 및 지침입니다.

---

## 프로젝트 개요

**Kyoutube**는 한국 음식 레시피 앱으로 Flutter(Android/iOS) + Supabase + Firebase로 구성된 AI 쿠킹 플랫폼 MVP입니다.

- **앱**: Flutter (Dart), `lib/` 디렉터리
- **백엔드**: Supabase (Auth, Postgres, Storage, Edge Functions), `supabase/`
- **CI/CD**: GitHub Actions, `.github/workflows/`
- **릴리즈 도구**: PowerShell 스크립트, `tools/release/`
- **문서**: `docs/`

---

## 기술 스택

| 레이어 | 기술 |
|--------|------|
| 모바일 앱 | Flutter 3, Dart, flutter_riverpod, go_router |
| 인증 | Supabase Auth (Google OAuth, 이메일) |
| DB | Supabase Postgres (RLS 적용) |
| Edge Functions | Deno TypeScript (`supabase/functions/`) |
| 알림 | Firebase Cloud Messaging |
| AI | OpenAI API (서버 사이드 전용) |
| 레시피 데이터 | 식품안전처 공공 API (COOKRCP01) |
| CI/CD | GitHub Actions (ubuntu/windows-latest) |

---

## 디렉터리 구조

```
lib/
  main.dart                        # 앱 진입점, OpsMonitorService 초기화
  app.dart                         # KYoutubeBootstrapApp (Supabase + Firebase 부트스트랩)
  core/
    config/env.dart                # 환경변수 (APP_ENV: local/staging/production)
    firebase/                      # Firebase 초기화 및 FCM 서비스
    ops/ops_monitor_service.dart   # 오류 추적 및 운영 상태 모니터링
    router/app_router.dart         # go_router 라우팅 정의
    theme/app_theme.dart           # 앱 테마
    widgets/                       # 공용 위젯
  features/
    auth/                          # 인증 (Google OAuth, 이메일)
    recipes/                       # 공개/크리에이터/구독자 레시피
    kitchen/                       # 냉장고 재료 관리, 장보기, 요리 세션
    home/                          # 홈 화면 (레시피 목록 + Kitchen 요약 카드)
    ai/                            # AI 어시스턴트 서비스
    cooking/                       # 음성 가이드 (요리 중 안내)
    shopping/                      # 장보기 서비스

supabase/
  config.toml                      # 로컬 Supabase 설정 (project_id: k-youtube)
  migrations/                      # SQL 마이그레이션 (0001~0007)
  functions/
    public_recipe_sync/index.ts    # 공공 레시피 동기화 Edge Function

.github/workflows/
  deploy-public-recipe-sync.yml   # Supabase Edge Function 배포
  apply-supabase-migrations.yml   # DB 마이그레이션 적용
  internal-track-release-guard.yml # 서명된 AAB 빌드 + 스모크 체크
  release-guard-command.yml        # /release-guard PR 슬래시 커맨드

tools/release/
  run-internal-track-validation.ps1  # 릴리즈 유효성 검사 스크립트 (Windows PowerShell)
```

---

## 환경 설정

### 환경변수

앱은 `dart-define`으로 주입된 환경변수를 사용합니다. `.env.example`을 복사해 `.env`를 만드세요.

```bash
cp .env.example .env
# .env 파일에 실제 값 입력
```

주요 환경변수:
- `APP_ENV`: `local` | `staging` | `production`
- `SUPABASE_URL_LOCAL` / `SUPABASE_ANON_KEY_LOCAL`
- `SUPABASE_URL_PRODUCTION` / `SUPABASE_ANON_KEY_PRODUCTION`
- `OPENAI_API_KEY`: 서버 사이드 전용, 앱에 직접 넣지 않음

### 로컬 실행

```bash
# 로컬 Supabase 시작
supabase start

# Flutter 앱 실행 (로컬 환경)
flutter run \
  --dart-define=APP_ENV=local \
  --dart-define=SUPABASE_URL_LOCAL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY_LOCAL=<supabase start 출력값>
```

### 정적 분석 및 테스트

```bash
flutter analyze          # 린트 검사 (항상 통과해야 함)
flutter test             # 단위/위젯 테스트
```

---

## 코딩 규칙

### Flutter / Dart

1. **상태 관리**: `flutter_riverpod`만 사용, StatefulWidget 최소화
2. **라우팅**: `go_router` 사용, `app_router.dart`에 라우트 정의
3. **환경변수**: `lib/core/config/env.dart`의 `Env` 클래스를 통해서만 접근
4. **에러 처리**: `OpsMonitorService.recordError()`로 에러 기록
5. **서비스 키**: 앱 코드에 service role key, OpenAI API key 등 서버 전용 키 절대 포함 금지
6. **한국어 UI**: 사용자에게 보이는 모든 문자열은 한국어로 작성
7. **린트**: `analysis_options.yaml` 준수, `avoid_print`, `prefer_const_constructors` 규칙 준수

### Supabase

1. **마이그레이션**: `supabase/migrations/` 에 순번 파일명으로 추가 (예: `0008_xxx.sql`)
2. **RLS**: 모든 새 테이블에 RLS 정책 필수 (`owner_id = auth.uid()`)
3. **Edge Functions**: `supabase/functions/<name>/index.ts`, Deno TypeScript 사용
4. **서비스 키**: Edge Function 내에서만 `SUPABASE_SERVICE_ROLE_KEY` 사용

### CI/CD

1. **GitHub Actions 액션 버전**: Node 24 호환 버전 사용 (현재: `checkout@v7`, `setup-java@v5`, `upload-artifact@v7`, `setup-cli@v3`)
2. **시크릿**: 워크플로우에 하드코딩 금지, GitHub Secrets 사용
3. **릴리즈 가드**: `/release-guard` PR 슬래시 커맨드로 `internal-track-release-guard.yml` 트리거

---

## 현재 개발 상태 (Phase 2)

### 완료된 작업

- ✅ **Phase 2 / Feature Track Step 1**: 구독자 레시피 MVP (공개 레시피 복사, 개인 노트, 목록/상세)
- ✅ **Phase 2 / Ops Track Step 1**: 내부 트랙 릴리즈 검증 (`internal-track-release-guard.yml`)
- ✅ Kitchen 기반 스키마 마이그레이션 (`0007_kitchen_foundation.sql`)
- ✅ Kitchen API 클라이언트 (`lib/features/kitchen/data/kitchen_api.dart`)
- ✅ Google OAuth 로그인 구현
- ✅ CI 액션 버전 업데이트 (Node 24 호환)
- ✅ `/release-guard` PR 슬래시 커맨드

### 진행 중 / 다음 작업

- 🔄 **Phase 2 / Ops Track Step 2**: Firebase 프로덕션 설정 및 실제 기기 푸시 검증
- 🔄 **Phase 2 / Ops Track Step 3**: 개인정보처리방침/이용약관 URL 게시, Play 데이터 안전 양식 완성
- ⏳ **Phase 2 / Feature Track Step 2**: AI 어시스턴트 실제 모델 연동 및 사용량 로깅
- ⏳ **Phase 2 / Feature Track Step 3**: YouTube 메타데이터 워커 및 UX 개선

### 알려진 블로커

- Windows CI 러너에서 Flutter `gen_snapshot.EXE` 실행 정책 문제 → AAB 업로드는 allowlist 또는 CI 빌드 환경 변경 필요

---

## 데이터 모델 요약

### 주요 테이블

| 테이블 | 설명 |
|--------|------|
| `profiles` | 사용자 프로필 (Supabase Auth와 연동) |
| `recipes_public` | 공공 레시피 (식품안전처 API 동기화) |
| `recipes_creator` | 크리에이터 레시피 (사용자 작성) |
| `recipes_subscriber` | 구독자 레시피 (공개 레시피 개인 복사본) |
| `kitchen_ingredients` | 냉장고/재료 재고 |
| `kitchen_shopping_lists` | 장보기 목록 |
| `kitchen_shopping_items` | 장보기 항목 |
| `kitchen_cook_sessions` | 요리 완료 세션 및 피드백 |

### RLS 원칙

- 모든 사용자 데이터 테이블: `owner_id = auth.uid()` 기반 행 수준 보안
- 공개 레시피: 모든 사용자 읽기 허용, 서비스 롤만 쓰기 가능
- 서비스 롤 키: Edge Function 내에서만 사용

---

## 문서 위치

| 문서 | 경로 |
|------|------|
| 아키텍처 | `docs/architecture.md` |
| Phase 2 개발 계획 | `docs/phase-2-development-plan.md` |
| Kitchen 구현 스펙 | `docs/kitchen-priority-implementation-spec.md` |
| 내부 트랙 릴리즈 체크리스트 | `docs/internal-track-release-checklist.md` |
| 운영 스모크 체크리스트 | `docs/ops-smoke-checklist.md` |
| 비용 가드레일 | `docs/cost-guardrails.md` |
| 작업 일지 | `docs/worklog/` |
