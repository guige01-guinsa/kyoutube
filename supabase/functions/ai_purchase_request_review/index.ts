import {
  type AiUsageReservation,
  finishAiUsage,
  reserveAiUsage,
} from "../_shared/membership.ts";
import { reviewHandler } from "./handler.ts";

Deno.serve(reviewHandler({
  key: () =>
    Deno.env.get("PURCHASE_REVIEW_ENABLED") === "false"
      ? undefined
      : Deno.env.get("OPENAI_API_KEY"),
  reserve: (authorization) =>
    reserveAiUsage(authorization, "ai_purchase_request_review"),
  finish: (reservation, succeeded, usage) =>
    finishAiUsage(
      reservation as AiUsageReservation,
      succeeded,
      reservation.recipeModel,
      usage.input,
      usage.output,
    ),
}));
