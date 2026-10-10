import {
  MODEL,
  videoGenerationBody,
} from "../../supabase/functions/ai_youtube_video_assistant/request.ts";
// Explicit live Gemini smoke test: at most two public videos, no production DB writes.
// This checks the provider directly, not app authentication or YouTube metadata preflight.
const secretFile = ".env.gemini.local";
const key = (await Deno.readTextFile(secretFile)).replace(/^\uFEFF/, "").split(
  /\r?\n/,
)
  .find((line) => line.startsWith("GEMINI_API_KEY="))?.split("=").slice(1).join(
    "=",
  ).trim().replace(/^["']|["']$/g, "");
if (!key) throw new Error("Gemini key entry is missing");
const cases = [
  { id: "p0JEtaprf2c", language: "Korean", locale: "ko-KR" },
  { id: "3qBjL_HGvco", language: "US English", locale: "en-US" },
];
const metadata = JSON.parse(
  await Deno.readTextFile(".artifacts/gemini-smoke-eligible-metadata.json"),
) as {
  videoId: string;
  durationSec: number;
  isLiveContent: boolean;
  isUnlisted: boolean;
  playabilityStatus: string;
}[];
const results: Record<string, unknown>[] = [];
for (const item of cases) {
  if (Deno.args[0] && Deno.args[0] !== item.locale) continue;
  const source = metadata.find((v) => v.videoId === item.id);
  if (
    !source || source.durationSec <= 0 || source.durationSec > 1200 ||
    source.isLiveContent !== false || source.isUnlisted !== false ||
    source.playabilityStatus !== "OK"
  ) {
    throw new Error(
      "Eligible public-video metadata must be refreshed before this smoke test",
    );
  }
  const started = Date.now();
  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": key },
        signal: AbortSignal.timeout(90000),
        body: JSON.stringify(
          videoGenerationBody(
            `https://www.youtube.com/watch?v=${item.id}`,
            item.locale === "es-419" ? "es-419" : item.locale === "en-US" ? "en-US" : "ko-KR",
          ),
        ),
      },
    );
    const payload = await response.json();
    if (!response.ok) {
      const details = payload.error?.details ?? [];
      const result = {
        videoId: item.id,
        locale: item.locale,
        httpStatus: response.status,
        seconds: (Date.now() - started) / 1000,
        errorStatus: payload.error?.status,
        errorMessage: String(payload.error?.message ?? "").replaceAll(
          key,
          "[REDACTED]",
        ).slice(0, 1200),
        reasons: details.filter((d: Record<string, unknown>) => d.reason).map((
          d: Record<string, unknown>,
        ) => d.reason),
        quotaViolations: details.flatMap((
          d: { violations?: Record<string, unknown>[] },
        ) =>
          (d.violations ?? []).map((v) => ({
            quotaMetric: v.quotaMetric,
            quotaId: v.quotaId,
            quotaValue: v.quotaValue,
            quotaDimensions: v.quotaDimensions,
          }))
        ),
        retryDelay: details.find((d: Record<string, unknown>) => d.retryDelay)
          ?.retryDelay,
      };
      results.push(result);
      console.log(JSON.stringify(result));
      break;
    }
    const candidate = payload.candidates?.[0];
    const content = (candidate?.content?.parts ?? []).filter((
      p: { thought?: boolean; text?: string },
    ) => !p.thought && p.text).map((p: { text: string }) => p.text).join("");
    let draft = null;
    try {
      draft = JSON.parse(content);
    } catch { /* Incomplete JSON is recorded, not retried. */ }
    const result = {
      videoId: item.id,
      locale: item.locale,
      videoDurationSec: source.durationSec,
      httpStatus: response.status,
      seconds: (Date.now() - started) / 1000,
      finishReason: candidate?.finishReason,
      usage: payload.usageMetadata,
      validRecipeShape: Boolean(
        draft?.title && draft?.summary && draft?.ingredients?.length >= 2 &&
          draft?.steps?.length >= 2,
      ),
      draft,
    };
    results.push(result);
    console.log(JSON.stringify({ ...result, draft: undefined }));
  } catch (error) {
    const result = {
      videoId: item.id,
      locale: item.locale,
      errorType: error instanceof Error ? error.name : "unknown",
      seconds: (Date.now() - started) / 1000,
    };
    results.push(result);
    console.log(JSON.stringify(result));
    break;
  }
}
await Deno.writeTextFile(
  ".artifacts/gemini-live-smoke.json",
  JSON.stringify(
    {
      kind: "direct_provider_smoke_not_end_to_end_or_accuracy_validation",
      model: MODEL,
      at: new Date().toISOString(),
      results,
    },
    null,
    2,
  ),
);
