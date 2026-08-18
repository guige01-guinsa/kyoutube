import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (request.method !== "POST") {
    return jsonResponse(
      {
        error: "method_not_allowed",
        message: "POST 요청만 사용할 수 있습니다.",
      },
      405,
    );
  }

  const authorization = request.headers.get("Authorization");

  if (authorization == null || !authorization.startsWith("Bearer ")) {
    return jsonResponse(
      {
        error: "unauthorized",
        message: "로그인이 필요합니다.",
      },
      401,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (
    supabaseUrl == null ||
    supabaseAnonKey == null ||
    serviceRoleKey == null
  ) {
    return jsonResponse(
      {
        error: "server_configuration_error",
        message: "Supabase 서버 환경 설정이 누락되었습니다.",
      },
      500,
    );
  }

  // 요청 토큰으로 현재 로그인 사용자를 검증한다.
  const authClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authorization,
      },
    },
  });

  const {
    data: { user },
    error: userError,
  } = await authClient.auth.getUser();

  if (userError != null || user == null) {
    return jsonResponse(
      {
        error: "unauthorized",
        message: "로그인 사용자 정보를 확인하지 못했습니다.",
      },
      401,
    );
  }

  // service_role은 Edge Function 서버 안에서만 사용한다.
  // Flutter 앱 코드나 env/local.json에는 절대 넣지 않는다.
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(
    user.id,
  );

  if (deleteError != null) {
    return jsonResponse(
      {
        error: "delete_failed",
        message: deleteError.message,
      },
      400,
    );
  }

  return jsonResponse({
    success: true,
    message: "회원탈퇴가 완료되었습니다.",
  });
});