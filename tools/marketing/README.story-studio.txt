Recipe Scout — reusable culinary webtoon studio

Implementation status
---------------------
This is opt-in source code, not evidence of a production rollout. Existing silent
marketing cards and the three reviewed pilot uploads are unchanged. No new paid
API call, production migration, private upload or public release is authorized by
running the offline tests. The production config defaults to disabled.

User's current production target
-------------------------------
Korean originals: 5–6 episodes/week. Each has English and Latin American Spanish
editions. Each video is 60 seconds: six webtoon panels, ten seconds per panel.
All three editions reuse the same six illustrations and original synthesized
music. This is a motion-webtoon slideshow, NOT full character animation. The
current version has subtitles and music, not spoken narration. Average monthly
capacity target: approximately 22–26 originals / 65–78 language outputs; allow
for up to 30 originals / 90 outputs in a five-week production month.

Topics: representative recipes, documented origins, historical development,
new-dish experiments (clearly labeled untested), and restaurants across Korea.
The weekly quantity is an editorial target, NOT automatic permission to spend
money or upload. Administrators explicitly request each episode and approve
production and each language's private upload separately. No public upload.

Flow
----
More > Promotional story series > Open story video studio.
Create a series with character/setting/continuity rules. Choose a culinary topic
and enter the next-episode brief. Review the quote before starting research and
writing. Research uses up to three web-search calls and requires at least two
attributed sources, but this is NOT a guarantee of factual correctness.
An administrator reviews current sources, disputed origins, restaurant details,
food-safety claims and all three language drafts before approving rendering.
Preview all relevant language outputs; approve each private upload separately.
The publisher verifies channel ownership, the approved file hash and privacy.
Sources and synthetic-media disclosure are included in the upload metadata.
Use feedback to request a bounded production recipe proposal; compare the
instructions/font/music settings and explicitly apply or restore a version.
Existing episodes keep their recipe snapshot. Accepted chapters can be read and
copied as a combined novel in each language. There is no automatic model training,
code rewriting, factual certification or guarantee of performance improvement.

Budget and billing limitations
------------------------------
Maximum configured envelope: KRW 300,000 per Korean calendar month.
Initial planning allocations: KRW 200,000 production reservations, KRW 50,000
server/storage allocation, KRW 50,000 contingency. These are allocations, NOT a
vendor quote. Existing subscriptions and actual account billing are not yet read
or reconciled by this application. Include them before activating production.

The serialized config-row lock prevents concurrent requests from over-reserving
the monthly allowance. Queued, failed and uncertain jobs keep their reservation;
there are no automatic retries. Quotes include draft research + Korean writing +
English/Spanish editions, or SIX image generations + three local renders.
The operator must set verified conservative USD quotes, a conservative USD/KRW
conversion including taxes/card fees, daily limits and a new config revision.
No prices/models are silently selected by the application. A missing price,
exchange rate, enabled flag or worker heartbeat keeps paid work blocked.
Queued jobs crossing a Korean calendar-month boundary are held for review.

This reservation cap is NOT an actual provider billing hard limit. Price changes,
exchange rates, independently used keys, hosting overages and other applications
can exceed an estimate. Use a dedicated API project/key, provider-side controls
where available, billing alerts, and daily reconciliation. Never represent the
app's reservation total as the account's actual invoice. Do not enable production
until a small authorized pilot has measured cost and the quotes cover the bounded
request sizes with margin. If the chosen text model cannot support both search
and strict structured chat output, select compatible approved configuration or
adapt/test the provider adapter before enabling it. Do not use deprecated models
merely because an old price looks attractive.

Official documentation checked 2026-10-23:
https://developers.openai.com/api/docs/pricing
https://developers.openai.com/api/docs/guides/structured-outputs
https://developers.openai.com/api/docs/guides/tools-web-search
https://developers.openai.com/api/docs/guides/image-generation
https://developers.google.com/youtube/data/reference/rest/v3/videos

Deployment gates (operator checklist, not authorization)
-------------------------------------------------------
1. Review a full commit and obtain explicit production database/server/web
   approval. Read docs/WEB_RELEASE_SAFETY_KO.md; use the prescribed sealed web
   build/deploy wrappers with that exact approved commit.
2. Apply only the new ordered story_studio migration after a backup/recovery
   review. Do NOT reset/push the database wholesale. The migration creates new
   tables/functions and the private story-previews bucket only.
3. Keep STORY_STUDIO_ENABLED unset/false. Run workflow_dispatch with dry_run=true.
   The workflow's dry-run steps have no production secrets and no paid calls.
4. Configure the dedicated STORY_STUDIO_OPENAI_API_KEY secret and the model vars
   OPENAI_MARKETING_MODEL and OPENAI_STORY_IMAGE_MODEL. Reuse the existing scoped
   marketing Supabase/YouTube secrets; never expose them to the Flutter client.
   Verify permitted model access and approved channel without changing visibility.
5. Review public-repository exposure before pushing any branch containing original
   creative assets. Never push the existing worktree's full history blindly.
6. Configure verified prices/rate/allocations and update config revision. Confirm
   hosting/runner charges with the actual account. Only then enable the workflow
   and the database flag. A worker heartbeat is required to accept paid jobs.
7. Obtain approval for one bounded paid pilot, inspect all three real outputs,
   reconcile real charges, and separately approve the intended private uploads.
8. Inspect the deployed admin UI and denied-access/MFA paths. Keep the previous
   production web version and the three original pilot videos unchanged.

The worker polls only approved jobs; GitHub cron timing is best-effort, not an
instant queue SLA. One job is claimed per run. A global flag pauses new side
effects. A claim uses a 20-minute lease. Errors, expired leases and unknown upload
outcomes become needs_review. An operator must inspect vendor/storage/YouTube
results before any manual reconciliation. Do not blindly requeue or delete these
rows, since an upload may have succeeded even if its response was lost.

Local verification
------------------
node --test tools/marketing/worker.test.mjs tools/marketing/story_studio.test.mjs
MARKETING_PGLITE_PATH points to an isolated installed PGlite 0.3.14 distribution:
node tools/marketing/database.test.mjs
node tools/marketing/story_studio_database.test.mjs
python tools/marketing/story_studio_render_test.py
python tools/marketing/story_series_test.py
Use the repository's pinned Flutter via tools/dev/verify.ps1 for full checks.
No live API keys are needed by these tests. They do not upload content.

Remaining rollout verification / limitations
--------------------------------------------
Real model access, real source quality, six-panel character consistency, billing,
worker hosting and real three-language private uploads require the authorized
pilot. Existing 3-episode Korean pilot links remain an archive; they are NOT yet
imported as editable three-language studio records. New series have persisted
continuity; the prompt uses a bounded last-ten-summary window plus the series
bible. Long-running editorial continuity still needs human review.
