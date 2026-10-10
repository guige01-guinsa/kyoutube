# v56 출시 기록

2026-09-13, 1.0.1+56, com.kyoutube.app.

- 원가 항목 추가/수정/삭제, 재료 단가 바로 수정.
- 원가에 0~100%를 가산한 판매가 자동 계산.
- 판매 수량·날짜 기록과 일/주/월 매출액·예상 이익, 과거 원가·판매가 보존.
- 무료/유료 권한 분리는 이번 버전에 포함되지 않는다.

## 배포와 검증

사용자가 DB 변경 0038·0039와 v56 서명 AAB 생성을 명시적으로 승인했다. 같은 저장소의 ‘이어서 작업 진행’ 작업에서 완료된 AAB를 덮어쓰지 않고 검증했다.

- 운영 DB: 0037 전제 확인 → 로컬 SQL 계약 통과 → 0038/0039 및 이력을 원자적으로 적용 → RLS 및 RPC 권한 확인.
- DB 검증: 소유자 정책 3개, 익명 조회/기록/집계 불가, 직접 INSERT 불가, 금액/소유자 직접 수정 불가, 날짜/수량 수정 가능, 구버전 덮어쓰기 차단.
- release/build-v56.log: analyze 지적 없음, Flutter 204개 통과·캡처 테스트 4개 기본 생략, 릴리스 빌드 성공.
- jarsigner 검증 통과. 자체 서명 인증서/타임스탬프 관련 경고는 기존 업로드 키 방식과 동일하며 v55 서명 일치를 확인했다.
- ZIP CRC, 생성 manifest 버전/패키지/디버그 설정, SHA-256/provenance 검증 통과.
- Flutter doctor의 PATH/Android/Windows 개발 도구 경고는 남아 있다. Android AAB 빌드는 성공했다.

파일: release/recipe-scout-v56.aab (65,633,974 bytes)

SHA-256: 08AEDB774C54CCB353F2045ECFDCD5607E2A2D4A39BDB570AF54C582058C7EF5

증거: release/verify-v56.json, release/recipe-scout-v56.aab.provenance.json,
.artifacts/v56-chef-contract.log, .artifacts/v56-production-verification.json.

운영 테스트용 판매 데이터는 만들지 않았다. Play 업로드·휴대폰 설치는 수행하지 않았다. 0036 운영 관측과 신규 관리자 알림은 이 배포 범위에 포함되지 않는다. 영어 초안 성공률 90%와 조리 정확도는 별도 표본 검증이 필요하다.
