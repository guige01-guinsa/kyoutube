# Week 1 User-Value Implementation Spec

Last update: 2026-07-22

## 1. Goal

This spec defines a one-week execution slice focused on user-perceived value improvement.

Targets:
1. Shorten time-to-value for first-time users.
2. Improve practical usefulness of AI outputs through guided regeneration.
3. Make cooking session entry and unstable-network behavior feel reliable.
4. Improve account trust cues before Google Play rollout.

## 2. Scope (Plan 1~3)

1. Day 1-2: Onboarding + AI regeneration reason selector.
2. Day 3-4: Quick cook mode + network fallback UX.
3. Day 5: Account connection guidance + trust package + 5-user test.

Out of scope:
1. Full i18n pipeline.
2. New payment/commerce features.
3. New external identity provider integration beyond current Google/Kakao wiring.

## 3. Success Metrics

1. Onboarding completion rate: >= 70% (first launch sessions).
2. AI helpful feedback rate: +10pp from baseline over 7 days.
3. AI degraded response rate: -20% relative over 7 days.
4. Recipe detail bounce (open then back within 10s): -15%.
5. Quick cook mode usage among detail viewers: >= 35%.
6. Network error recovery success (retry to success within 2 tries): >= 80%.

## 4. Milestone Plan

## Day 1-2: Onboarding + AI regeneration reason

Deliverables:
1. First-run onboarding flow (3 lightweight slides + skip + done).
2. Guest-visible core value path before forced login.
3. AI card action "다시 생성" with reason selector.
4. Reason-aware regenerate call path and logging.

Design:
1. Add route: /onboarding.
2. Launch rule:
- If first-run flag absent, open onboarding first.
- Store flag in SharedPreferences key: app.onboarding_completed_v1.
3. Onboarding CTA:
- Primary: "바로 시작".
- Secondary: "건너뛰기".
4. AI regenerate UI:
- Trigger on recipe detail AI card.
- Bottom sheet reasons:
- too_short, too_long, need_more_steps, need_safety_tips, tone_not_clear.
5. AI request contract extension:
- action: summarize|regenerate.
- regenerate_reason: nullable string.
- previous_summary: nullable string.
6. Analytics/logging:
- Reuse ai_usage_logs.meta and add fields:
- action_type, regenerate_reason, regenerate_attempt, user_feedback_context.

Technical components:
1. Flutter:
- lib/features/onboarding/presentation/onboarding_page.dart
- lib/features/onboarding/application/onboarding_state.dart
- lib/features/recipes/presentation/recipe_detail_page.dart (AI card actions)
2. Backend:
- supabase/functions/ai_recipe_assistant/index.ts
- optional migration: add feedback meta fields if strict schema needed.

## Day 3-4: Quick cook mode + network fallback UX

Deliverables:
1. "바로 요리 시작" sticky CTA in recipe detail.
2. Cook mode optimized layout (large step card, next/prev, auto advance toggle).
3. Network state-aware fallback for recipe list/detail.
4. Retry and last-success cache behavior.

Design:
1. Quick cook mode entry points:
- Recipe detail top CTA.
- AI summary card CTA "이 요약으로 요리 시작".
2. Cook mode UX:
- Focus mode with one-step-at-a-time card.
- Keep screen awake while in mode.
- Exit confirm if session started.
3. Network fallback:
- On list/detail fetch fail:
- show clear offline state card.
- show Retry button.
- if cache exists, show "마지막으로 본 데이터" with timestamp badge.
4. Cache policy:
- recipe list query cache TTL: 10 min.
- recipe detail cache TTL: 24 h.
- stale-but-usable allowed for offline read-only.

Technical components:
1. Flutter:
- lib/features/cooking/presentation/quick_cook_page.dart
- lib/features/recipes/application/recipe_repository.dart (cache + fallback path)
- lib/core/widgets/network_state_banner.dart
2. Storage:
- SharedPreferences or lightweight local file cache (json serialized).
3. Observability:
- ops monitor event types for network fallback and retry success.

## Day 5: Account connection guidance + trust package + 5-user test

Deliverables:
1. Account trust card on profile and post-login transition.
2. Clear provider connection benefit messaging.
3. In-app trust package links and data use summary.
4. 5-user moderated scenario test and action list.

Design:
1. Profile trust card:
- State: connected / partially connected / not connected.
- Message example:
- "소셜 계정 연결 시 기기 변경 후 레시피 복구가 쉬워집니다."
2. Post-login nudge:
- one-time prompt after first successful login.
- dismiss persists (key: account.link_nudge_dismissed_v1).
3. Trust package section:
- privacy policy, terms, data safety summary links.
- permission rationale (notification requested only at need point).
4. 5-user test protocol:
- tasks:
- first-run discover AI summary.
- regenerate with reason.
- start quick cook mode.
- recover from forced offline.
- verify profile connection understanding.
- collect SUS-lite score and friction notes.

Technical components:
1. Flutter:
- lib/features/auth/presentation/profile_page.dart (trust card)
- lib/features/auth/presentation/login_page.dart (post-login nudge)
- lib/core/widgets/trust_links_section.dart
2. Docs:
- docs/ops-execution-record-template.md (add UX test appendix)
- docs/work-log-2026-07-22.md or next-day log for findings.

## 5. Data and API Design

## 5.1 AI function contract

Request:
1. action: summarize|regenerate|feedback
2. title, recipeText, ingredients, steps
3. regenerate_reason (optional)
4. previous_summary (optional)

Response:
1. status: ok|error
2. data.summary, data.tips, data.cautions
3. data.degraded, data.errorCode
4. data.generationHint (optional short hint for UI)

Logging meta example:
1. action_type: regenerate
2. regenerate_reason: need_more_steps
3. previous_summary_len: 142
4. fallback_used: true|false

## 5.2 Optional migration

If strict queryability is needed for reasons:
1. Add columns to public.ai_assistant_feedback:
- action_type text default 'feedback'
- reason_code text
- session_id text
2. Keep RLS owner-only read/insert policy.

## 6. QA Plan

1. Static checks:
- flutter analyze lib/
2. Functional checks:
- onboarding first-run and skip path.
- AI regenerate reasons each once.
- quick cook mode enter/exit and auto-advance.
- offline fallback for list/detail with airplane mode.
- account guidance visibility and dismissal persistence.
3. Regression checks:
- login/logout/profile edit.
- existing AI summarize + feedback path.
4. Evidence:
- screenshots and ops report snapshots.
- short result section appended to daily work log.

## 7. Risk and Mitigation

1. Risk: extra UI complexity lowers clarity.
- Mitigation: keep one primary CTA per section.
2. Risk: regenerate calls increase cost.
- Mitigation: cap regenerate attempts per recipe/session and log guardrails.
3. Risk: stale cache confusion.
- Mitigation: always show cache timestamp and "최신 아님" badge.
4. Risk: OAuth reconnect confusion.
- Mitigation: consistent provider status labels and one-time tooltip.

## 8. Definition of Done

1. Code merged and flutter analyze green.
2. All three milestones implemented behind stable UX.
3. At least 5-user test completed with prioritized issue list.
4. Metrics dashboard can show helpful rate and degraded trend delta vs baseline.
5. Docs updated:
- week spec
- phase plan progress note
- daily work log evidence section.
