# 운영 관측 변경 검증 기록

일자: 2026-09-12. 대상: v53 이후 운영 관측 소스. 운영 배포·신규 AAB 생성은 수행하지 않았다.

| 검사 | 결과 | 증거/범위 |
| --- | --- | --- |
| Flutter analyze | 오류·지적 없음 | `.artifacts/operations-verify.log` |
| Flutter test | 172개 통과 | 전체 회귀, 신규 분류/비용 모델/한·영 화면 테스트 포함 |
| 작은 화면·접근성 글자 | 통과 | 한·영 각각 320px 및 200% 글자, 비용 입력 검증·조회 실패 복구 |
| Deno 회귀 | 42개 통과 | AI YouTube 26, YouTube 검색 8·클라이언트 3, 신규 관측 5 |
| Deno check | 7개 진입점 통과 | `.artifacts/operations-deno-check.log` |
| SQL 계약 | 통과 | `.artifacts/operations-sql-test.log`, 일회용 로컬 PostgreSQL DB |
| 보관 스크립트 | 모의 응답 4종 통과 | 0건 성공·전송 실패·잘못된 응답·배치 상한에서 종료 코드 검증. 실제 서버 호출 없음 |
| 기존 v53 AAB | 해시 유지 | `08B77FB4702A975B7006E67F5F791F6510B6CB14D7E3BC0D7C730B4C5ADB5332` |

SQL은 실제 anon/authenticated/service_role 역할로 관리자 접근 제한, 직접 테이블 읽기 차단, 허용 목록·시간당 제한, AI 성공률 분모, 실패 토큰 포함 집계, 비용 미입력/0/음수/NaN, 비용 감사 기록, 90일 정리와 계정 삭제 연계를 검증했다. 최소 기존 스키마 fixture를 사용했으며 전체 운영 마이그레이션의 재현은 아니다. 일회용 DB는 검사 후 삭제했다.

`flutter doctor`에는 PATH의 전역 SDK, Android 라이선스 상태 확인 불가, Windows Visual Studio 설치 관련 환경 경고가 남는다. 검증은 명시적인 고정 Flutter 3.44.8 및 JDK 17로 실행했다. 이 경고를 숨기거나 SDK/라이선스/설정을 변경하지 않았다.

Play 결제·FCM·운영 연결·공개 정책 페이지 게시·실기기 설치 검증은 이번 로컬 결과에 포함되지 않는다. 90일 정리 스크립트는 준비했으나 매일 실행 작업은 아직 등록하지 않았다. 자동 청구 연동·외부 알림·지출 차단은 구현 범위에 포함되지 않는다.

배포 절차는 [운영 안내서](OPERATIONS_RUNBOOK.md)를 따른다. 운영 DB 0036·7개 함수 적용, 보관 정리 등록, 공개 수집 안내 반영, 53보다 큰 신규 앱 버전 배포가 필요하다.
