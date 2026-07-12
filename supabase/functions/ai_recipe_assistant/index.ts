import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve(async (req) => {
  const body = await req.json().catch(() => ({}));
  const recipeText = typeof body.recipeText === "string" ? body.recipeText : "";

  return new Response(
    JSON.stringify({
      message: "ai summary placeholder",
      summary: recipeText ? recipeText.slice(0, 120) : ""
    }),
    { headers: { "Content-Type": "application/json" } }
  );
});
