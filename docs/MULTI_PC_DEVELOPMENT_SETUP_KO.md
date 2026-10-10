# 사무실 PC에서 레시피 스카우트 개발하기

## 사용할 소스

사무실 개발 기준 브랜치는 **codex/office-development-v99** 입니다. 이 브랜치에는 집 PC의 v99 기능 소스, 실행에 필요한 이미지·폰트·웹 파일·테스트·DB 마이그레이션과 GitHub의 홍보 기능이 함께 포함됩니다. clone 후 Release ZIP을 별도로 풀 필요가 없습니다.

앱 v99 AAB는 2026-10-06에 제작됐고, 복구한 운영 웹은 2026-10-08에 검증된 웹 빌드입니다. 이 개발 브랜치는 현재 소스에 기존 GitHub 홍보 기능을 통합한 개발 기준이며, 두 배포 파일을 그대로 재현하는 소스 태그라는 뜻은 아닙니다. 홍보 기능의 운영 상태는 [검토 결과](MARKETING_READINESS_REVIEW_KO.md)를 확인하세요.

## 최초 준비

Git, Dart(FVM 설치용), Android Studio 및 Android SDK, JDK 17, Node.js LTS, Docker Desktop을 설치합니다. Flutter는 `.fvmrc`의 **3.44.8**을 사용합니다.

```powershell
git clone --branch codex/office-development-v99 --single-branch https://github.com/guige01-guinsa/kyoutube.git
cd kyoutube
dart pub global activate fvm
```

`fvm`을 찾지 못하면 Dart Pub cache의 `bin` 디렉터리를 PATH에 추가한 뒤 새 터미널을 여세요.

```powershell
fvm install 3.44.8
.\.fvm\flutter_sdk\bin\flutter.bat pub get
```

Android 개발은 JDK 17을 `JAVA_HOME`과 Android Studio Gradle JDK로 선택하고 Android SDK platform-tools를 PATH에 추가합니다.

## 로컬 서버와 개인 설정

Docker Desktop을 실행한 뒤 저장소 루트에서 로컬 서버를 시작합니다. 첫 실행은 이 브랜치의 마이그레이션을 새 로컬 DB에 적용하므로 시간이 걸릴 수 있습니다.

```powershell
npx supabase@latest start -x studio,logflare,imgproxy
```

저장소 루트에 `.env.local`을 직접 만들고 다음 항목을 본인 PC의 로컬 연결 정보로 입력합니다. 운영 키나 집 PC의 환경 파일을 GitHub에 올리지 않습니다.

- `APP_ENV`: `local`
- `SUPABASE_URL_LOCAL`: 본인 로컬 Supabase의 API 주소
- `SUPABASE_ANON_KEY_LOCAL`: 본인 로컬 Supabase의 공개 클라이언트 키

안드로이드 에뮬레이터는 PC의 localhost 대신 `10.0.2.2`로 접근합니다. 실제 기기 개발에는 해당 기기가 접근할 수 있는 로컬 PC 주소를 사용합니다. AI·YouTube 검색은 별도로 로컬 Edge Function 실행과 서비스 키 설정이 필요하며 키는 로컬의 무시되는 파일이나 플랫폼 Secret에만 보관합니다.

Android Firebase 기능에는 공식 Firebase 콘솔에서 받은 `android/app/google-services.json`이 필요합니다. 이 파일과 iOS의 Firebase 파일은 각 PC에 별도로 준비합니다. 일반 디버그 개발에는 Android 릴리스 서명 키가 필요하지 않습니다.

```powershell
powershell -ExecutionPolicy Bypass -File tools/dev/bootstrap.ps1
powershell -ExecutionPolicy Bypass -File run-local.ps1 -AppEnv local -Device chrome
```

Android는 다음과 같이 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File run-local.ps1 -AppEnv local
```

여러 기기가 연결되어 있으면 `-Device`에 해당 기기의 실제 식별자를 지정하세요.

## 집과 사무실에서 이어서 작업하기

작업을 시작할 때 현재 브랜치와 변경 상태를 확인하고 최신 소스를 받습니다. 수정 중인 파일이 있으면 먼저 변경사항을 커밋한 뒤 pull합니다.

```powershell
git branch --show-current
git status
git pull --ff-only origin codex/office-development-v99
```

작업 후 검사하고 변경한 소스 파일만 선택해 올립니다. 전체 폴더를 한 번에 추가하지 마세요.

```powershell
powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1
git add <변경한-소스-파일>
git commit -m "변경 내용"
git push origin codex/office-development-v99
```

집 PC에서도 같은 개발 브랜치를 사용하세요. 기존 작업이 있는 폴더에서 곧바로 브랜치를 바꾸기보다 이 브랜치를 새 폴더에 clone하면 기존 작업을 보존할 수 있습니다. 두 PC가 같은 파일을 동시에 수정하면 충돌을 검토한 뒤 병합해야 합니다.

## 운영 반영

GitHub에 push해도 운영 웹·DB·함수가 자동 배포되지 않습니다. 운영 반영은 정상 기준과 변경 범위를 확인하고 별도로 승인받아 진행합니다. 동일한 버전 번호만으로 동일한 소스인지 판단하지 말고 커밋과 웹 검증 파일의 해시를 확인하세요.

운영 웹 배포는 `tools/release/build-production-web.ps1`으로 빌드한 파일과 `firebase.web.json`의 대상을 확인한 뒤 수행합니다. AAB는 기존 앱과 동일한 서명 키가 필요합니다. `.env*`, keystore, `key.properties`, `local.properties`, Firebase 개인 설정, 빌드·로그·캐시는 GitHub에 올리지 않습니다.

