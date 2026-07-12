# Cost guardrails

Monthly OpenAI budget target: 50,000 KRW.

## Alert thresholds
- 70%: warning
- 90%: high warning
- 100%: stop high-cost features and notify admin

## Logging
- Track per-user token usage and request count.
- Store endpoint, model, prompt size, response size, and latency.

## Degrade policy
- Shorten summary length at 90%.
- Disable non-critical AI endpoints at 100%.
