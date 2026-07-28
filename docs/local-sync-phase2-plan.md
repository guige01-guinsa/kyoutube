# 로컬 데이터 계정 동기화 2차 설계

## 목표
- 현재 로컬 우선 구조를 유지하면서, 나중에 계정 로그인 추가 시 사용자 데이터 동기화를 안전하게 연결한다.
- 기존 구조를 깨지 않고 점진적으로 전환한다.

## 현재 기준
- 개인 레시피/북마크는 로컬 저장소(SharedPreferences)에 저장.
- 백업/복원 JSON 포맷은 `schema_version` 기반.
- 동기화 부트스트랩 페이로드는 `LocalRecipeBackupService.buildSyncBootstrapPayload()`로 생성.

## 설계 원칙
1. 로컬 우선: 로그인 전에는 항상 로컬 데이터가 단일 진실 소스.
2. 지연 동기화: 로그인 이후에만 동기화 시도.
3. 병합 안전성: 서버 데이터가 있어도 로컬 데이터 유실 금지.
4. 가시성: 병합 결과(생성/갱신/충돌 수) 사용자에게 요약 표시.
5. 중단 복구: 동기화 중 실패해도 로컬 데이터는 그대로 유지.

## 데이터 모델
- 로컬 레시피: `id`, `title`, `summary`, `ingredients`, `steps`, `notes`, `imageUrl`, `youtubeUrl`, `visibility`
- 동기화 메타(추가 예정):
  - `origin`: `local` | `remote`
  - `updatedAt`: ISO-8601
  - `syncState`: `pending` | `synced` | `conflict`
  - `remoteId`: 서버 반영 후 매핑 ID

## 단계별 구현 계획
1. Phase 2-A: 준비
- 서버 테이블(예: `recipes_user_sync`)에 최소 필드와 업서트 정책 구성.
- 로컬 모델에 `updatedAt`, `syncState` 메타 필드 확장.

2. Phase 2-B: 로그인 후 1회 부트스트랩
- `buildSyncBootstrapPayload()`로 로컬 스냅샷 업로드.
- 서버에서 병합 결과 리턴: `created`, `updated`, `conflicts`.
- 앱은 결과를 저장하고 화면에 요약 표시.

3. Phase 2-C: 증분 동기화
- 로컬 변경 발생 시 `syncState=pending`으로 표시.
- 백그라운드/수동 동기화 트리거로 pending만 전송.
- 성공 시 `synced` 갱신.

4. Phase 2-D: 충돌 해결
- 기준 정책: 기본은 최신 수정 우선(last-write-wins).
- 중요 충돌(같은 레시피 동시 수정)은 사용자 선택 UI 제공.

## API 권장
- `POST /sync/bootstrap`
  - 입력: 로컬 전체 스냅샷
  - 출력: 병합 결과 + 서버 기준 최신 목록(선택)
- `POST /sync/delta`
  - 입력: pending 변경셋
  - 출력: 성공/실패 항목
- `GET /sync/status`
  - 출력: 마지막 동기화 시각, pending 수, conflict 수

## 실패/복구 전략
- 네트워크 실패: 재시도 큐 유지, 로컬 사용 계속.
- 서버 오류: 사용자는 로컬 데이터 계속 사용 가능.
- 부분 성공: 성공 항목만 synced로 전환, 실패 항목 유지.

## 품질 게이트
- analyze/test 통과.
- 로그인 없이 기존 로컬 CRUD 100% 동작.
- 동기화 실패 시 데이터 손실 0건.
- 부트스트랩/증분/충돌 시나리오 수동 테스트 체크리스트 완료.

## 출시 순서
1. 로컬 기능 안정화(현재 단계)
2. 숨김 플래그로 동기화 베타
3. 내부 트랙 검증
4. 점진 롤아웃

## 내부 베타 토글 사용법
- 기본값: 비활성 (`LOCAL_SYNC_BETA_ENABLED=false`)
- 내부 테스트 빌드에서만 활성화:
  - 실행 예시: `flutter run --dart-define=LOCAL_SYNC_BETA_ENABLED=true`
  - 릴리스 예시: `flutter build apk --release --dart-define=LOCAL_SYNC_BETA_ENABLED=true`
- 활성화 시 `내 요리 노트` 메뉴에 아래 항목이 추가됨:
  - `동기화 베타 프리뷰 실행`
  - `동기화 베타 상태 보기`
