# Recipe Scout 마케팅 자동화 1차 버전

## 구현 범위

- 앱의 **계정 관리 → 마케팅 자동화**: 등록된 관리자만 표시 및 접근.
- AI 초안 생성: 영상 검색·장보기·보유 재료 검색 중 하나를 소개. 외부 레시피나 개인 데이터를 조회하지 않음.
- 제목·설명·8초씩 3개 장면을 검토하고 5분~30일 이내 예약 승인. 예약 전 초안을 취소하고 새로 생성할 수 있음.
- 승인된 콘텐츠를 720×1280, 24초, 무음 카드 영상으로 자체 제작하고 공식 YouTube API로 업로드.
- 예약 작업은 매시간 17분에 후보 1개를 처리. GitHub Actions 스케줄은 지연될 수 있으며 정시 게시를 보장하지 않음.
- 조회·좋아요를 갱신. 설치·가입·레시피 저장 및 재방문 측정은 아직 연동하지 않음.
- 첫 시험 업로드의 기본 공개 설정은 `private`. 앱에서는 실제 공개와 구분해 **업로드 완료**라고 표시.
- AI 호출은 전체 계정 합산 최근 24시간 최대 5회. 실패한 호출도 한도에 포함.
- 사용자에게 관리자 권한을 주는 `profiles.role`에 의존하지 않고 별도 allowlist 사용.
- 채널 ID가 인증된 채널과 일치해야 업로드. 중단된 업로드는 자동 재전송하지 않음.

ChatGPT 홍보 초안 자동화도 월·수·금 오전(한국 시간)으로 설정됨. 이것은 사용자에게 검토할 문구를 전달하는 별도 작업이며 앱 DB 저장이나 YouTube 게시를 수행하지 않음. 앱의 `AI 홍보 초안 생성`은 관리자가 누르는 작업이다.

## 운영 연결 순서

1. PR의 Flutter 및 Marketing Quality 검사를 통과시키고 변경사항을 main에 반영.
2. 기존 `Apply Supabase Migrations` 워크플로를 실행하기 전에 대기 중인 모든 migration을 확인. 이 작업은 모든 대기 migration을 적용하므로 0027만 있다고 가정하지 말 것. 기존 실행 기록과 DB migration 목록을 대조하고 백업 확인.
3. Supabase Dashboard → Authentication → Users에서 운영자의 UUID 확인. SQL Editor에서 아래 템플릿의 UUID를 본인 UUID로 대체해 실행:

   ```sql
   insert into public.marketing_admins(user_id)
   values ('운영자-사용자-UUID') on conflict do nothing;
   ```

   UUID는 클라이언트가 보내는 값을 신뢰해 자동 등록하지 않음. 접근 취소는 해당 행 삭제.

4. Supabase Edge Functions Secrets에서 `OPENAI_API_KEY`, `OPENAI_MARKETING_MODEL` 설정. 기존 레시피 AI 모델은 변경하지 않음. 마케팅 모델은 해당 API 프로젝트에서 사용할 수 있는 JSON 응답 지원 모델로 지정.
5. GitHub Actions의 `Deploy Marketing Function`을 수동 실행하거나 해당 Supabase 프로젝트에서 아래 함수만 배포:

   ```text
   supabase functions deploy marketing_generate --project-ref dfczeudklykypysiseck
   ```

