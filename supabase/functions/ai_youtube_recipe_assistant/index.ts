import { fetchWithTimeout } from "../_shared/http.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { finishAiUsage, reserveAiUsage } from "../_shared/membership.ts";
import { createYoutubeRecipeAssistantHandler } from "./handler.ts";
import { observeHttp } from "../_shared/operations.ts";

serve(
  observeHttp(
    "ai_youtube_recipe_assistant",
    createYoutubeRecipeAssistantHandler({
      getEnv: (name) => Deno.env.get(name),
      reserveUsage: reserveAiUsage,
      finishUsage: finishAiUsage,
      saveIncompleteDraft: async ({ userId, input, draft, reasonCodes }) => {
        const client = createClient(
          Deno.env.get("SUPABASE_URL") ?? "",
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
          {
            auth: { persistSession: false, autoRefreshToken: false },
            global: { fetch: fetchWithTimeout },
          },
        );
        const { error } = await client.from("recipe_search_exclusions").upsert({
          user_id: userId,
          source_type: "youtube",
          source_id: input.selectedVideo.videoId,
          title: draft.title || input.selectedVideo.inferredRecipeTitle,
          summary: draft.summary || null,
          ingredients: draft.ingredients,
          steps: draft.steps,
          image_url:
            `https://i.ytimg.com/vi/${input.selectedVideo.videoId}/hqdefault.jpg`,
          youtube_url: input.selectedVideo.youtubeUrl,
          reason_codes: reasonCodes,
          status: "needs_edit",
          updated_at: new Date().toISOString(),
        }, { onConflict: "user_id,source_type,source_id" });
        if (error) throw error;
      },
      recordMetrics: async (details) => {
        const client = createClient(
          Deno.env.get("SUPABASE_URL") ?? "",
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
          {
            auth: { persistSession: false, autoRefreshToken: false },
            global: { fetch: fetchWithTimeout },
          },
        );
        const { error } = await client.from("youtube_recipe_draft_metrics")
          .upsert({
            reservation_id: details.reservationId,
            user_id: details.userId,
            succeeded: details.succeeded,
            ingredient_count: details.ingredientCount,
            step_count: details.stepCount,
            had_description: details.hadDescription,
            had_transcript: details.hadTranscript,
            repair_attempted: details.repairAttempted,
            promotional_lines_removed: details.promotionalLinesRemoved,
          }, { onConflict: "reservation_id" });
        if (error) throw error;
      },
    }),
  ),
);
