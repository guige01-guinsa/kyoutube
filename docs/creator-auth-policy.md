# Creator API 인증 정책

최종 결정일: 2026-07-26

## 정책
- 비로그인(익명) 상태에서는 Creator 서버 저장을 허용하지 않는다.
- 비로그인 상태에서 허용되는 범위는 작성 화면의 로컬 초안 저장까지다.
- Creator API(`type=creator`)는 GET/POST/PATCH/DELETE 모두 인증 토큰이 필요하다.

## 근거
- 작성자 식별/수정 권한/삭제 권한 일관성 유지
- 악의적 대량 쓰기/스팸 작성 방지
- RLS 및 소유권 검증 로직 단순화

## 구현 반영
- Edge Function: `supabase/functions/recipe_api/index.ts`
  - 인증 토큰 누락 시 401 + `policy=local_draft_only` 상세 응답
- Flutter 작성 화면: `lib/features/recipes/presentation/create_creator_recipe_page.dart`
  - 비로그인 저장 시 서버 저장 대신 SharedPreferences 로컬 초안 저장
  - 정책 안내 배너 및 로컬 초안 저장/삭제 버튼 제공
