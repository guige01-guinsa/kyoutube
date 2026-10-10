# 레시피 스카우트 홍보 자동화

사무실 개발 브랜치는 `codex/office-development-v99`입니다. v99 기능 소스와 GitHub의 기존 홍보 기능을 통합했으며 이미지·폰트·웹 소스를 저장소에 직접 포함합니다. 이 브랜치에서는 Release ZIP 복원 단계가 필요하지 않습니다.

현재 운영 상태와 남은 확인 사항은 [홍보 기능 검토 결과](MARKETING_READINESS_REVIEW_KO.md)를 참고하세요. 과거 작업의 ‘일시 중지’ 기록과 달리 2026-10-10 현재 기본 브랜치의 worker는 활성화돼 있고 게시 범위는 비공개입니다. 생성 함수는 별도의 활성화 설정을 요구합니다.

홍보 관리자 목록과 AAL2 인증을 사용하는 관리자 화면에서 주제를 선택해 제목·설명·3개 장면을 생성하고 검토 후 예약 승인·취소할 수 있습니다. 하루 생성량은 최근 24시간 전체 5회이며 불확실한 업로드는 자동 재전송하지 않습니다.

검사 명령:

```text
node --test tools/marketing/worker.test.mjs
deno check supabase/functions/marketing_generate/index.ts
```

격리된 PGlite를 설치한 뒤 `MARKETING_PGLITE_PATH`에 해당 패키지의 `dist/index.js` 경로를 지정하면 `node tools/marketing/database.test.mjs`로 DB 권한·예약 동작을 검사할 수 있습니다. Python Pillow, ffmpeg, ffprobe와 한국어 폰트를 준비하면 `python tools/marketing/render_test.py`로 영상 제작을 검사할 수 있습니다. GitHub의 Marketing Quality는 이 검사들을 실행합니다.

운영 DB migration·Edge Function·웹·앱 배포와 공개 게시 활성화는 별도 승인 후 진행합니다. GitHub push 자체로 현재 운영 웹을 바꾸지 않습니다.
