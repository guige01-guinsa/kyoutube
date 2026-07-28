# K-youtube

AI cooking platform MVP with Flutter + Supabase.

## Current status
- Manual bootstrap complete
- App skeleton, routing, and Supabase init code added
- Supabase schema and RLS migration drafts added

## Local setup
1. Install Flutter SDK and add it to PATH.
2. Run: flutter create . --project-name k_youtube --platforms=android,ios
3. Run: flutter pub get
4. Copy `.env.local.example` to `.env.local` and fill in the local values.
5. Run `tools\dev\check-dev-env.ps1`.
6. Start local Supabase stack.
7. Run `tools\dev\run-local.ps1`.

See [docs/development-environment.md](docs/development-environment.md) for the standard setup.

### Local Supabase
```powershell
npx supabase@latest start -x studio,logflare,imgproxy
npx supabase@latest db reset
```

### Public recipe sync function
```powershell
Invoke-RestMethod \
	-Method Post \
	-Uri http://127.0.0.1:54321/functions/v1/public_recipe_sync \
	-Headers @{ "x-worker-secret" = "<PUBLIC_RECIPE_SYNC_WORKER_SECRET>"; "Content-Type" = "application/json" } \
	-Body '{"size":30}'
```

### COOKRCP01 real API setup (식품안전나라)
공공 레시피는 COOKRCP01 인증키를 설정하면 실제 식품안전나라 데이터에서 동기화됩니다.

1) Edge Function 환경 변수 설정
```powershell
supabase secrets set FOOD_API_KEY="<COOKRCP01_API_KEY>"
supabase secrets set FOOD_API_BASE_URL="https://openapi.foodsafetykorea.go.kr/api"
supabase secrets set FOOD_API_URL_TEMPLATE="https://openapi.foodsafetykorea.go.kr/api/{API_KEY}/COOKRCP01/json/{START}/{END}"
supabase secrets set PUBLIC_RECIPE_SYNC_WORKER_SECRET="<RANDOM_LONG_SECRET>"
```

2) 함수 실행
```powershell
Invoke-RestMethod \
	-Method Post \
	-Uri http://127.0.0.1:54321/functions/v1/public_recipe_sync \
	-Headers @{ "x-worker-secret" = "<PUBLIC_RECIPE_SYNC_WORKER_SECRET>"; "Content-Type" = "application/json" } \
	-Body '{"size":200}'
```

3) 동기화 개수 확인
```powershell
$service = "<SERVICE_ROLE_KEY_FROM_SUPABASE_START>"
$headers = @{ apikey = $service; Authorization = "Bearer $service"; Prefer = "count=exact" }
(Invoke-WebRequest -Uri "http://127.0.0.1:54321/rest/v1/recipes_public?select=id&limit=1" -Headers $headers).Headers["Content-Range"]
```

### Recipe API function examples
GET list public:
```powershell
Invoke-RestMethod \
	-Method Get \
	-Uri "http://127.0.0.1:54321/functions/v1/recipe_api?type=public&search=egg&limit=10&offset=0" \
	-Headers @{ apikey = "<ANON_KEY_FROM_SUPABASE_START>"; Authorization = "Bearer <ANON_KEY_FROM_SUPABASE_START>" }
```

GET detail public:
```powershell
Invoke-RestMethod \
	-Method Get \
	-Uri "http://127.0.0.1:54321/functions/v1/recipe_api/<PUBLIC_RECIPE_ID>?type=public" \
	-Headers @{ apikey = "<ANON_KEY_FROM_SUPABASE_START>"; Authorization = "Bearer <ANON_KEY_FROM_SUPABASE_START>" }
```

POST creator (authorized):
```powershell
Invoke-RestMethod \
	-Method Post \
	-Uri "http://127.0.0.1:54321/functions/v1/recipe_api?type=creator" \
	-Headers @{ apikey = "<ANON_KEY_FROM_SUPABASE_START>"; Authorization = "Bearer <USER_ACCESS_TOKEN>"; "Content-Type" = "application/json" } \
	-Body '{"title":"My Omelette","summary":"Fast breakfast","ingredients":["egg","salt"],"steps":["Beat eggs","Cook on pan"],"tips":"Low heat","is_published":true}'
```

Local values from `supabase start` output:
- SUPABASE_URL: `http://127.0.0.1:54321`
- SUPABASE_ANON_KEY: use `ANON_KEY`

### Run command example
```powershell
flutter run \
	--dart-define=APP_ENV=local \
	--dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
	--dart-define=SUPABASE_ANON_KEY=<ANON_KEY_FROM_SUPABASE_START>
```

