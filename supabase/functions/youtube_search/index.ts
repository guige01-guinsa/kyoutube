import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createYoutubeSearchHandler } from "./handler.ts";
import { searchYoutube } from "./youtube_client.ts";

const handler = createYoutubeSearchHandler({
  getEnv: (name) => Deno.env.get(name),
  searchYoutube,
  logFailure: (code, status) =>
    console.error("youtube_search_failed", { code, status }),
});

serve(handler);
