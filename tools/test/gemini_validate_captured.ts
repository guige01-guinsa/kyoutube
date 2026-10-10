// Offline acceptance of captured live Gemini outputs. No keys or network needed.
import {
  addQualityWarnings,
  draftQualityIssues,
  normalizeRequest,
  parseModelOutput,
} from "../../supabase/functions/ai_youtube_recipe_assistant/handler.ts";
import { validateVideoEvidence } from "../../supabase/functions/ai_youtube_video_assistant/handler.ts";
const initial = JSON.parse(
  await Deno.readTextFile(".artifacts/gemini-live-smoke-initial.json"),
);
const latest = JSON.parse(
  await Deno.readTextFile(".artifacts/gemini-live-smoke.json"),
);
const metadata = JSON.parse(
  await Deno.readTextFile(".artifacts/gemini-smoke-eligible-metadata.json"),
);
const results = [];
for (
  const live of [
    initial.results.find((r: { locale: string }) => r.locale === "ko-KR"),
    latest.results.find((r: { locale: string }) => r.locale === "en-US"),
  ]
) {
  const source = metadata.find((m: { videoId: string }) =>
    m.videoId === live?.videoId
  );
  if (!source || source.durationSec > 1200 || !live.validRecipeShape) {
    throw new Error("Eligible live result required");
  }
  const url = `https://www.youtube.com/watch?v=${source.videoId}`;
  const input = normalizeRequest({
    outputLocale: live.locale,
    recipe: { title: source.title, youtubeUrl: url },
    selectedVideo: {
      videoId: source.videoId,
      youtubeUrl: url,
      originalTitle: source.title,
      inferredRecipeTitle: live.draft.title,
      channelName: source.author,
      description: "",
      durationSec: source.durationSec,
    },
  });
  if (!input) throw new Error("Source normalization failed");
  const evidence = validateVideoEvidence(live.draft, source.durationSec);
  const draft = evidence ? parseModelOutput(evidence, input) : null;
  const issues = draft ? draftQualityIssues(draft) : ["unparseable"];
  if (draft) addQualityWarnings(draft, input.outputLocale);
  const tokens = live.usage;
  const cost = (tokens.promptTokenCount * .75 +
    ((tokens.candidatesTokenCount ?? 0) + (tokens.thoughtsTokenCount ?? 0)) *
      3.75) / 1e6 * 1400;
  const result = {
    locale: live.locale,
    videoId: source.videoId,
    durationSec: source.durationSec,
    latencySeconds: live.seconds,
    accepted: issues.length === 0,
    issues,
    ingredientCount: draft?.ingredients.length,
    stepCount: draft?.steps.length,
    estimateKrw2026: Math.round(cost * 10) / 10,
    draft,
  };
  results.push(result);
  console.log(JSON.stringify({ ...result, draft: undefined }));
}
await Deno.writeTextFile(
  ".artifacts/gemini-live-acceptance.json",
  JSON.stringify(
    {
      kind:
        "captured_live_provider_output_with_offline_server_validation_not_production_e2e",
      results,
    },
    null,
    2,
  ),
);
if (results.some((r) => !r.accepted)) Deno.exit(1);