### Environment separation
- `APP_ENV` supports `local`, `staging`, `production`.
- For quick local work, existing `SUPABASE_URL` and `SUPABASE_ANON_KEY` still work.
- For safer separation, pass environment-specific keys instead of reusing one pair everywhere.

Local example:
```powershell
flutter run \
	--dart-define=APP_ENV=local \
	--dart-define=SUPABASE_URL_LOCAL=http://127.0.0.1:54321 \
	--dart-define=SUPABASE_ANON_KEY_LOCAL=<ANON_KEY_FROM_SUPABASE_START>
```

Real-device local check (Android, USB):
```powershell
adb reverse tcp:54321 tcp:54321
adb reverse --list
npx supabase@latest status
```

Expected:
- `adb reverse --list` includes `tcp:54321 tcp:54321`
- Supabase API URL is `http://127.0.0.1:54321`

Production example:
```powershell
flutter run \
	--dart-define=APP_ENV=production \
	--dart-define=SUPABASE_URL_PRODUCTION=https://<your-project-ref>.supabase.co \
	--dart-define=SUPABASE_ANON_KEY_PRODUCTION=<YOUR_PRODUCTION_ANON_KEY>
```

### Login flow
- 홈 우측 상단 로그인 아이콘으로 이메일 로그인/회원가입 화면에 진입합니다.
- 로그인 후 홈 우측 상단 `내 레시피` 아이콘으로 creator 목록 화면에 진입합니다.

## Firebase setup
1. Firebase Console에서 프로젝트를 만들고 Cloud Messaging을 사용할 Android 앱 `com.kyoutube.app`을 등록합니다.
2. `google-services.json`을 다운로드해 `android/app/google-services.json`에 배치합니다.
3. iOS도 사용할 경우 Firebase Console에서 iOS 앱을 추가하고 `GoogleService-Info.plist`를 다운로드합니다.
4. `GoogleService-Info.plist`를 `ios/Runner` 아래에 복사한 뒤 Xcode에서 Runner target 리소스로 추가합니다.
5. Android 13 이상 알림 표시를 위해 앱 최초 실행 시 알림 권한을 허용합니다.

Android quick check:
```powershell
Test-Path android/app/google-services.json
```

iOS quick check:
```powershell
Test-Path ios/Runner/GoogleService-Info.plist
```

현재 앱은 시작 시 `Firebase.initializeApp()`을 호출합니다. 설정 파일이 없으면 Firebase 초기화 단계에서 바로 실패하도록 해 두었습니다.

### Non-admin Flutter install (Windows)
```powershell
$meta = Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
$stable = $meta.current_release.stable
$release = $meta.releases | Where-Object { $_.hash -eq $stable }
$url = "https://storage.googleapis.com/flutter_infra_release/releases/$($release.archive)"
$zip = Join-Path $HOME 'tools\\flutter_sdk.zip'
Invoke-WebRequest -Uri $url -OutFile $zip
Expand-Archive -Path $zip -DestinationPath (Join-Path $HOME 'tools') -Force
setx PATH "$env:PATH;$HOME\\tools\\flutter\\bin"
```

## Architecture (MVP)
- App: Flutter (Android first)
- Backend: Supabase Auth, Postgres, Storage, Edge Functions
- AI: OpenAI via Supabase Edge Function
- Push: Firebase Cloud Messaging

## Key folders
- lib/: Flutter app code
- supabase/migrations/: SQL schema and RLS policies
- supabase/functions/: edge function placeholders
- docs/: architecture and cost guardrails

## Android release prep
- Release signing requires `android/key.properties` by default.
- If release signing values are missing, `release` build fails to prevent accidental non-production signing.
- For local verification only, you can allow debug signing explicitly with `-PallowDebugSigningForRelease=true`.
- Copy `android/key.properties.example` to `android/key.properties` and fill in your real keystore values before Play release preparation.

Example release commands:
```powershell
flutter build appbundle \
	-PallowDebugSigningForRelease=true \
	--dart-define=APP_ENV=production \
	--dart-define=SUPABASE_URL_PRODUCTION=https://<your-project-ref>.supabase.co \
	--dart-define=SUPABASE_ANON_KEY_PRODUCTION=<YOUR_PRODUCTION_ANON_KEY>
```

Production submission should run without `-PallowDebugSigningForRelease=true`.

Before store submission, update these Android items:
- `applicationId` in `android/app/build.gradle.kts` if you want a different final Play identifier than `com.kyoutube.app`
- `namespace` in `android/app/build.gradle.kts` if you change the package id
- `package` path for `MainActivity.kt` if you change the package id
- `app_name` in `android/app/src/main/res/values/strings.xml`
