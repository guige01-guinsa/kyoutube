# Engineering roadmap

Priorities reflect the current repository only; they are not commitments for unimplemented product features.

## P0 — security, data loss, and execution blockers

| Item | Evidence/current state | Goal and done condition | Verification |
| --- | --- | --- | --- |
| Rotate potentially exposed root environment credentials | Root `.env` was previously tracked; `docs/SECURITY_ROTATION.md` lists variable names only. | Owners rotate applicable credentials and revoke old ones; no secret files remain tracked. | Secret-owner record; `git ls-files .env` is empty. |
| Preserve database safety gates | `supabase/migrations/` contains ordered migrations and a manual push workflow. | Database reset/push remains explicit approval-only; future schema edits use new migrations. | PR review and migration filename check. |

## P1 — tests, stability, CI, authentication, and errors

| Item | Evidence/current state | Goal and done condition | Verification |
| --- | --- | --- | --- |
| Expand Flutter test coverage | Only `test/widget_test.dart` and `test/features/cooking/application/voice_guide_service_test.dart` are present. | Add focused tests for auth, recipe repository/provider, kitchen and route error states. | `flutter test` covers added behaviours. |
| Add Edge Function test harness | `recipe_api`, `ai_recipe_assistant`, and `public_recipe_sync` have `index.ts` only; no checked-in test/config harness was found. | Exercise request validation, auth/worker-secret rejection, public API failures, and upsert/error responses locally. | Deno/Supabase-local test command documented and run in CI when dependency setup is stable. |
| Replace AI placeholder safely | `supabase/functions/ai_recipe_assistant/index.ts` returns a placeholder summary. | Define server-side provider integration, limits, redaction, and error handling before enabling product AI output. | Local mocked tests and approved secret-backed integration test. |
| Harden public recipe synchronization | `public_recipe_sync` contains worker secret and service-role paths, but no automated tests. | Validate retry/error logging, API timeout handling, idempotency, and least-privileged scheduling path. | Local function tests plus non-production smoke test. |
| Reconcile local migration history | Local migration history contains `0008`–`0013`, while this checkout contains `0001`–`0007`. | Determine the provenance and schema impact before adding or changing any migration; do not reset a developer DB as remediation. | Read-only schema and migration-history comparison with an approved recovery plan. |
| Complete atomic kitchen flow adoption | Migrations `0014`–`0017` define owner-scoped idempotent RPC contracts, but the current Edge completion path still uses multiple REST calls and Flutter still exposes legacy checkbox semantics. | Phase 3 passes explicit `{name, ingredient_text, quantity, unit}` items only to the create RPC and routes completion through the single RPC. Phase 4 adds a review UI for free-form recipe strings, legacy-item review, quantity/unit confirmation, and pending/purchased/skipped/unavailable states. Never call create for unreviewed free-form input. | Local Edge and Flutter tests; local two-session idempotency smoke; no raw ingredient text used as an inventory key. |
| Keep quality gate green | New `.github/workflows/flutter-quality.yml` covers analysis/tests only. | All normal PRs run it without secrets. | GitHub Actions required-check configuration (repository setting). |

## P2 — architecture, performance, observability, maintenance

| Item | Evidence/current state | Goal and done condition | Verification |
| --- | --- | --- | --- |
| Document provider/repository contracts | Feature folders contain Riverpod providers and Supabase repositories. | Define testable interfaces and error-state conventions without changing product behaviour. | Architecture review and focused provider tests. |
| Improve observability boundaries | `OpsMonitorService` and runtime diagnostics exist; Edge Functions have basic HTTP errors. | Add privacy-safe structured errors and correlation conventions. | No secrets/PII in log review; error-path tests. |
| Stabilize toolchain maintenance | Flutter is pinned in `.fvmrc`; Android uses JDK 17. | Schedule controlled upgrades with compatibility matrix and CI verification. | Dedicated upgrade PR with analyze/test/build verification. |

## P3 — product improvement candidates

| Item | Evidence/current state | Goal and done condition | Verification |
| --- | --- | --- | --- |
| Evolve AI cooking assistance | The visible assistant function is a placeholder. | Product-approved recipe assistance with clear scope, safety, and cost limits. | UX acceptance criteria and provider-backed integration tests. |
| Improve public recipe discovery | Public recipe sync maps food API records into `recipes_public`. | Validate relevance, source freshness, and user-facing empty/error states. | Non-production data review and Flutter UI tests. |
| Evaluate Play Console automation | Existing release material is manual/internal-track oriented. | Decide whether automated upload is needed; if so, design least-privilege service account, protected environments, approvals, and artifact provenance. Do not implement in this cleanup. | Security/release-owner approval and isolated workflow proposal. |
