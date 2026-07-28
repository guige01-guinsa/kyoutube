# 내 레시피 승격 UX/실패 처리 설계 (2026-07-26)

## 목표
- 사용자가 `복사 승격`과 `이동 승격`의 차이를 즉시 이해하도록 안내를 강화한다.
- 현재 발생 중인 승격 실패를 구조적으로 해소한다.
- 실패 시 원인을 사용자 언어로 설명하고 다음 행동(로그인/재시도)을 제시한다.

## 문제 요약
- 개인 레시피 상세의 승격 다이얼로그에는 짧은 문구만 있어, 데이터 보존/삭제 범위가 직관적이지 않다.
- 저장소 계층(`LocalFirstRecipeRepository`)에서 승격 메서드가 `UnsupportedError`로 미구현 상태여서 승격이 항상 실패한다.
- 실패 메시지가 기술 오류 문자열 중심이라 사용자가 해결 행동을 알기 어렵다.

## 사용자 경험 설계
### 1) 승격 방식 안내(다이얼로그)
- 제목 아래에 `승격 방식 안내` 블록을 노출한다.
- `복사 승격`: 개인 레시피는 그대로 남고, 크리에이터 레시피가 추가 생성됨.
- `이동 승격`: 개인 레시피를 크리에이터로 옮기며, 개인 레시피는 삭제됨.
- 현재 선택된 모드의 효과를 한 줄로 재강조한다.

### 2) 실패 메시지 정책
- 로그인/세션 문제: `로그인이 필요합니다. 다시 로그인 후 승격해 주세요.`
- 네트워크 문제: `네트워크 연결을 확인한 뒤 다시 시도해 주세요.`
- 정책/미구현 문제: `현재 환경에서는 승격을 처리할 수 없습니다.`
- 그 외: `승격에 실패했습니다. 잠시 후 다시 시도해 주세요.`

## 기술 설계
### 1) 로컬 퍼스트 승격 구현
대상: `LocalFirstRecipeRepository.promoteSubscriberRecipeToCreator`
- 개인 레시피 목록에서 원본 레시피를 찾는다.
- 선택 옵션을 반영해 생성 payload를 구성한다.
  - summary: includeSummary=true일 때만 전달
  - youtubeUrl: includeYoutubeUrl=true일 때만 전달
  - imagePath: includeImageUrl=true일 때만 전달 (`imageUrl` 재사용)
  - tips: includeNotesAsTips=true일 때만 notes 전달
- `_remote.createCreatorRecipe(...)`를 호출해 크리에이터 레시피를 생성한다.
- `deleteSource=true`면 개인 레시피를 로컬에서 삭제하고, 북마크에 `user:{id}`가 있으면 정리한다.

### 2) UI 오류 매핑
대상: `SubscriberRecipeDetailPage`
- `_isSessionProblem`, `_isNetworkProblem`, `_friendlyPromotionError` 헬퍼를 추가한다.
- `catch`에서 raw 오류 대신 정책 메시지를 사용한다.

## 검증 계획
- 정적 분석: 승격 관련 파일 analyze 통과.
- 수동 시나리오
  1. 복사 승격 성공: 개인 레시피 유지 + 크리에이터 상세 이동
  2. 이동 승격 성공: 개인 레시피 삭제 + 크리에이터 상세 이동
  3. 로그아웃 상태 승격: 로그인 필요 메시지 노출
  4. 네트워크 차단 상태 승격: 네트워크 안내 메시지 노출
