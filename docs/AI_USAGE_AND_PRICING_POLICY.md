# AI usage and pricing policy

Effective baseline: 2026-09-08

Status note, 2026-09-12: the rates, exchange-rate assumptions and capacity
estimates below are historical planning inputs, not live billing totals or
verified current supplier prices. v53 release status is in CURRENT_STATUS.md.
Post-v53 operations adds recorded tokens plus manual actual monthly costs and
budget warnings; it does not enforce the global USD ceiling automatically.
See [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md). Member quotas and the global
operating budget are separate controls.

## Approved recipe models

- Free-member recipe drafts: `gpt-4o-mini`
- Paid-member recipe drafts: `gpt-5.4-mini`
- Availability fallback: `gpt-4o-mini`
- No recipe workflow may use `gpt-5.6-terra` or another unapproved model.

The membership implementation selects the model from a server-owned plan and
never accepts a client-provided model name. Migration `0031` and membership/AI
functions have a dated deployment record in MEMBERSHIP_OPERATIONS.md. Verify
the current remote versions rather than treating the original deployment plan
as the current production state.

## Member allowances

The daily, weekly, and monthly limits are cumulative. A request is permitted
only when all three windows have remaining allowance.

| Plan | Model | Daily | Weekly | Monthly |
| --- | --- | ---: | ---: | ---: |
| Free | `gpt-4o-mini` | 1 | 5 | 10 |
| Monthly paid (KRW 9,000) | `gpt-5.4-mini` | 10 | 50 | 100 |
| Annual Basic (KRW 30,000) | `gpt-5.4-mini` | 3 | 15 | 30 |

Only a successful draft consumes the member allowance. Provider-billed failed
or cancelled requests still count toward the global operating budget and abuse
controls.

## Repeated-request protection

- One in-flight recipe generation per user.
- At most three generation starts per user in ten minutes.
- Repeated cancellations, identical payloads, automation, or account cycling
  can trigger a temporary cooldown independent of the plan allowance.
- Administrators may suspend AI access without removing access to saved recipes.

## USD 700 monthly operating ceiling

The USD 700 figure is the ceiling for all operating costs, not a target to
spend. OpenAI usage is budgeted to USD 560 (80%), leaving USD 140 for variance,
Supabase/Firebase/YouTube-related costs, and incident recovery.

| Stage | Total monthly operating cost | Action |
| --- | ---: | --- |
| Normal | below USD 490 | Normal plan limits |
| Warning | USD 490-559 | Notify administrators and review usage anomalies |
| Protection | USD 560-629 | Stop free-member AI generation; preserve saved data |
| Emergency | USD 630-664 | Allow paid members only under reduced daily capacity |
| Shutdown | USD 665 or above | Stop new AI generations before the USD 700 ceiling |

The OpenAI project budget alert and limit do not include Supabase, Firebase,
YouTube, Google Play fees, taxes, or refunds. Those costs must be combined in
the service-level monthly ledger.

## Capacity planning assumptions

For planning only, one draft is estimated at 10,000 uncached input tokens and
3,000 billed completion/reasoning tokens.

- `gpt-4o-mini`: about USD 0.0033 per draft; USD 0.033 for 10 drafts.
- `gpt-5.4-mini`: about USD 0.021 per draft; USD 2.10 for 100 drafts.
- At the current 4,000 completion/reasoning-token ceiling, the conservative
  paid-member maximum is about USD 2.55 for 100 drafts.

At maximum allowance use and an AI budget of USD 560:

| Free members | Typical free cost | Typical fully reserved monthly members | Conservative fully reserved monthly members |
| ---: | ---: | ---: | ---: |
| 0 | USD 0.00 | 266 | 219 |
| 100 | USD 3.30 | 265 | 218 |
| 500 | USD 16.50 | 258 | 211 |
| 1,000 | USD 33.00 | 250 | 204 |

The conservative column assumes both plans reach the 4,000-token completion
ceiling. Start with at most 150 paid memberships. Increase the saleable
capacity toward 200 only after at least one full billing cycle confirms actual
token use and non-AI operating costs.

## Recommended retail price

- Standard monthly subscription: KRW 9,000 for 100 drafts per month.
- Annual Basic subscription: KRW 30,000 for 30 drafts per month.
- The annual product has a lower AI allowance because KRW 30,000 per year
  cannot sustainably fund the monthly product's 100-draft allowance.

This recommendation uses a conservative internal planning exchange rate of
KRW 1,500 per USD, the current 15% Google Play fee for auto-renewing
subscriptions in South Korea, and a separate 10% tax/settlement buffer. The
exact tax treatment depends on the developer's business-registration and
payments-profile status and must be confirmed with an accountant.

At the monthly plan's full allowance, estimated AI cost is approximately KRW
3,150 under the typical case and KRW 3,825 under the conservative case. The
approved KRW 9,000 monthly price provides room for customer support, refunds,
store settlement variance, and non-AI infrastructure. At 30 annual-plan drafts
per month, the conservative AI cost is approximately KRW 1,148 per member per
month; this preserves a modest margin within the KRW 30,000 annual price.

## Enforcement status

- Model allowlisting, Google Play server verification, and transactional quota
  reservation are implemented locally in the Edge Function and migration
  source.
- The member limits and USD budget stages are the approved product policy.
- Verify the current deployed migration and membership/AI function versions
  before making claims about live quota enforcement.
- A combined provider-cost ledger and Google Play real-time developer
  notifications remain required for fully automated production operations.
