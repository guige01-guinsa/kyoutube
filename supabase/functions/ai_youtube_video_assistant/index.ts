import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  finishVideoUsage,
  reserveVideoUsage,
  startVideoProvider,
} from "../_shared/membership.ts";
import { observeHttp } from "../_shared/operations.ts";
import { createVideoAssistantHandler } from "./handler.ts";

// The existing YouTube AI operations category includes this additional mode.
serve(observeHttp(
  "ai_youtube_recipe_assistant",
  createVideoAssistantHandler({
    getEnv: (name) => Deno.env.get(name),
    reserve: reserveVideoUsage,
    start: startVideoProvider,
    finish: finishVideoUsage,
  }),
));
