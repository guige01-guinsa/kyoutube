// Compare locally downloaded production source and current source without keys
// or model calls. A 503 ai_not_configured means request validation passed.
const variants = [
  [
    "deployed",
    "../../.artifacts/deployed-youtube-review/supabase/functions/ai_youtube_recipe_assistant/handler.ts",
  ],
  [
    "updated",
    "../../supabase/functions/ai_youtube_recipe_assistant/handler.ts",
  ],
];
const rows = [];
for (const [version, path] of variants) {
  const { createYoutubeRecipeAssistantHandler } = await import(path);
  const handler = createYoutubeRecipeAssistantHandler({
    getEnv: () => undefined,
  });
  for (const title of ["Bibimbap", "초간단 Bibimbap"]) {
    const body = {
      outputLocale: "en-US",
      recipe: { title, youtubeUrl: "https://youtu.be/abc123XYZ00" },
      selectedVideo: {
        videoId: "abc123XYZ00",
        youtubeUrl: "https://youtu.be/abc123XYZ00",
        originalTitle: title,
        inferredRecipeTitle: title,
        channelName: "Synthetic test",
        description: "",
        durationSec: 180,
      },
    };
    const response = await handler(
      new Request("https://local.test", {
        method: "POST",
        headers: {
          Authorization: "Bearer synthetic-test",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      }),
    );
    const result = await response.json();
    rows.push({
      version,
      title,
      httpStatus: response.status,
      code: result.code,
      modelCalled: false,
    });
  }
}
console.log(JSON.stringify(rows, null, 2));
