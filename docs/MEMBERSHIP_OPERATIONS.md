# 새 출시 요금제

현재 운영 기준은 [v63 배포 기록](release-v63.md)과 [출시 전 새 요금제](launch-billing-implementation.md)입니다. DB 0054–0056, 함수 3개와 새 서명 AAB 적용을 완료했고 실제 Play 결제는 설정·검증 전까지 비활성입니다. 아래 이전 월간 프리미엄·연간 베이직 관련 항목은 과거 기록이며 새 판매 정책이 아닙니다.

# Membership operations

2026-09-14 운영 기준은 v63입니다. 새 요금제 DB 0054–0056 및 관련 함수 배포가 완료됐습니다.
기존 가격·권한 보존안은 폐기됐으며 새 상품 판매는 Play 설정·검증 전까지 비활성입니다.
아래 이전 날짜의 미배포/설정 상태를 현재 상태로 해석하지 마세요.

> 2026-09-13 보안 반영 이후 상태는 [최신 운영 반영 기록](security-rollout-2026-09-13.md)을 확인하세요. 아래의 이전 날짜 상태와 구분합니다.

Baseline: 2026-09-08

## Production evidence and current verification

Updated 2026-09-12 for the v53 baseline. The dated entries below describe the
2026-09-09 inspection, not the current Console/secret state. Later v51 work
included an approved server deployment and the user confirmed English drafts.
Re-read applied migrations and current function versions before a new deployment;
do not infer that later migrations remain unapplied from this old checklist.
Paid purchase/RTDN readiness still needs real Play tester verification.
Post-v53 central monitoring is prepared but not deployed; see
[OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md).

Deployed on 2026-09-09:

- Database migration `0031_memberships_and_ai_quotas.sql` is applied.
- Edge Functions `membership`, `ai_recipe_assistant`, and
  `ai_youtube_recipe_assistant` are active.
- Free-member quota enforcement and server-side plan/model selection are live.

Not configured at the 2026-09-09 inspection (recheck current state):

- Supabase secret `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` is absent, so a new
  Google Play purchase cannot be verified or granted until it is added.
- Google Play RTDN lifecycle reconciliation is pending.
- The two subscription products must be active in Play Console before they can
  be returned to the Android app.
- Migrations `0032` through `0034` and the updated YouTube AI function are prepared
  locally but are not deployed.

## Scheduled discount campaigns

Discounts use Google Play subscription offers. The database schedules when an
existing offer is shown; it never invents or overrides the checkout price.

1. Create and activate an offer on the matching subscription in Play Console.
2. Copy its exact offer ID.
3. In **회원 관리자 > 할인 행사 관리**, add the plan, start/end dates,
   Korean and English messages, and offer ID.
4. Confirm with a Play license tester that the discounted price shown by the
   app matches the checkout sheet.

If the offer ID is wrong, unavailable to the current user, or outside the
scheduled window, Recipe Scout shows the regular base plan instead of claiming
that a discount is available.

## Products and allowances

| Plan | Google Play subscription ID | Price | AI draft allowance |
| --- | --- | ---: | --- |
| Free | none | KRW 0 | 1/day, 5/week, 10/month with `gpt-4o-mini` |
| Monthly Premium | `recipe_scout_premium_monthly` | KRW 9,000/month | 10/day, 50/week, 100/month with `gpt-5.4-mini` |
| Annual Basic | `recipe_scout_basic_annual` | KRW 30,000/year | 3/day, 15/week, 30/month with `gpt-5.4-mini` |

The annual allowance is intentionally lower. Giving the annual KRW 30,000
product the monthly product's 100-draft allowance would make full-use members
loss-making after model, store, and settlement costs.

## Security model

- Flutter never writes a paid flag or quota count.
- Google Play purchase tokens are sent to the `membership` Edge Function and
  verified with `purchases.subscriptionsv2.get` before access is granted.
- A purchase token is unique and cannot be attached to two Recipe Scout users.
- Purchase tokens and entitlement rows are service-role-only. The client reads
  a narrow projection through `get_my_membership()`.
- AI functions reserve an allowance atomically before calling OpenAI and mark
  it successful only after a valid draft is returned.
- A YouTube AI draft with missing ingredient amounts/units or no usable cooking
  directions is marked failed for allowance purposes and stored in the user's
  search-exclusion list for manual editing.
- Profile roles are server-managed so a user cannot promote themselves to an
  administrator and use the membership administration RPCs.

## Play Console preparation

1. Open **Monetize with Play > Products > Subscriptions**.
2. Create and activate `recipe_scout_premium_monthly` with an auto-renewing
   monthly base plan priced at KRW 9,000 in South Korea.
3. Create and activate `recipe_scout_basic_annual` with an auto-renewing annual
   base plan priced at KRW 30,000 in South Korea.
4. Add license testers and test both successful and pending purchases from a
   Play-installed internal-test build. A locally installed APK cannot reliably
   query production subscription products.
5. In Google Cloud, enable the Google Play Android Developer API, create a
   dedicated service account, and grant only the Play Console permissions
   needed to view orders/subscriptions and manage purchase acknowledgement.
6. Store the complete service-account JSON as the Supabase secret
   `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. Never place it in Flutter assets, source,
   logs, or Git.

## Safe rollout order

The database and all three functions form one compatibility unit. Do not
deploy only one part.

1. Back up and review the production database migration plan.
2. Apply `0031_memberships_and_ai_quotas.sql`.
3. Set `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.
4. Deploy `membership`, `ai_recipe_assistant`, and
   `ai_youtube_recipe_assistant` together.
5. Test a free account, monthly license tester, annual license tester, pending
   purchase, cancellation, restore, daily limit, weekly limit, and monthly
   limit.
6. Only then release the Flutter build containing the subscription screen.

No production migration or function deployment is performed merely by adding
these source files.

For the search-exclusion and discount update, apply `0032` before deploying the
updated `ai_youtube_recipe_assistant`, then apply `0033` before distributing the
Flutter build. Migration `0032` intentionally drops the pre-release `bookmarks`
table and its rows.

## Administration

An authenticated profile with the server-owned `admin` role sees **회원 관리자
화면** under **계정 관리 > 회원 및 구독 관리**. The administrator can assign
Free, Monthly Premium, or Annual Basic access. Manual assignments are recorded
in `membership_events` and do not auto-renew.

Do not manually replace a valid Google Play entitlement unless correcting a
support incident. The member should normally use **Google Play 구독 복원**.

The same administrator screen links to **할인 행사 관리** and **요금제 정책
관리**. Plan policy changes can adjust AI limits, the approved recipe model,
the active state, and an internal reference price. Each change is written to
`membership_policy_events`. Product IDs are immutable from the app, and the
checkout price must still be changed in Play Console first.

## Required follow-up before public paid launch

Configure Google Play real-time developer notifications (RTDN) and a secured
receiver so renewals, refunds, account hold, and revocation are processed even
when the member does not open the app. Until RTDN is connected, the app can
verify new and restored purchases, but lifecycle reconciliation is not fully
automatic.
