# YouTube 검색 통합 MVP 구현안

Last update: 2026-07-26

## 목표
- 기존 공공레시피 검색 흐름을 유지하면서 YouTube 검색 소스를 보조로 추가한다.
- 사용자가 YouTube 결과를 내 레시피로 가져오는 전환을 측정한다.
- 실패 시 앱 핵심 기능(공공레시피 검색)은 영향을 받지 않도록 설계한다.

## 범위 (MVP)
- 검색 화면에 소스 탭 추가: 공공레시피 | YouTube
- YouTube 검색은 상위 3~5개 결과만 표시
- 결과 카드에서 2개 액션 제공
  - 외부 열기
  - 내 레시피로 가져오기
- 가져오기 시 저장 대상
  - youtubeUrl
  - title (영상 제목 기본값)
  - summary (빈값 허용)
  - ingredients/steps (빈값 또는 템플릿)
- 기존 YouTube 메타데이터 카드/오버라이드와 자연스럽게 연결

## 비범위 (MVP 제외)
- 앱 내 YouTube 플레이어 내장
- 영상 자막 파싱 자동 레시피화
- 대규모 랭킹/추천 모델

## 서버 설계

### 1) Edge Function: youtube_search
- 위치: supabase/functions/youtube_search/index.ts
- 목적: YouTube Data API 호출을 서버에서 대리 수행하고 결과를 앱 친화 DTO로 정규화

### 2) 요청 스키마
- Method: GET
- Path: /functions/v1/youtube_search
- Query
  - q: string (필수, 1~80자)
  - limit: number (선택, 기본 5, 최대 10)
  - hl: string (선택, 기본 ko)
  - regionCode: string (선택, 기본 KR)

### 3) 성공 응답 스키마
- status: ok
- data
  - query: string
  - total: number
  - items: array
    - videoId: string
    - title: string
    - channelTitle: string
    - publishedAt: string (ISO-8601)
    - thumbnailUrl: string
    - youtubeUrl: string
    - durationSec: number | null

### 4) 실패 응답 스키마
- status: error
- errorCode: string
  - invalid_query
  - quota_exceeded
  - upstream_timeout
  - upstream_error
  - internal_error
- message: string

### 5) 서버 가드레일
- API 키는 Edge Function 환경 변수로만 관리
- q 길이 제한, limit 상한 제한
- 응답 캐시 권장: 60~180초
- 동일 쿼리 burst 완화
- 장애 시 4xx/5xx를 명확한 errorCode로 표준화

## Flutter 설계

### 1) 도메인 모델
- 파일: lib/features/recipes/domain/youtube_search_result.dart
- 필드
  - videoId
  - title
  - channelTitle
  - publishedAt
  - thumbnailUrl
  - youtubeUrl
  - durationSec

### 2) 데이터 레이어
- 파일: lib/features/recipes/data/youtube_search_service.dart
- 책임
  - Edge Function 호출
  - 응답 DTO 파싱
  - 에러코드 매핑

### 3) 상태 관리 (Riverpod)
- 파일: lib/features/recipes/application/youtube_search_providers.dart
- 제안 Provider
  - youtubeSearchQueryProvider (StateProvider<String>)
  - youtubeSearchLimitProvider (StateProvider<int>)
  - youtubeSearchResultsProvider (FutureProvider.family<List<YoutubeSearchResult>, String>)
  - youtubeSearchLoadingStateProvider (필요 시)

### 4) 프레젠테이션
- 파일: lib/features/home/presentation/home_page.dart
- 변경
  - 검색 소스 선택 UI 추가 (공공레시피 | YouTube)
  - YouTube 소스 선택 시 카드 리스트 출력
  - 카드 액션
    - 외부 열기
    - 내 레시피로 가져오기

