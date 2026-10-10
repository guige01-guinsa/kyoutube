import { fetchWithTimeout } from "./http.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";

export type AiUsageReservation = {
  id: string;
  userId: string;
  planCode: string;
  recipeModel: "gpt-4o-mini" | "gpt-5.4-mini";
};

export class MembershipQuotaError extends Error {
  constructor(
    public readonly code: string,
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "MembershipQuotaError";
  }
}

function requiredEnv(name: string): string {
  const value = (Deno.env.get(name) ?? "").trim();
  if (!value) throw new Error(`Missing server configuration: ${name}`);
  return value;
}

function quotaError(message: string): MembershipQuotaError {
  if (message.includes("VIDEO_MEMBERSHIP_REQUIRED")) {
    return new MembershipQuotaError("video_membership_required",403,"영상 분석은 플러스 또는 비즈니스 구독이 필요합니다.");
  }
  if (message.includes("VIDEO_QUOTA_MONTHLY")) {
    return new MembershipQuotaError("video_quota_monthly",429,"이번 달 요금제의 영상 분석 횟수를 모두 사용했습니다.");
  }
  if (message.includes("AI_QUOTA_DAILY")) {
    return new MembershipQuotaError(
      "ai_quota_daily",
      429,
      "오늘 사용할 수 있는 AI 초안 횟수를 모두 사용했습니다.",
    );
  }
  if (message.includes("AI_QUOTA_WEEKLY")) {
    return new MembershipQuotaError(
      "ai_quota_weekly",
      429,
      "이번 주에 사용할 수 있는 AI 초안 횟수를 모두 사용했습니다.",
    );
  }
  if (message.includes("AI_QUOTA_MONTHLY")) {
    return new MembershipQuotaError(
      "ai_quota_monthly",
      429,
      "이번 달에 사용할 수 있는 AI 초안 횟수를 모두 사용했습니다.",
    );
  }
  if (message.includes("AI_IN_FLIGHT")) {
    return new MembershipQuotaError(
      "ai_request_in_flight",
      409,
      "이미 AI 초안을 만들고 있습니다. 완료 후 다시 시도해 주세요.",
    );
  }
  if (message.includes("AI_RATE_LIMIT")) {
    return new MembershipQuotaError(
      "ai_rate_limited",
      429,
      "짧은 시간에 요청이 반복되었습니다. 10분 후 다시 시도해 주세요.",
    );
  }
  return new MembershipQuotaError(
    "membership_unavailable",
    503,
    "회원 사용 한도를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.",
  );
}

async function authenticatedUserId(authorization: string): Promise<string> {
  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const anonKey = requiredEnv("SUPABASE_ANON_KEY");
  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: authorization }, fetch: fetchWithTimeout },
  });
  const { data: { user }, error } = await authClient.auth.getUser();
  if (error || !user || user.is_anonymous === true) {
    throw new MembershipQuotaError(
      "unauthorized",
      401,
      "로그인이 필요합니다.",
    );
  }
  return user.id;
}

function adminClient() {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { autoRefreshToken: false, persistSession: false }, global: { fetch: fetchWithTimeout } },
  );
}

export async function reserveAiUsage(
  authorization: string,
  endpoint: "ai_recipe_assistant" | "ai_youtube_recipe_assistant" | "ai_purchase_request_review",
): Promise<AiUsageReservation> {
  const userId = await authenticatedUserId(authorization);
  const { data, error } = await adminClient().rpc("begin_ai_recipe_usage", {
    p_user_id: userId,
    p_endpoint: endpoint,
  });
  if (error) throw quotaError(error.message);
  const row = Array.isArray(data) ? data[0] : data;
  const model = row?.recipe_model;
  if (
    !row?.reservation_id ||
    (model !== "gpt-4o-mini" && model !== "gpt-5.4-mini")
  ) {
    throw quotaError("invalid reservation response");
  }
  return {
    id: String(row.reservation_id),
    userId,
    planCode: String(row.plan_code),
    recipeModel: model,
  };
}

export async function finishAiUsage(
  reservation: AiUsageReservation,
  succeeded: boolean,
  model: string,
  requestTokens = 0,
  responseTokens = 0,
): Promise<void> {
  const { error } = await adminClient().rpc("finish_ai_recipe_usage", {
    p_user_id: reservation.userId,
    p_reservation_id: reservation.id,
    p_succeeded: succeeded,
    p_model: model,
    p_request_tokens: Math.max(0, Math.trunc(requestTokens)),
    p_response_tokens: Math.max(0, Math.trunc(responseTokens)),
  });
  if (error) throw new Error(`AI usage finalization failed: ${error.message}`);
}

export async function reserveVideoUsage(authorization:string):Promise<AiUsageReservation> {
  const userId=await authenticatedUserId(authorization);
  const {data,error}=await adminClient().rpc("begin_ai_video_usage",{p_user_id:userId});
  if(error)throw quotaError(error.message);
  const row=Array.isArray(data)?data[0]:data;
  if(!row?.reservation_id||!["plus_monthly","plus_annual","business_monthly","business_annual"].includes(row.plan_code)||!["gpt-4o-mini","gpt-5.4-mini"].includes(row.recipe_model))throw quotaError("invalid reservation response");
  return {id:String(row.reservation_id),userId,planCode:row.plan_code,recipeModel:row.recipe_model};
}

export async function startVideoProvider(reservation:AiUsageReservation,seconds:number):Promise<void> {
  const {data,error}=await adminClient().rpc("start_ai_video_provider",{p_user_id:reservation.userId,p_reservation_id:reservation.id,p_seconds:seconds});
  if(error||data!==true)throw new MembershipQuotaError("membership_unavailable",503,"영상 분석 사용 내역을 기록하지 못했습니다.");
}

export async function finishVideoUsage(reservation:AiUsageReservation,succeeded:boolean,model:string,input:number,output:number,metadata:Record<string,unknown>):Promise<void> {
  // Preserve provider usage independently of success (failed output can still cost money).
  const {error}=await adminClient().from("ai_usage_reservations").update({video_usage_metadata:metadata})
    .eq("id",reservation.id).eq("user_id",reservation.userId).eq("video_analysis",true);
  await finishAiUsage(reservation,succeeded,model,input,output);
  if(error)throw new Error("Video usage metadata persistence failed");
}