6. 앱 변경사항을 내부 테스트 배포하여 관리자 계정으로 초안 생성·취소·예약 승인 확인. 앱 버전 및 서명 설정은 이번 변경에서 조정하지 않음.
7. Google Cloud Console → APIs & Services에서 YouTube Data API v3 활성화. Google Auth Platform에서 OAuth 동의 화면 및 클라이언트 설정. 앱 로그인 OAuth와 별도 마케팅 클라이언트 사용 권장.
8. 공식 OAuth 절차로 채널 소유자의 오프라인 동의 및 refresh token 취득. 필요한 scope는 `https://www.googleapis.com/auth/youtube.upload`, `https://www.googleapis.com/auth/youtube.readonly`. OAuth Playground 사용 시 자신의 OAuth 클라이언트를 지정하고 승인된 redirect URI에 `https://developers.google.com/oauthplayground` 등록. 반드시 올릴 채널 계정으로 동의. 토큰 및 키는 채팅·스크린샷에 공유하지 않고 아래 Secret 입력란에 직접 등록.
9. GitHub 저장소 → Settings → Secrets and variables → Actions에서 다음 값을 설정:

   | 종류 | 이름 | 값의 용도 |
   |---|---|---|
   | Secret | `MARKETING_SUPABASE_URL` | 실제 운영 Supabase URL |
   | Secret | `MARKETING_SUPABASE_SERVICE_ROLE_KEY` | 서버 전용 service role key |
   | Secret | `MARKETING_YOUTUBE_CLIENT_ID` | 마케팅 OAuth 클라이언트 ID |
   | Secret | `MARKETING_YOUTUBE_CLIENT_SECRET` | 마케팅 OAuth 클라이언트 secret |
   | Secret | `MARKETING_YOUTUBE_REFRESH_TOKEN` | 채널의 OAuth refresh token |
   | Variable | `MARKETING_YOUTUBE_CHANNEL_ID` | `UC…` 형식 채널 ID |
   | Variable | `MARKETING_PRIVACY` | 처음에는 `private` |
   | Variable | `MARKETING_ENABLED` | 설정 완료 후 `true` |

10. 채널 프로필에 Play Store 앱 링크를 등록. Shorts 설명과 댓글 URL은 클릭되지 않으므로 프로필 링크를 안내. 설명의 캠페인 referrer 링크는 참고 링크이며 조회수를 클릭·설치로 환산하지 않음. 채널 공용 프로필 링크는 게시물별 정확한 유입을 구분하지 못함.
11. 초안 한 개 승인 → 예약 시간이 지난 뒤 `Recipe Scout Marketing` workflow를 수동 실행 → 비공개 영상의 한글·3개 장면·내용 및 연결 채널 확인. 공개 설정은 YouTube API 프로젝트 감사/검증 상태를 확인한 뒤 조정.

## 장애와 중단

- 즉시 중단: GitHub Variable `MARKETING_ENABLED=false`. 아직 claim되지 않은 예약은 앱에서 취소 가능.
- `failed`: 파일 제작 또는 업로드 시작 전 실패. 설정 확인 후 새로운 초안으로 재승인.
- `needs_review`: 전송 또는 DB 저장 결과가 불명확함. **YouTube Studio에서 기존 영상 유무를 먼저 확인**. 자동 재시도하지 않음.
- `publishing` 상태가 30분 이상 남으면 다음 실행에서 `needs_review`로 전환. 채널 인증이 실패하면 운영자가 직접 점검 필요.
- 비공개 영상 제한은 OAuth 동의 화면 검증과 별도로 API 프로젝트 감사가 필요할 수 있음.
- 일반 사용자에게 관리자 등록이나 예약 RPC 실행권한을 확장하지 말 것. service role 키는 앱에 포함하지 않음.
- 예약 후 편집 기능은 없음. 승인한 텍스트는 일반 관리자 SQL 권한으로 직접 변경하지 말고 취소 후 새 초안 생성.

## 검증

```text
node --test tools/marketing/worker.test.mjs
deno check supabase/functions/marketing_generate/index.ts
MARKETING_PGLITE_PATH=/path/to/pglite/dist/index.js node tools/marketing/database.test.mjs
python tools/marketing/render_test.py
powershell -ExecutionPolicy Bypass -File tools/dev/verify.ps1
```

DB 검증은 임시 PGlite PostgreSQL에서 관리자 격리·직접 수정 거부·예약 검증·중복 claim 차단·중단 보류·하루 한도를 실행. 생산 DB 접속 없음.

## 다음 확장

- 관리자가 문구를 수정하면 승인 상태를 취소하는 버전 기반 편집.
- 실제 영상 미리보기, 내레이션, 앱 화면 녹화 기반 설명 영상.
- 채널 프로필용 캠페인 landing page 및 실제 클릭 측정.
- Android Install Referrer와 앱 분석 이벤트를 통한 설치·첫 저장·재방문 연결.
- 승인 처리에서 예산·공개 정책을 캠페인별로 기록.
- 설치·활성화 성과에 기반한 콘텐츠 추천. 현재 조회·좋아요만으로 이를 자동 판단하지 않음.

## 공식 참고

- https://developers.google.com/youtube/v3/docs/videos/insert
- https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol
- https://developers.google.com/identity/protocols/oauth2/web-server#offline
- https://support.google.com/youtube/answer/13748639