### 5) 가져오기 저장 정책
- 저장 경로: 기존 createSubscriberRecipe 활용
- 매핑 정책
  - title: YouTube 제목
  - summary: null (또는 짧은 자동 문구)
  - ingredients: 빈 리스트 템플릿 또는 사용자 입력 유도
  - steps: 빈 리스트 템플릿 또는 사용자 입력 유도
  - youtubeUrl: 필수 저장

## UX 흐름

### 1) 검색
1. 사용자가 검색어 입력
2. 소스 탭에서 YouTube 선택
3. 결과 3~5개 표시

### 2) 가져오기
1. 결과 카드에서 내 레시피로 가져오기
2. 즉시 저장 또는 편집 바텀시트 열기
3. 저장 후 내 요리 노트 상세로 이동

### 3) 실패 처리
- YouTube 요청 실패 시 안내 문구 노출
- 공공레시피 결과 탭은 항상 사용 가능

## 이벤트 측정 설계

### 1) 퍼널 이벤트
- search.submitted.youtube
- search.submitted.public
- youtube.search.success
- youtube.search.success.empty
- youtube.search.success.1_3
- youtube.search.success.4_10
- youtube.result.open.clicked
- youtube.result.open.success
- youtube.result.open.failed
- youtube.result.open.invalid_url
- youtube.import.clicked
- youtube.import.canceled
- youtube.import.completed
- youtube.import.failed

### 2) 품질 이벤트
- youtube.search.failed.{error_code}
- youtube_metadata_sync_success
- youtube_metadata_sync_failed
  - error_code

### 3) 에러 코드 사용자 메시지 표준
- invalid_query: 검색어를 다시 확인해 주세요.
- quota_exceeded: YouTube 검색 사용량 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.
- upstream_timeout: YouTube 응답이 지연되고 있습니다. 다시 시도해 주세요.
- upstream_error: YouTube 검색 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.
- invalid_response: 검색 응답 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.
- misconfigured: 검색 기능 설정이 올바르지 않습니다. 관리자에게 문의해 주세요.
- internal_error: 검색 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.

## 1주 실행 체크리스트

### Day 1
- Edge Function youtube_search 뼈대 생성
- YouTube API 연동 및 최소 응답 DTO 확정
- 로컬/스테이징 환경변수 구성

### Day 2
- Flutter YouTubeSearchResult 모델/서비스 구현
- Provider 연결
- 실패 코드 매핑

### Day 3
- Home 검색 UI에 소스 탭/결과 카드 추가
- 외부 열기 액션 연결

### Day 4
- 내 레시피 가져오기 연결
- 저장 후 상세 이동 UX 정리

### Day 5
- 이벤트 로깅 추가
- 에러/빈결과/로딩 상태 문구 정리
- smoke 수동 테스트

### Day 6
- flutter analyze / flutter test
- 로컬 실기기 점검

## 진행 현황 (2026-07-26)
- Day 1~4 구현 완료.
- Day 5 구현 완료: 이벤트 로깅 및 에러 메시지 표준화 반영.
- Day 6 일부 완료: `flutter analyze` 통과, 관련 테스트 통과.
- Day 6 잔여: 실기기 수동 스모크(YouTube 검색/열기/가져오기 + 이벤트 카운터 증가 확인).

### Day 7
- 내부 트랙 실험 빌드
- KPI 수집 시작

## 수용 기준 (MVP Done)
- 공공레시피 검색 회귀 없음
- YouTube 탭 결과 노출/외부열기/가져오기 정상
- 가져온 레시피에 youtubeUrl 저장 확인
- 에러코드 기반 사용자 메시지 노출 확인
- analyze/test 통과

## 리스크와 대응
- 쿼터 소진: limit 축소, 캐시 강화, 실험 트래픽 제한
- 품질 편차: 기본 필터 강화, 상위 결과 수 제한
- 정책 리스크: API 키 서버 관리, 약관 준수 검토

## 권장 롤아웃
1. 내부 플래그로 팀 검증
2. 내부 트랙 제한 실험 (10~20%)
3. KPI 확인 후 전체 공개 여부 결정