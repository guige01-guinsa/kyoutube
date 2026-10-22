# 레시피 스카우트 홍보 자동화

사무실 개발 브랜치는 `codex/office-development-v99`입니다. v99 기능 소스와 GitHub의 기존 홍보 기능을 통합했으며 이미지·폰트·웹 소스를 저장소에 직접 포함합니다. 이 브랜치에서는 Release ZIP 복원 단계가 필요하지 않습니다.

현재 운영 상태와 남은 확인 사항은 [홍보 기능 검토 결과](MARKETING_READINESS_REVIEW_KO.md)를 참고하세요. 과거 작업의 ‘일시 중지’ 기록과 달리 2026-10-10 현재 기본 브랜치의 worker는 활성화돼 있고 게시 범위는 비공개입니다. 생성 함수는 별도의 활성화 설정을 요구합니다.

홍보 관리자 목록과 AAL2 인증을 사용하는 관리자 화면에서 주제를 선택해 제목·설명·3개 장면을 생성하고 검토 후 예약 승인·취소할 수 있습니다. 하루 생성량은 최근 24시간 전체 5회이며 불확실한 업로드는 자동 재전송하지 않습니다.

검사 명령:

```text
node --test tools/marketing/worker.test.mjs
deno check supabase/functions/marketing_generate/index.ts
```

격리된 PGlite를 설치한 뒤 `MARKETING_PGLITE_PATH`에 해당 패키지의 `dist/index.js` 경로를 지정하면 `node tools/marketing/database.test.mjs`로 DB 권한·예약 동작을 검사할 수 있습니다. `tools/marketing/requirements.txt`의 고정 Python 패키지를 설치하고, 포함된 ffmpeg를 PATH에 연결한 뒤 `MARKETING_FONT`를 저장소의 `assets/fonts/NanumGothic-Regular.ttf`로 지정하면 `python tools/marketing/render_test.py`로 영상 제작을 검사할 수 있습니다. 별도 ffprobe나 시스템 폰트 다운로드는 필요하지 않습니다. 검사는 H.264, 720×1280, yuv420p, 24fps, 24초 및 실제 576프레임을 확인합니다. GitHub의 Marketing Quality는 같은 설치 방식으로 검사합니다.

## 영상 준비 시간과 안전한 속도 시험

- 영상 작업은 고정 버전의 Pillow·imageio-ffmpeg 바이너리 패키지와 저장소 한글 폰트만 사용합니다.
  pip 다운로드 캐시는 requirements 파일에 맞춰 재사용하며 설치는 5분, 사전 영상 검사는 3분으로 제한합니다.
- GitHub `Recipe Scout Marketing` 작업을 수동 실행할 때 `dry_run`은 기본값이 `true`입니다.
  이 모드는 설치와 실제 24초 영상 검사만 수행하고, 업로드 단계와 해당 단계의 비밀정보 접근은 건너뜁니다.
  따라서 새 캠페인, YouTube 업로드, 생성 한도 소모 없이 준비 시간을 측정할 수 있습니다.
- 승인된 예약 영상의 수동 업로드가 필요한 경우에만 명시적으로 `dry_run=false`를 선택합니다.
  실행 전에 대상 채널·비공개 설정·예약 대기열을 확인해야 합니다. 예약 작업은 기존 방식대로 동작합니다.
- 정기 실행 간격(약 1시간), 최소 5분 예약 규칙, 비공개 설정, 관리자 인증 및 중복 방지는 변경하지 않습니다.
  설치 속도 개선은 예약부터 업로드까지의 대기 시간을 없애는 변경이 아닙니다.

운영 DB migration·Edge Function·웹·앱 배포와 공개 게시 활성화는 별도 승인 후 진행합니다. GitHub push 자체로 현재 운영 웹을 바꾸지 않습니다.
