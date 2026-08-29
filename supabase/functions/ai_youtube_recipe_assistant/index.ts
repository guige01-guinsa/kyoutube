import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createYoutubeRecipeAssistantHandler } from "./handler.ts";

serve(createYoutubeRecipeAssistantHandler({
  getEnv: (name) => Deno.env.get(name),
}));
