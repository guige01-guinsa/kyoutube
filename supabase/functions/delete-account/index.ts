import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const creatorRecipeImagesBucket = "creator-recipe-images";

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

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];

  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }

  return chunks;
}

async function deleteCreatorRecipeImages(
  adminClient: any,
  userId: string,
): Promise<void> {
  const imagePaths: string[] = [];
  const pageSize = 100;
  let offset = 0;

  while (true) {
    const {
      data: entries,
      error: listError,
    } = await adminClient.storage
      .from(creatorRecipeImagesBucket)
      .list(userId, {
        limit: pageSize,
        offset,
        sortBy: {
          column: "name",
          order: "asc",
        },
      });

    if (listError != null) {
      throw new Error(`storage_list_failed:${listError.message}`);
    }

    // Supabase Storage list result always has a string name.
    const pageEntries = (entries ?? []) as Array<{
      id?: string | null;
      name: string;
    }>;

    const pagePaths = pageEntries
      .filter(
        (entry) =>
          entry.id != null &&
          entry.name !== ".emptyFolderPlaceholder",
      )
      .map((entry) => `${userId}/${entry.name}`);

    imagePaths.push(...pagePaths);

    if (pageEntries.length < pageSize) {
      break;
    }

    offset += pageSize;
  }

  for (const paths of chunk(imagePaths, 100)) {
    const { error: removeError } = await adminClient.storage
      .from(creatorRecipeImagesBucket)
      .remove(paths);

    if (removeError != null) {
      throw new Error(`storage_remove_failed:${removeError.message}`);
    }
  }
}

async function deleteUserApplicationData(
  adminClient: any,
  userId: string,
): Promise<void> {
  const cleanupTables = [
    "ai_assistant_feedback",
    "ai_usage_logs",
  ] as const;

  for (const table of cleanupTables) {
    const { error } = await adminClient
      .from(table)
      .delete()
      .eq("user_id", userId);

    if (error != null) {
      throw new Error(
        `application_data_delete_failed:${table}:${error.message}`,
      );
    }
  }
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
    console.error("delete_account_server_configuration_missing");

    return jsonResponse(
      {
        error: "server_configuration_error",
        message: "회원탈퇴를 처리할 수 없습니다.",
      },
      500,
    );
  }

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

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  try {
    // Auth 계정 삭제 전에 공개 Storage 파일과 사용자 AI 데이터를 먼저 제거한다.
    await deleteCreatorRecipeImages(adminClient, user.id);
    await deleteUserApplicationData(adminClient, user.id);

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(
      user.id,
    );

    if (deleteError != null) {
      console.error("delete_account_auth_delete_failed", {
        code: deleteError.code,
        message: deleteError.message,
      });

      return jsonResponse(
        {
          error: "delete_failed",
          message: "회원탈퇴를 완료하지 못했습니다.",
        },
        500,
      );
    }

    return jsonResponse({
      success: true,
      message: "회원탈퇴가 완료되었습니다.",
    });
  } catch (error) {
    console.error("delete_account_cleanup_failed", {
      message: error instanceof Error ? error.message : "unknown_error",
    });

    return jsonResponse(
      {
        error: "delete_failed",
        message: "회원탈퇴를 완료하지 못했습니다.",
      },
      500,
    );
  }
});
