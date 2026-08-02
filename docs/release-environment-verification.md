# 출시 환경 검증 체크리스트

Last update: 2026-07-29

이 문서는 AAB 빌드 전 외부 서비스 설정이 올바른지 확인하기 위한 체크리스트입니다.
코드 수정은 자동으로 반영되지만 아래 항목들은 **사람이 직접 확인**해야 합니다.

---

## A. GitHub Secrets 설정 확인

[Settings → Secrets and variables → Actions](https://github.com/guige01-guinsa/kyoutube/settings/secrets/actions) 에서 아래 7개가 모두 설정됐는지 확인합니다.

| Secret 이름 | 설명 | 확인 |
|-------------|------|------|
| `SUPABASE_URL_PRODUCTION` | Supabase 프로젝션 URL (예: `https://xxxx.supabase.co`) | ⬜ |
| `SUPABASE_ANON_KEY_PRODUCTION` | Supabase anon key | ⬜ |
| `ANDROID_KEY_PROPERTIES` | `android/key.properties` 파일 전체 내용 | ⬜ |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | 업로드 키스토어 파일 Base64 인코딩 값 | ⬜ |
| `ANDROID_GOOGLE_SERVICES_JSON` | `google-services.json` 파일 전체 내용 | ⬜ |
| `PUBLIC_RECIPE_SYNC_FUNCTION_URL` | Supabase Edge Function URL | ⬜ |
| `PUBLIC_RECIPE_SYNC_WORKER_SECRET` | 동기화 함수 인증 비밀키 | ⬜ |

---

## B. Firebase 설정 확인

1. [Firebase Console](https://console.firebase.google.com) → 프로젝트 선택
2. **Project Settings → Your apps** 에서 Android 앱이 등록됐는지 확인

| 항목 | 기댓값 | 확인 |
|------|--------|------|
| Android 패키지명 | `com.kyoutube.app` | ⬜ |
| `google-services.json`의 `package_name` | `com.kyoutube.app` | ⬜ |
| SHA-1 인증서 지문 등록 여부 | 업로드 키스토어의 SHA-1 | ⬜ |
| Cloud Messaging 활성화 여부 | Enabled | ⬜ |

SHA-1 추출 명령 (로컬):
```powershell
keytool -list -v -keystore <키스토어파일.jks> -alias <keyAlias>
```

---

## C. Supabase 설정 확인

[Supabase Dashboard](https://supabase.com/dashboard) → 프로젝트 선택

### C1. Authentication → URL Configuration

| 항목 | 값 | 확인 |
|------|-----|------|
| Site URL | `https://<your-project>.supabase.co` 또는 앱 URL | ⬜ |
| Redirect URLs 에 추가됐는지 | `io.supabase.kyoutube://login-callback` | ⬜ |

> ⚠️ 이게 없으면 Google 로그인 후 앱으로 돌아오지 못합니다.

### C2. Authentication → Providers → Google

| 항목 | 확인 |
|------|------|
| Google OAuth provider 활성화 | ⬜ |
| Client ID (Web client ID from Google Cloud Console) 입력됨 | ⬜ |
| Client Secret 입력됨 | ⬜ |

---

## D. Google Cloud Console 설정 확인

[Google Cloud Console](https://console.cloud.google.com) → 프로젝트 선택 → APIs & Services → Credentials

| 항목 | 확인 |
|------|------|
| OAuth 2.0 Client ID (Web application 타입) 생성됨 | ⬜ |
| Authorized redirect URI에 Supabase 콜백 URL 추가됨 | ⬜ |
| Android OAuth Client ID 생성됨 (패키지명 + SHA-1) | ⬜ |

Supabase 콜백 URL 형식:
```
https://<your-project-ref>.supabase.co/auth/v1/callback
```

---

## E. Play Console 설정 확인

[Google Play Console](https://play.google.com/console)

| 항목 | 확인 |
|------|------|
| 앱 생성됨 (`com.kyoutube.app`) | ⬜ |
| 내부 테스트 트랙 존재 | ⬜ |
| 개인정보처리방침 URL 입력됨 | ⬜ |

---

## 최종 체크 — AAB 빌드 전 확인

위 A~E 항목이 모두 ✅ 완료된 후:

1. [Internal Track Release Guard 워크플로우](https://github.com/guige01-guinsa/kyoutube/actions/workflows/internal-track-release-guard.yml) 실행
2. Branch: `main`, 모든 옵션 기본값
3. 빌드 성공 시 Artifacts에서 `app-release-aab` 다운로드
4. Play Console 내부 테스트 트랙에 업로드
