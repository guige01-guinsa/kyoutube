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
4. Start local Supabase stack.
5. Provide runtime keys with dart-define.
6. Run app.

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
	-Headers @{ Authorization = "Bearer <ANON_KEY_FROM_SUPABASE_START>"; apikey = "<ANON_KEY_FROM_SUPABASE_START>"; "Content-Type" = "application/json" } \
	-Body '{"size":30}'
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
- Release signing is configured to use `android/key.properties` when present.
- If `android/key.properties` does not exist, release builds fall back to the debug signing key for local verification only.
- Copy `android/key.properties.example` to `android/key.properties` and fill in your real keystore values before Play release preparation.

Example release commands:
```powershell
flutter build appbundle \
	--dart-define=APP_ENV=production \
	--dart-define=SUPABASE_URL_PRODUCTION=https://<your-project-ref>.supabase.co \
	--dart-define=SUPABASE_ANON_KEY_PRODUCTION=<YOUR_PRODUCTION_ANON_KEY>
```

Before store submission, update these Android items:
- `applicationId` in `android/app/build.gradle.kts` if you want a different final Play identifier than `com.kyoutube.app`
- `namespace` in `android/app/build.gradle.kts` if you change the package id
- `package` path for `MainActivity.kt` if you change the package id
- `app_name` in `android/app/src/main/res/values/strings.xml`
