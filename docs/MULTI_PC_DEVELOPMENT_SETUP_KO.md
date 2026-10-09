# 집·사무실 PC 공통 개발 및 배포 환경

이 프로젝트는 여러 PC에서 같은 GitHub 저장소를 사용해 개발하고 Firebase 운영 웹과 Android AAB를 배포할 수 있습니다.

## 사무실 PC 최초 설정

1. Git을 설치하고 저장소를 clone합니다.

```powershell
git clone https://github.com/guige01-guinsa/kyoutube.git
cd kyoutube
```

2. Flutter 3.44.8과 JDK 17을 설치합니다. 저장소의 `.fvmrc`에 지정된 Flutter 버전을 사용해야 합니다.

3. 프로젝트 의존성을 설치합니다.

```powershell
fvm install 3.44.8
fvm flutter pub get
```

4. 집 PC의 비밀 설정을 복사하지 말고, 사무실 PC에서 별도로 준비합니다.

- `.env.local`
- Firebase 설정 파일
- Supabase URL·키 설정
- Android 서명용 `key.properties`와 keystore

이 파일들은 GitHub에 올리지 않습니다.

## 매일 작업할 때

작업을 시작하기 전에 최신 코드를 받습니다.

```powershell
git pull --rebase origin main
```

작업 후에는 변경사항을 확인하고 커밋합니다.

```powershell
git status
git add <변경한 파일>
git commit -m "작업 내용"
git push origin main
```

## 운영 웹 배포

Firebase CLI에 운영 프로젝트 계정으로 로그인한 뒤 최신 코드를 받은 상태에서 배포합니다.

```powershell
firebase login
firebase use korea-01
powershell -ExecutionPolicy Bypass -File tools\release\build-production-web.ps1
firebase deploy --only hosting --config firebase.web.json --project korea-01
```

운영 주소는 https://recipe-scout-workspace.web.app 입니다.

## AAB 배포

Android 서명 키와 `key.properties`가 집 PC와 동일해야 기존 Play 앱의 업데이트로 사용할 수 있습니다. 서명 키가 다르면 새 앱으로 인식될 수 있으므로 GitHub에 업로드하지 말고 안전한 방법으로 두 PC에 각각 설치합니다.

```powershell
powershell -ExecutionPolicy Bypass -File tools\release\build-production-aab.ps1
```

## 충돌 방지 규칙

- 두 PC에서 동시에 같은 파일을 수정하지 않습니다.
- 작업 시작 전에 `git pull --rebase`를 실행합니다.
- 한 PC에서 커밋·push·배포를 끝낸 뒤 다른 PC에서 작업합니다.
- `.env*`, keystore, `key.properties`, 빌드 폴더와 로그는 커밋하지 않습니다.
- 운영 DB 마이그레이션과 Edge Function 배포는 별도 확인 후 진행합니다.
