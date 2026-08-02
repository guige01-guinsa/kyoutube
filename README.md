# K-youtube

Flutter, Supabase, Firebase 기반의 Android-first AI 요리 플랫폼입니다.

## 1. 프로젝트 소개

Flutter 앱은 레시피 탐색·저장·제작·주방 기능을 제공하며 Supabase Auth, Postgres, Storage와 Edge Functions를 사용합니다. Firebase Cloud Messaging은 모바일 푸시를 담당합니다.

## 2. 필수 도구

- Flutter 3.44.8 (`.fvmrc` 및 프로젝트별 FVM SDK에 고정)
- JDK 17 (Android Gradle Java/Kotlin target 17)
- Android SDK와 `adb`
- Node.js LTS 및 npm
- Docker Desktop (Supabase 로컬 스택을 사용할 때)
- Supabase CLI: 전역 설치 또는 `npx supabase@latest`

## 3. 최초 설치

FVM을 설치한 뒤, 저장소 루트에서 고정 SDK를 받습니다. 전역 Flutter는 이 프로젝트의 실행·검증에 사용하지 않습니다.

```powershell
fvm install 3.44.8
```

그 다음 bootstrap을 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File tools/dev/bootstrap.ps1
```

이 스크립트는 도구, Flutter/JDK 버전, Android SDK, 환경 파일 존재 여부를 검사하고 `flutter pub get`을 실행합니다. 값은 출력하거나 읽지 않습니다.

## 4. 환경파일 설정

`.env.example` 또는 `.env.local.example`을 `.env.local`로 복사하고 로컬 값을 설정합니다. `.env.local`, 루트 `.env`, `android/key.properties`, keystore와 Firebase 설정 파일은 커밋하지 않습니다.

```powershell
Copy-Item .env.local.example .env.local
```

`APP_ENV=local`에는 `SUPABASE_URL_LOCAL`, `SUPABASE_ANON_KEY_LOCAL`이 필요합니다. 실기기에서 로컬 Supabase에 접속할 때는 아래 Android 기기 연결 절차도 수행하세요.

## 5. 로컬 Supabase 시작

Docker Desktop을 시작한 뒤 로컬 스택을 실행합니다.

```powershell
npx supabase@latest start -x studio,logflare,imgproxy
npx supabase@latest status
```

기존 migration은 수정하지 않습니다. 데이터베이스 초기화와 migration push는 명시적 승인 없이는 실행하지 않습니다.

## 6. Flutter 앱 실행

표준 진입점은 루트 스크립트입니다.

```powershell
powershell -ExecutionPolicy Bypass -File run-local.ps1 -AppEnv local
```

`local`, `staging`, `production` 중 환경을 선택할 수 있습니다. 운영 환경 실행은 검증된 환경 파일로만 수행하세요.

## 7. 테스트와 정적 분석

```powershell
powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1
```

개별 실행은 `flutter analyze`, `flutter test`입니다.

## 8. Android 기기 연결

USB 디버깅을 승인한 후 기기와 로컬 Supabase 포트를 연결합니다.

```powershell
adb devices
adb reverse tcp:54321 tcp:54321
adb reverse --list
```

## 9. Edge Function 개발

함수는 `supabase/functions/`의 Deno/TypeScript 소스입니다. 로컬 함수 실행은 Supabase CLI 문서를 따르며, 필요한 비밀값은 무시되는 로컬 파일 또는 로컬 Supabase 환경에만 둡니다. `recipe_api`, `ai_recipe_assistant`, `public_recipe_sync`는 배포 전 로컬 요청/응답 검증을 추가해야 합니다. 배포·비밀 설정 변경은 이 저장소의 일반 개발 절차에 포함하지 않습니다.

## 10. 릴리스 절차

릴리스는 `docs/internal-track-release-checklist.md`와 기존 수동 workflow를 따릅니다. 서명키와 Firebase 파일이 필요하며, 로컬 개발 스크립트는 릴리스 빌드·AAB 업로드·배포를 수행하지 않습니다.

## 11. 문제 해결

- Flutter 버전 오류: 저장소 루트에서 `fvm install 3.44.8`을 실행합니다. 스크립트는 `.fvm/flutter_sdk/bin/flutter.bat`만 사용하며 전역 Flutter로 대체하지 않습니다.
- JDK 오류: JDK 17을 선택한 뒤 새 터미널에서 `java -version`을 확인합니다.
- `.env.local` 오류: 예시 파일에서 새로 만들고 필요한 변수만 설정합니다.
- Android 실기기에서 로컬 API에 연결되지 않음: `adb reverse` 결과에 54321 포트가 있는지 확인합니다.
- Firebase 초기화 오류: 플랫폼별 Firebase 설정 파일이 로컬에 있는지 확인합니다. 해당 파일은 커밋하지 않습니다.

상세 개발 흐름은 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md), 구성은 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)를 참고하세요.
