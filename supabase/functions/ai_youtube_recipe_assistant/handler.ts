export type SelectedVideo = {
  videoId: string;
  youtubeUrl: string;
  originalTitle: string;
  inferredRecipeTitle: string;
  channelName: string;
  description: string;
  transcript?: string | null;
  recipeNameHint?: string | null;
  ingredientHints?: string | null;
  durationSec: number | null;
};

export type RecipeOutputLocale = "ko-KR" | "en-US" | "es-419";
import { outputLanguage, localizedMessage } from "../_shared/output_locale.ts";
import { recipeGroundingIssues } from "../_shared/recipe_grounding.ts";

type YoutubeRecipeInput = {
  title: string;
  youtubeUrl: string;
};

type YoutubeEnrichmentRequest = {
  outputLocale: RecipeOutputLocale;
  recipe: YoutubeRecipeInput;
  selectedVideo: SelectedVideo;
};

type HandlerOptions = {
  getEnv: (name: string) => string | undefined;
  fetchOpenAi?: typeof fetch;
  logError?: (event: Record<string, unknown>) => void;
  reserveUsage?: (
    authorization: string,
    endpoint: "ai_youtube_recipe_assistant",
  ) => Promise<{
    id: string;
    userId: string;
    planCode: string;
    recipeModel: "gpt-4o-mini" | "gpt-5.4-mini";
  }>;
  finishUsage?: (
    reservation: {
      id: string;
      userId: string;
      planCode: string;
      recipeModel: "gpt-4o-mini" | "gpt-5.4-mini";
    },
    succeeded: boolean,
    model: string,
    requestTokens?: number,
    responseTokens?: number,
  ) => Promise<void>;
  saveIncompleteDraft?: (details: {
    userId: string;
    input: YoutubeEnrichmentRequest;
    draft: {
      title: string;
      summary: string;
      ingredients: string[];
      steps: string[];
    };
    reasonCodes: string[];
  }) => Promise<void>;
  recordMetrics?: (details: {
    reservationId: string;
    userId: string;
    succeeded: boolean;
    ingredientCount: number;
    stepCount: number;
    hadDescription: boolean;
    hadTranscript: boolean;
    repairAttempted: boolean;
    promotionalLinesRemoved: number;
  }) => Promise<void>;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function text(value: unknown, maxLength: number): string {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function textList(
  value: unknown,
  maxItems: number,
  maxLength: number,
): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => text(item, maxLength))
    .filter(Boolean)
    .slice(0, maxItems);
}

const PROMOTIONAL_LINE =
  /(?:유료\s*광고|광고\s*포함|협찬|제품\s*제공|공동\s*구매|공구\s*(?:링크|오픈)|구매\s*링크|할인\s*코드|쿠폰|스마트스토어|자사몰|비즈니스\s*문의|affiliate\s*links?|sponsor(?:ed|ship)?|paid\s*(?:promotion|partnership)|promotion(?:al)?|promo\s*code|discount\s*code|coupon|use\s+(?:my\s+)?code|shop\s*(?:now|here)|merch(?:andise)?|product\s*links?)/i;
const RECIPE_LINE =
  /(?:재료|양념|소스|육수|준비물|만드는\s*법|조리\s*(?:법|순서)|레시피|ingredients?|directions?|method|recipe)/i;
const MEASURE_LINE =
  /(?:\d+(?:[.,/]\d+)?\s*(?:g|kg|mg|ml|l|cc|컵|큰술|작은술|스푼|개|쪽|알|장|봉|팩|줌|꼬집|대|줄기|인분|cups?|tbsp|tablespoons?|tsp|teaspoons?|oz|ounces?|lb|lbs|pounds?|cloves?|cans?|packages?|packs?|sticks?|pinch(?:es)?|bunch(?:es)?)(?![A-Za-z가-힣]))/i;
const UNVERIFIED_TEXT =
  /(?:확인\s*필요|영상에서\s*확인|재료\s*미상|조리\s*순서\s*미상|needs?\s+(?:video\s+)?verification|check\s+(?:the\s+)?video|ingredient\s+unknown|unknown\s+ingredient|directions?\s+unknown|unknown\s+(?:step|direction))/i;

/**
 * Keeps the full recipe evidence from a YouTube description while removing
 * obvious commerce and sponsorship lines before the text reaches the model.
 * The YouTube Data API already returns the description hidden behind "more".
 */
export function extractRecipeDescription(raw: string): {
  recipeEvidence: string;
  removedLineCount: number;
} {
  const normalized = raw
    .replace(/\r\n?/g, "\n")
    .replace(/https?:\/\/\S+/gi, " ")
    .replace(/www\.\S+/gi, " ");
  const kept: string[] = [];
  let removedLineCount = 0;

  for (const sourceLine of normalized.split("\n")) {
    const line = sourceLine.replace(/[ \t]+/g, " ").trim();
    if (!line) continue;
    const promotional = PROMOTIONAL_LINE.test(line);
    const hasRecipeEvidence = RECIPE_LINE.test(line) || MEASURE_LINE.test(line);
    if (promotional) {
      removedLineCount += 1;
      if (!hasRecipeEvidence) continue;
    }
    if (/^(?:#\S+\s*){3,}$/.test(line)) continue;
    const cleanedLine = promotional
      ? line.replace(PROMOTIONAL_LINE, " ").replace(/^\s*[:：|\-]+\s*/, "")
        .trim()
      : line;
    if (cleanedLine) kept.push(cleanedLine);
  }

  return {
    recipeEvidence: kept.join("\n").slice(0, 10000),
    removedLineCount,
  };
}

function cleanTranscript(raw: string | null | undefined): string {
  if (!raw) return "";
  const seen = new Set<string>();
  const lines: string[] = [];
  for (const sourceLine of raw.replace(/\r\n?/g, "\n").split("\n")) {
    const line = sourceLine
      .replace(/^\s*\d{1,2}:\d{2}(?::\d{2})?\s*/g, "")
      .replace(/\[(?:음악|박수|Music|Applause)\]/gi, "")
      .replace(/[ \t]+/g, " ")
      .trim();
    if (!line || seen.has(line)) continue;
    seen.add(line);
    lines.push(line);
  }
  return lines.join("\n").slice(0, 16000);
}

export function extractYoutubeVideoId(rawUrl: string): string | null {
  let url: URL;
  try {
    url = new URL(rawUrl.trim());
  } catch (_) {
    return null;
  }

  const host = url.hostname.toLowerCase();
  let videoId: string | null = null;
  if (host === "youtu.be" || host.endsWith(".youtu.be")) {
    videoId = url.pathname.split("/").filter(Boolean)[0] ?? null;
  } else if (host === "youtube.com" || host.endsWith(".youtube.com")) {
    if (url.pathname === "/watch") {
      videoId = url.searchParams.get("v");
    } else {
      const parts = url.pathname.split("/").filter(Boolean);
      if (parts.length >= 2 && ["shorts", "embed", "live"].includes(parts[0])) {
        videoId = parts[1];
      }
    }
  }

  return videoId && /^[A-Za-z0-9_-]{6,30}$/.test(videoId) ? videoId : null;
}

export function normalizeRequest(value: unknown): YoutubeEnrichmentRequest | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;

  const forbiddenKeys = [
    "references",
    "referenceRecipeIds",
    "referenceRecipeId",
    "publicRecipeIds",
    "publicRecipeId",
  ];
  if (forbiddenKeys.some((key) => key in body)) return null;
  if (
    Object.keys(body).some((key) =>
      !["outputLocale", "recipe", "selectedVideo"].includes(key)
    )
  ) {
    return null;
  }

  if (
    body.outputLocale != null && body.outputLocale !== "ko-KR" &&
    body.outputLocale !== "en-US" && body.outputLocale !== "es-419"
  ) return null;
  const outputLocale: RecipeOutputLocale = body.outputLocale === "en-US"
    ? "en-US"
    : body.outputLocale === "es-419"
    ? "es-419"
    : "ko-KR";

  if (
    !body.recipe || typeof body.recipe !== "object" ||
    Array.isArray(body.recipe)
  ) {
    return null;
  }
  if (
    !body.selectedVideo || typeof body.selectedVideo !== "object" ||
    Array.isArray(body.selectedVideo)
  ) {
    return null;
  }

  const recipeSource = body.recipe as Record<string, unknown>;
  const selectedSource = body.selectedVideo as Record<string, unknown>;
  if (
    Object.keys(recipeSource).some((key) =>
      !["title", "youtubeUrl"].includes(key)
    )
  ) return null;
  const selectedKeys = [
    "videoId",
    "youtubeUrl",
    "originalTitle",
    "inferredRecipeTitle",
    "channelName",
    "description",
    "transcript",
    "recipeNameHint",
    "ingredientHints",
    "durationSec",
  ];
  if (Object.keys(selectedSource).some((key) => !selectedKeys.includes(key))) {
    return null;
  }
  const recipe = {
    title: text(recipeSource.title, 120),
    youtubeUrl: text(recipeSource.youtubeUrl, 500),
  };
  const selectedVideo = {
    videoId: text(selectedSource.videoId, 30),
    youtubeUrl: text(selectedSource.youtubeUrl, 500),
    originalTitle: text(selectedSource.originalTitle, 200),
    inferredRecipeTitle: text(selectedSource.inferredRecipeTitle, 80),
    channelName: text(selectedSource.channelName, 160),
    description: text(selectedSource.description, 10000),
    transcript: cleanTranscript(text(selectedSource.transcript, 20000)) || null,
    recipeNameHint: text(selectedSource.recipeNameHint, 80) || null,
    ingredientHints: text(selectedSource.ingredientHints, 500) || null,
    durationSec: typeof selectedSource.durationSec === "number"
      ? selectedSource.durationSec
      : null,
  };

  if (
    !recipe.title || !recipe.youtubeUrl || !selectedVideo.videoId ||
    !selectedVideo.youtubeUrl || !selectedVideo.originalTitle ||
    !selectedVideo.inferredRecipeTitle || !selectedVideo.channelName
  ) return null;
  const inferredTitleLimit = outputLocale === "ko-KR" ? 10 : 80;
  if ([...selectedVideo.inferredRecipeTitle].length > inferredTitleLimit) {
    return null;
  }
  if (
    selectedVideo.durationSec != null &&
    (!Number.isInteger(selectedVideo.durationSec) ||
      selectedVideo.durationSec < 1 || selectedVideo.durationSec > 3600)
  ) return null;
  // Promotional words are title noise, not an invalid video identity.
  // Normalize legacy app requests as well as newly generated titles.
  selectedVideo.inferredRecipeTitle = cleanRecipeTitle(
    selectedVideo.inferredRecipeTitle,
    outputLocale === "es-419"
      ? "Receta en video"
      : outputLocale === "en-US" ? "Video recipe" : "영상 요리",
    outputLocale,
  );

  const recipeVideoId = extractYoutubeVideoId(recipe.youtubeUrl);
  const selectedUrlVideoId = extractYoutubeVideoId(selectedVideo.youtubeUrl);
  if (
    !recipeVideoId || !selectedUrlVideoId ||
    recipeVideoId !== selectedUrlVideoId ||
    selectedVideo.videoId !== selectedUrlVideoId
  ) {
    return null;
  }

  return { outputLocale, recipe, selectedVideo };
}

function cleanRecipeTitle(
  value: unknown,
  fallback: string,
  outputLocale: RecipeOutputLocale,
): string {
  const cleaned = text(value, 80)
    .replace(/[\[\(【].*?[\]\)】]/g, " ")
    .replace(
      /(초간단|대박|역대급|무조건|강력추천|필수시청|레전드|황금레시피)/g,
      " ",
    )
    .replace(
      outputLocale !== "ko-KR"
        ? /\b(?:must\s*watch|viral|sponsored|paid\s+promotion|subscribe|like\s+and\s+share)\b/gi
        : /(초간단|대박|역대급|무조건|강력추천|필수시청|레전드|황금레시피|구독|좋아요|알림설정|만드는|만들기|레시피)/g,
      " ",
    )
    .replace(/[^가-힣A-Za-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const normalized = cleaned || fallback.trim();
  const limit = outputLocale === "ko-KR" ? 20 : 80;
  return [...normalized].slice(0, limit).join("").trim();
}

type EvidenceStatus = "confirmed" | "inferred" | "unverified";

type IngredientDetail = {
  name: string;
  quantity: string | null;
  unit: string | null;
  preparation: string | null;
  status: EvidenceStatus;
};

type StepDetail = {
  instruction: string;
  durationMinutes: number | null;
  ingredientNames: string[];
  status: EvidenceStatus;
};

function evidenceStatus(
  value: unknown,
  fallback: EvidenceStatus,
): EvidenceStatus {
  return value === "confirmed" || value === "inferred" || value === "unverified"
    ? value
    : fallback;
}

function nullableText(value: unknown, maxLength: number): string | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return String(value).slice(0, maxLength);
  }
  const normalized = text(value, maxLength);
  return normalized || null;
}

function positiveInteger(value: unknown, maximum: number): number | null {
  return typeof value === "number" && Number.isInteger(value) && value > 0 &&
      value <= maximum
    ? value
    : null;
}

function ingredientDetails(value: unknown): IngredientDetail[] {
  if (!Array.isArray(value)) return [];

  return value.map((raw): IngredientDetail | null => {
    if (typeof raw === "string") {
      const name = text(raw, 160);
      if (!name) return null;
      return {
        name,
        quantity: null,
        unit: null,
        preparation: null,
        status: UNVERIFIED_TEXT.test(name) ? "unverified" : "confirmed",
      };
    }
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    const source = raw as Record<string, unknown>;
    const name = text(source.name, 100);
    if (!name) return null;
    const fallback = UNVERIFIED_TEXT.test(name) ? "unverified" : "confirmed";
    return {
      name,
      quantity: nullableText(source.quantity, 32),
      unit: nullableText(source.unit, 24),
      preparation: nullableText(source.preparation, 80),
      status: evidenceStatus(source.status, fallback),
    };
  }).filter((item): item is IngredientDetail => item !== null).slice(0, 60);
}

function stepDetails(value: unknown): StepDetail[] {
  if (!Array.isArray(value)) return [];

  return value.map((raw): StepDetail | null => {
    if (typeof raw === "string") {
      const instruction = text(raw, 500);
      if (!instruction) return null;
      return {
        instruction,
        durationMinutes: null,
        ingredientNames: [],
        status: UNVERIFIED_TEXT.test(instruction) ? "unverified" : "confirmed",
      };
    }
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    const source = raw as Record<string, unknown>;
    const instruction = text(source.instruction, 420);
    if (!instruction) return null;
    const fallback = UNVERIFIED_TEXT.test(instruction)
      ? "unverified"
      : "confirmed";
    return {
      instruction,
      durationMinutes: positiveInteger(source.durationMinutes, 1440),
      ingredientNames: textList(source.ingredientNames, 30, 100),
      status: evidenceStatus(source.status, fallback),
    };
  }).filter((item): item is StepDetail => item !== null).slice(0, 40);
}

function formatIngredient(
  item: IngredientDetail,
  outputLocale: RecipeOutputLocale,
): string {
  const measure = [item.quantity, item.unit].filter(Boolean).join(" ");
  const preparation = item.preparation ? `(${item.preparation})` : "";
  const prefix = item.status === "unverified"
    ? outputLocale === "es-419" ? "[Revisar video] "
    : outputLocale === "en-US" ? "[Check video] " : "[확인 필요] "
    : item.status === "inferred"
    ? outputLocale === "es-419" ? "[Inferido] "
    : outputLocale === "en-US" ? "[Inferred] " : "[추정] "
    : "";
  return `${prefix}${
    [item.name, measure, preparation].filter(Boolean).join(" ")
  }`;
}

function formatStep(
  item: StepDetail,
  outputLocale: RecipeOutputLocale,
): string {
  const duration = item.durationMinutes == null
    ? ""
    : outputLocale === "es-419"
    ? ` (aprox. ${item.durationMinutes} min)`
    : outputLocale === "en-US"
    ? ` (about ${item.durationMinutes} min)`
    : ` (약 ${item.durationMinutes}분)`;
  const prefix = item.status === "unverified"
    ? outputLocale === "es-419" ? "[Revisar video] "
    : outputLocale === "en-US" ? "[Check video] " : "[확인 필요] "
    : item.status === "inferred"
    ? outputLocale === "es-419" ? "[Inferido] "
    : outputLocale === "en-US" ? "[Inferred] " : "[추정] "
    : "";
  return `${prefix}${item.instruction}${duration}`;
}

export function parseModelOutput(value: unknown, input: YoutubeEnrichmentRequest) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const source = value as Record<string, unknown>;
  const title = cleanRecipeTitle(
    source.title,
    input.selectedVideo.inferredRecipeTitle,
    input.outputLocale,
  );
  const summary = text(source.summary, 240);
  const parsedIngredients = ingredientDetails(source.ingredients);
  const parsedSteps = stepDetails(source.steps);
  if (!title) return null;
  return {
    title,
    summary,
    servings: positiveInteger(source.servings, 100),
    prepTimeMinutes: positiveInteger(source.prepTimeMinutes, 1440),
    cookTimeMinutes: positiveInteger(source.cookTimeMinutes, 1440),
    ingredients: parsedIngredients.map((item) =>
      formatIngredient(item, input.outputLocale)
    ),
    ingredientDetails: parsedIngredients,
    steps: parsedSteps.map((item) => formatStep(item, input.outputLocale)),
    stepDetails: parsedSteps,
    tips: text(source.tips, 500) || null,
    warnings: textList(source.warnings, 10, 240),
  };
}

function parseModelContent(
  raw: unknown,
  input: YoutubeEnrichmentRequest,
): ReturnType<typeof parseModelOutput> {
  if (typeof raw !== "string") return null;
  const normalized = raw.trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "");
  try {
    return parseModelOutput(JSON.parse(normalized), input);
  } catch (_) {
    return null;
  }
}

export function draftQualityIssues(
  draft: NonNullable<ReturnType<typeof parseModelOutput>>,
  input?: YoutubeEnrichmentRequest,
) {
  const issues: string[] = [];
  const usableIngredients = draft.ingredientDetails.filter((item) =>
    item.name.trim().length > 0 &&
    !UNVERIFIED_TEXT.test(item.name) &&
    !PROMOTIONAL_LINE.test(item.name)
  );
  const distinctIngredients = new Set(
    usableIngredients.map((item) =>
      item.name.trim().toLocaleLowerCase().replace(/\s+/g, " ")
    ),
  );
  if (distinctIngredients.size < 2) issues.push("insufficient_ingredients");
  if (usableIngredients.length && usableIngredients.every(item => item.status === "unverified")) {
    issues.push("unverified_ingredients");
  }
  if (distinctIngredients.size < usableIngredients.length) {
    issues.push("duplicate_ingredients");
  }

  const usableSteps = draft.stepDetails.filter((item) =>
    item.instruction.trim().length >= 2 &&
    !UNVERIFIED_TEXT.test(item.instruction) &&
    !PROMOTIONAL_LINE.test(item.instruction)
  );
  const distinctSteps = new Set(
    usableSteps.map((item) =>
      item.instruction.trim().toLocaleLowerCase().replace(/\s+/g, " ")
    ),
  );
  if (distinctSteps.size < 2) issues.push("insufficient_steps");
  if (usableSteps.length && usableSteps.every(item => item.status === "unverified")) {
    issues.push("unverified_steps");
  }
  if (distinctSteps.size < usableSteps.length) issues.push("duplicate_steps");
  if (!draft.summary.trim()) issues.push("missing_summary");
  if (input) {
    const evidence = input.selectedVideo.transcript?.trim() ||
      extractRecipeDescription(input.selectedVideo.description).recipeEvidence;
    issues.push(...recipeGroundingIssues(draft, evidence, input.outputLocale));
  }
  return issues;
}

export function addQualityWarnings(
  draft: NonNullable<ReturnType<typeof parseModelOutput>>,
  outputLocale: RecipeOutputLocale,
) {
  const missingMeasures =
    draft.ingredientDetails.filter((item) => !item.quantity || !item.unit)
      .length;
  if (missingMeasures > 0) {
    const warning = outputLocale === "es-419"
      ? `${missingMeasures} ingrediente(s) requieren verificar la cantidad o unidad en el video.`
      : outputLocale === "en-US"
      ? `${missingMeasures} ingredient(s) need a quantity or unit check against the video.`
      : `수량 또는 단위를 영상에서 확인할 재료가 ${missingMeasures}개 있습니다.`;
    if (!draft.warnings.includes(warning)) draft.warnings.push(warning);
  }
  return draft;
}

function prompt(input: YoutubeEnrichmentRequest): string {
  const hasTranscript = Boolean(input.selectedVideo.transcript?.trim());
  const isEnglish = input.outputLocale === "en-US";
  const isSpanish = input.outputLocale === "es-419";
  const hintGuide =
    (input.selectedVideo.recipeNameHint || input.selectedVideo.ingredientHints)
      ? isSpanish
        ? "recipeNameHint e ingredientHints son pistas aportadas por la persona usuaria sobre este mismo video. Úsalas solo para refinar el título e identificar posibles ingredientes. Si difieren de la transcripción o la descripción, prioriza esas fuentes."
        : isEnglish
        ? "recipeNameHint and ingredientHints are user-provided clues about this same video. Use them only to refine the title and identify ingredient candidates. Prefer the transcript and description if they conflict."
        : "사용자 힌트(recipeNameHint, ingredientHints)는 같은 영상에 대한 사용자의 보조 단서입니다. 힌트는 제목 정리와 재료 후보 판별에만 사용하고, 자막/설명란과 충돌하면 자막/설명란을 우선하세요."
      : isSpanish
      ? "No se proporcionaron pistas de la persona usuaria."
      : isEnglish
      ? "No user hints were provided."
      : "사용자 힌트는 제공되지 않았습니다.";
  const sourceGuide = hasTranscript
    ? isSpanish
      ? "La transcripción pegada corresponde a este mismo video. Úsala como evidencia principal para ingredientes e instrucciones; la descripción es evidencia complementaria."
      : isEnglish
      ? "The pasted transcript is from this same video. Use it as the primary evidence for ingredients and directions, with the description as supporting evidence."
      : "사용자가 붙여넣은 transcript는 같은 영상의 자막입니다. 재료와 조리 순서는 transcript를 최우선 근거로 사용하고, 설명란은 보조 자료로만 사용하세요."
    : isSpanish
    ? "No se proporcionó transcripción. Usa únicamente información respaldada por el título y la descripción completa del video."
    : isEnglish
    ? "No transcript was provided. Use only information supported by the video title and full description."
    : "자막이 제공되지 않았습니다. 영상 제목과 설명란에서 확인 가능한 정보만 사용하세요.";

  const description = extractRecipeDescription(
    input.selectedVideo.description,
  );
  const evidenceVideo = {
    ...input.selectedVideo,
    description: description.recipeEvidence,
    descriptionRemovedPromotionalLines: description.removedLineCount,
  };

  if (isSpanish) {
    return `
Eres un asistente de edición de recetas en español latinoamericano.
Usa únicamente la información del único video de YouTube seleccionado por la persona usuaria. No uses recetas públicas, otros videos, comentarios ni fuentes externas.
Escribe todos los campos visibles para la persona usuaria en español latinoamericano natural, aun cuando el video esté en otro idioma. Conserva fielmente cantidades y unidades.
${sourceGuide}
${hintGuide}
Extrae título, resumen, porciones, ingredientes, cantidades, unidades, instrucciones, tiempos y consejos que estén respaldados por el título, la descripción completa, el canal y la duración.
Lee las secciones de ingredientes, condimentos, salsas, caldo, instrucciones, método y receta. Nunca incluyas publicidad, patrocinios, enlaces de afiliados o productos, códigos promocionales, promoción del canal, sorteos, envíos ni datos de contacto.
Incluye todos los ingredientes reales distintos y pasos prácticos respaldados por la evidencia. No inventes ni repitas elementos. Redacta un resumen breve y no vacío. Si falta cantidad o unidad, usa null y agrega una advertencia en español.
Si hay ingredientes pero las instrucciones son breves, puedes inferir preparación, cocción y finalización básicas que no contradigan la evidencia. No inventes temperaturas, tiempos, proporciones ni cantidades exactas.
Usa un título de plato conciso de hasta 80 caracteres. Marca status como confirmed, inferred o unverified. Combina el mismo ingrediente solo si las unidades son compatibles.
Si no se identifican ingredientes o instrucciones, usa un elemento editable no verificado como "Revisar ingrediente en el video" en lugar de una lista vacía. Es un borrador revisable y no se guarda automáticamente.
Devuelve solamente este objeto JSON.
{"title":"Título de la receta","summary":"Hasta 240 caracteres","servings":2,"prepTimeMinutes":10,"cookTimeMinutes":20,"ingredients":[{"name":"leche","quantity":"300","unit":"ml","preparation":null,"status":"confirmed"}],"steps":[{"instruction":"Agrega la leche y lleva a fuego suave.","durationMinutes":5,"ingredientNames":["leche"],"status":"confirmed"}],"tips":"Consejo o null","warnings":["Aspectos que la persona usuaria debe verificar en el video"]}

Receta actual: ${JSON.stringify(input.recipe)}
Video seleccionado: ${JSON.stringify(evidenceVideo)}
    `.trim();
  }

  if (isEnglish) {
    return `
You are an English-language recipe editing assistant.
Use only the information from the one YouTube video selected by the user. Do not use public recipes, other videos, comments, or outside sources.
Write every user-facing field in natural US English, even when the source video uses another language. Keep quantities and units faithful to the source.
${sourceGuide}
${hintGuide}
Extract the title, summary, servings, ingredients, quantities, units, directions, times, and tips supported by the title, full description, channel, and duration.
Read the entire Ingredients, Seasoning, Sauce, Stock, Directions, Method, and Recipe sections. The description contains text hidden behind YouTube's More button.
Never include advertising, sponsorships, affiliate or product links, promo codes, channel promotion, giveaways, shipping, or contact information in recipe fields.
Include all distinct real ingredients and actionable cooking steps supported by the evidence. A simple recipe with 2 ingredients and 2 steps is valid. Never invent or duplicate items to meet a count. Provide a concise nonempty English summary. Keep an evidenced ingredient even when its quantity or unit is missing; set quantity/unit to null and add an English warning.
If the description contains ingredients but only brief directions, you may infer basic preparation, cooking, and finishing actions that do not contradict the evidence. Do not invent exact temperatures, times, ratios, or quantities.
Use a concise dish name of at most 80 characters for the title. Remove hype, promotions, channel names, and decorative symbols.
Set status to confirmed when directly supported, inferred when reasonably derived from context, or unverified when the user must check the video.
Combine repeated uses of the same ingredient only when units are compatible. Connect each step to relevant ingredient names in ingredientNames.
If ingredients or directions cannot be identified, use an unverified editable item such as "Check video for ingredient" instead of an empty array.
This is a reviewable draft and must not be saved automatically.
Return only the following JSON object shape.
{"title":"Recipe title","summary":"Up to 240 characters","servings":2,"prepTimeMinutes":10,"cookTimeMinutes":20,"ingredients":[{"name":"milk","quantity":"300","unit":"ml","preparation":null,"status":"confirmed"}],"steps":[{"instruction":"Add the milk and bring it to a simmer.","durationMinutes":5,"ingredientNames":["milk"],"status":"confirmed"}],"tips":"Tip or null","warnings":["Items the user should verify against the video"]}

Current recipe: ${JSON.stringify(input.recipe)}
Selected video: ${JSON.stringify(evidenceVideo)}
    `.trim();
  }

  return `
당신은 한국어 레시피 편집 보조 AI입니다.
오직 사용자가 선택한 한 개의 YouTube 영상 정보만 사용하세요.
공공 레시피, 다른 영상, 외부 자료 또는 댓글을 사용하지 마세요.
${sourceGuide}
${hintGuide}
영상 제목·설명·채널·길이에서 확인 가능한 제목, 요약, 인분, 재료, 계량, 조리 순서, 시간, 팁을 최대한 채우세요.
설명란의 재료/양념/소스/육수 구역을 끝까지 읽고 각 줄의 재료명, 수량, 단위를 분리하세요. 설명은 YouTube 화면에서 '더보기' 뒤에 숨은 부분까지 포함한 전체 설명입니다.
광고, 협찬, 공동구매, 상품명, 구매 링크, 할인 코드, 채널 홍보, 이벤트, 배송·문의 문구는 레시피 제목·재료·단계·팁에 절대 넣지 마세요.
근거에 있는 서로 다른 실제 재료와 실행 가능한 조리 단계를 모두 작성하세요. 간단한 요리는 재료 2개와 단계 2개도 유효합니다. 개수를 채우려고 항목을 지어내거나 반복하지 마세요. 비어 있지 않은 간결한 한국어 요약을 작성하세요. 수량이나 단위가 없는 재료도 이름이 근거에 있으면 포함하되 quantity/unit은 null로 두고 warnings에 확인 필요를 기록하세요.
설명에 재료 목록은 있지만 조리 단계가 짧으면 제목·재료와 모순되지 않는 기본 준비·가열·마무리 동작을 inferred로 구성할 수 있습니다. 근거 없이 특정 온도·시간·수량은 만들지 마세요.
제목은 음식명 중심으로 20자 이내로 추론하고 광고, 감탄, 홍보, 채널명, 특수문자를 제외하세요.
설명에 없는 계량, 시간, 비율을 사실처럼 만들지 말고 해당 항목은 warnings에 영상 확인 필요를 표시하세요.
각 재료와 조리 단계의 status는 근거가 명확하면 confirmed, 문맥상 추정이면 inferred, 영상에서 사용자가 확인해야 하면 unverified로 지정하세요.
같은 재료가 여러 번 사용되면 ingredients에는 총량을 합쳐 한 번만 적고, 각 단계의 ingredientNames에 사용하는 재료명을 연결하세요. 단위가 달라 안전하게 합칠 수 없으면 수량과 단위를 null로 두고 unverified로 지정하세요.
재료나 조리 순서를 확인할 수 없으면 빈 배열 대신 status가 unverified인 "영상에서 확인 필요" 편집용 항목을 넣으세요.
결과는 자동 저장되지 않는 사용자 검토용 초안입니다.
반드시 아래 JSON 객체만 반환하세요.
{"title":"레시피 제목","summary":"240자 이하","servings":2,"prepTimeMinutes":10,"cookTimeMinutes":20,"ingredients":[{"name":"우유","quantity":"300","unit":"ml","preparation":null,"status":"confirmed"}],"steps":[{"instruction":"우유를 넣고 끓인다","durationMinutes":5,"ingredientNames":["우유"],"status":"confirmed"}],"tips":"팁 또는 null","warnings":["사용자가 영상에서 확인할 항목"]}

현재 레시피: ${JSON.stringify(input.recipe)}
선택된 영상: ${JSON.stringify(evidenceVideo)}
  `.trim();
}

function repairPrompt(
  input: YoutubeEnrichmentRequest,
  draft: NonNullable<ReturnType<typeof parseModelOutput>>,
  issues: string[],
): string {
  if (input.outputLocale === "es-419") {
    return `${prompt(input)}

El primer borrador no cumplió los requisitos mínimos: ${issues.join(", ")}.
Primer borrador: ${JSON.stringify(draft)}
Vuelve a revisar la descripción y la transcripción para encontrar ingredientes dispersos, sin incluir publicidad ni comercio. Corrige resúmenes faltantes, duplicados e información incompleta usando solo la evidencia. No inventes ingredientes ni pasos. Si falta una cantidad o unidad, usa null y una advertencia en español.
Devuelve únicamente el objeto JSON corregido.`;
  }
  if (input.outputLocale === "en-US") {
    return `${prompt(input)}

The first draft did not meet the minimum requirements: ${issues.join(", ")}.
First draft: ${JSON.stringify(draft)}
Search the supplied description and transcript again for scattered ingredients while continuing to exclude advertising and commerce content.
Repair missing summaries, duplicates and incomplete recipe details using only the evidence. Simple recipes with 2 distinct ingredients and 2 actionable steps are valid. Never invent ingredients or steps to reach a count.
Do not discard a real ingredient only because its quantity or unit is missing; use null and an English warning.
Return only the corrected JSON object.`;
  }
  return `${prompt(input)}

첫 번째 초안이 최소 기준을 충족하지 못했습니다: ${issues.join(", ")}.
첫 번째 초안: ${JSON.stringify(draft)}
광고성 항목을 제거한 상태를 유지하면서 설명/자막에 흩어진 재료를 다시 찾으세요.
근거에 따라 누락된 요약, 중복, 불완전한 조리 정보를 보정하세요. 간단한 요리는 서로 다른 재료 2개와 실행 가능한 단계 2개도 유효합니다. 개수를 채우려고 재료나 단계를 지어내지 마세요.
수량·단위가 없다는 이유만으로 실제 재료를 버리지 말고 null과 warning을 사용하세요.
JSON 객체만 다시 반환하세요.`;
}

export function createYoutubeRecipeAssistantHandler(options: HandlerOptions) {
  const fetchOpenAi = options.fetchOpenAi ?? fetch;
  const logError = options.logError ?? ((event) => console.error(event));

  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return jsonResponse({
        status: "error",
        code: "method_not_allowed",
        message: "POST 요청만 지원합니다.",
      }, 405);
    }
    const authorization = (request.headers.get("Authorization") ?? "").trim();
    if (!authorization.startsWith("Bearer ")) {
      return jsonResponse({
        status: "error",
        code: "unauthorized",
        message: "로그인이 필요합니다.",
      }, 401);
    }

    const requestBody = await request.json().catch(() => null);
    const input = normalizeRequest(requestBody);
    if (!input) {
      return jsonResponse({
        status: "error",
        code: "invalid_selected_video",
        message: requestBody?.outputLocale === "es-419"
          ? "La información del video no es válida. Selecciona el video de nuevo."
          : requestBody?.outputLocale === "en-US"
          ? "The selected YouTube video information is invalid. Please select the video again."
          : "선택한 YouTube 영상 정보가 올바르지 않습니다.",
      }, 400);
    }

    const apiKey = (options.getEnv("OPENAI_API_KEY") ?? "").trim();
    const allowedModels = new Set(["gpt-5.4-mini", "gpt-4o-mini"]);
    const configuredModel = (options.getEnv("OPENAI_RECIPE_MODEL") ?? "")
      .trim();
    const configuredFallbackModel =
      (options.getEnv("OPENAI_RECIPE_FALLBACK_MODEL") ?? "").trim();
    const fallbackModel = allowedModels.has(configuredFallbackModel)
      ? configuredFallbackModel
      : "gpt-4o-mini";
    if (!apiKey) {
      return jsonResponse({
        status: "error",
        code: "ai_not_configured",
        message: localizedMessage(input.outputLocale, "AI 기능이 아직 설정되지 않았습니다.", "AI is not configured yet.", "La IA aún no está configurada."),
      }, 503);
    }

    let reservation:
      | Awaited<ReturnType<NonNullable<HandlerOptions["reserveUsage"]>>>
      | null = null;
    try {
      reservation = options.reserveUsage
        ? await options.reserveUsage(
          authorization,
          "ai_youtube_recipe_assistant",
        )
        : null;
    } catch (error) {
      const quota = error as {
        code?: unknown;
        status?: unknown;
        message?: unknown;
      };
      return jsonResponse({
        status: "error",
        code: typeof quota.code === "string"
          ? quota.code
          : "membership_unavailable",
        message: typeof quota.message === "string"
          ? quota.message
          : "회원 사용 한도를 확인할 수 없습니다.",
      }, typeof quota.status === "number" ? quota.status : 503);
    }
    const model = reservation?.recipeModel ??
      (allowedModels.has(configuredModel) ? configuredModel : "gpt-5.4-mini");
    let generationSucceeded = false;
    let usedModel = model;
    let requestTokens = 0;
    let responseTokens = 0;
    let finalIngredientCount = 0;
    let finalStepCount = 0;
    let repairAttempted = false;
    const descriptionInfo = extractRecipeDescription(
      input.selectedVideo.description,
    );

    try {
      const models = [model, fallbackModel].filter((candidate, index, all) =>
        candidate.length > 0 && all.indexOf(candidate) === index
      );
      let upstream: Response | null = null;

      for (const [index, candidateModel] of models.entries()) {
        usedModel = candidateModel;
        const generationOptions = /^(gpt-[56](?:\.|-|$))/.test(candidateModel)
          ? { reasoning_effort: "low" }
          : { temperature: 0.2 };
        upstream = await fetchOpenAi(
          "https://api.openai.com/v1/chat/completions",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${apiKey}`,
            },
            body: JSON.stringify({
              model: candidateModel,
              ...generationOptions,
              max_completion_tokens: 4000,
              response_format: { type: "json_object" },
              messages: [
                {
                  role: "system",
                  content: `Create a safe ${outputLanguage(input.outputLocale)} recipe draft from exactly one selected YouTube video. Write every user-facing field in this language.`,
                },
                { role: "user", content: prompt(input) },
              ],
            }),
          },
        );
        if (upstream.ok) break;

        const errorPayload = await upstream.json().catch(() => null);
        const upstreamError = errorPayload?.error;
        const upstreamCode = typeof upstreamError?.code === "string"
          ? upstreamError.code
          : null;
        const upstreamType = typeof upstreamError?.type === "string"
          ? upstreamError.type
          : null;
        const requestId = upstream.headers.get("x-request-id");

        logError({
          event: "openai_recipe_request_failed",
          function: "ai_youtube_recipe_assistant",
          status: upstream.status,
          code: upstreamCode,
          type: upstreamType,
          requestId,
          model: candidateModel,
        });

        const canFallback = index === 0 && models.length > 1 &&
          (upstream.status === 403 || upstream.status === 404 ||
            upstreamCode === "model_not_found");
        if (canFallback) {
          logError({
            event: "openai_recipe_model_fallback",
            function: "ai_youtube_recipe_assistant",
            primaryModel: candidateModel,
            fallbackModel: models[1],
            status: upstream.status,
            code: upstreamCode,
            requestId,
          });
          continue;
        }

        if (upstream.status === 401) {
          return jsonResponse({
            status: "error",
            code: "ai_upstream_auth_error",
            message: input.outputLocale === "es-419"
              ? "Es necesario revisar la autenticación del servicio de IA."
              : input.outputLocale === "en-US"
              ? "The AI service authentication needs attention."
              : "AI API 인증 설정을 확인해야 합니다.",
          }, 502);
        }
        if (upstream.status === 403) {
          return jsonResponse({
            status: "error",
            code: "ai_upstream_model_access_error",
            message: input.outputLocale === "es-419"
              ? "El modelo de IA configurado no está disponible."
              : input.outputLocale === "en-US"
              ? "The configured AI model is not available."
              : "AI 모델 접근 권한을 확인해야 합니다.",
          }, 502);
        }
        if (upstream.status === 429 && upstreamCode === "insufficient_quota") {
          return jsonResponse({
            status: "error",
            code: "ai_upstream_quota_exceeded",
            message: input.outputLocale === "es-419"
              ? "Es necesario revisar el límite de uso o la facturación del servicio de IA."
              : input.outputLocale === "en-US"
              ? "The AI service quota or billing configuration needs attention."
              : "AI API 사용 한도 또는 결제 설정을 확인해야 합니다.",
          }, 502);
        }
        if (upstream.status === 429) {
          return jsonResponse({
            status: "error",
            code: "ai_upstream_rate_limited",
            message: input.outputLocale === "es-419"
              ? "El servicio de IA está ocupado. Inténtalo de nuevo en un momento."
              : input.outputLocale === "en-US"
              ? "The AI service is busy. Please try again shortly."
              : "AI 요청이 많습니다. 잠시 후 다시 시도해 주세요.",
          }, 502);
        }
        if (upstream.status === 404 || upstreamCode === "model_not_found") {
          return jsonResponse({
            status: "error",
            code: "ai_upstream_model_error",
            message: input.outputLocale === "es-419"
              ? "Es necesario revisar el modelo de IA configurado."
              : input.outputLocale === "en-US"
              ? "The configured AI model needs attention."
              : "AI 모델 설정을 확인해야 합니다.",
          }, 502);
        }
        return jsonResponse({
          status: "error",
          code: "ai_upstream_error",
          message: input.outputLocale === "es-419"
            ? "No se puede crear el borrador de la receta en este momento."
            : input.outputLocale === "en-US"
            ? "The AI recipe draft cannot be created right now."
            : "AI 레시피 보강을 지금 처리할 수 없습니다.",
        }, 502);
      }

      if (!upstream?.ok) {
        return jsonResponse({
          status: "error",
          code: "ai_upstream_error",
          message: input.outputLocale === "es-419"
            ? "No se puede crear el borrador de la receta en este momento."
            : input.outputLocale === "en-US"
            ? "The AI recipe draft cannot be created right now."
            : "AI 레시피 보강을 지금 처리할 수 없습니다.",
        }, 502);
      }
      const payload = await upstream.json().catch(() => null);
      requestTokens = Number.isInteger(payload?.usage?.prompt_tokens)
        ? payload.usage.prompt_tokens
        : 0;
      responseTokens = Number.isInteger(payload?.usage?.completion_tokens)
        ? payload.usage.completion_tokens
        : 0;
      const raw = payload?.choices?.[0]?.message?.content;
      let result = parseModelContent(raw, input);
      if (!result) {
        return jsonResponse({
          status: "error",
          code: "ai_response_invalid",
          message: input.outputLocale === "es-419"
            ? "La IA devolvió un borrador de receta no válido."
            : input.outputLocale === "en-US"
            ? "The AI returned an invalid recipe draft."
            : "AI 응답 형식이 올바르지 않습니다.",
        }, 502);
      }
      let qualityIssues = draftQualityIssues(result, input);
      finalIngredientCount = result.ingredientDetails.length;
      finalStepCount = result.stepDetails.length;
      if (qualityIssues.length > 0) {
        repairAttempted = true;
        const generationOptions = /^(gpt-[56](?:\.|-|$))/.test(usedModel)
          ? { reasoning_effort: "low" }
          : { temperature: 0.2 };
        const repairResponse = await fetchOpenAi(
          "https://api.openai.com/v1/chat/completions",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${apiKey}`,
            },
            body: JSON.stringify({
              model: usedModel,
              ...generationOptions,
              max_completion_tokens: 4000,
              response_format: { type: "json_object" },
              messages: [
                {
                  role: "system",
                  content: `Repair one ${outputLanguage(input.outputLocale)} recipe draft using only the supplied YouTube evidence. Exclude advertising and commerce content. Keep every user-facing field in this language.`,
                },
                {
                  role: "user",
                  content: repairPrompt(input, result, qualityIssues),
                },
              ],
            }),
          },
        );
        if (repairResponse.ok) {
          const repairPayload = await repairResponse.json().catch(() => null);
          requestTokens += Number.isInteger(repairPayload?.usage?.prompt_tokens)
            ? repairPayload.usage.prompt_tokens
            : 0;
          responseTokens += Number.isInteger(
              repairPayload?.usage?.completion_tokens,
            )
            ? repairPayload.usage.completion_tokens
            : 0;
          const repairRaw = repairPayload?.choices?.[0]?.message?.content;
          const repaired = parseModelContent(repairRaw, input);
          if (repaired) {
            const repairedIssues = draftQualityIssues(repaired, input);
            if (repairedIssues.length < qualityIssues.length) {
              result = repaired;
              qualityIssues = repairedIssues;
              finalIngredientCount = repaired.ingredientDetails.length;
              finalStepCount = repaired.stepDetails.length;
            }
          }
        } else {
          logError({
            event: "openai_recipe_repair_failed",
            function: "ai_youtube_recipe_assistant",
            status: repairResponse.status,
            model: usedModel,
          });
        }
      }
      if (qualityIssues.length > 0) {
        if (reservation && options.saveIncompleteDraft) {
          await options.saveIncompleteDraft({
            userId: reservation.userId,
            input,
            draft: result,
            reasonCodes: qualityIssues,
          });
        }
        return jsonResponse({
          status: "error",
          code: "ai_draft_incomplete",
          message: input.outputLocale === "es-419"
            ? "El borrador necesita datos de cocina verificados; no se descontó este intento. Agrega subtítulos o edítalo en Recetas excluidas."
            : input.outputLocale === "en-US"
            ? "The draft still needs verified recipe details, so this attempt was not charged. Add captions or edit it under Excluded recipes."
            : "초안에 확인할 조리 정보가 남아 있어 사용 횟수를 차감하지 않았습니다. 자막을 추가하거나 검색 제외 레시피에서 직접 편집할 수 있습니다.",
        }, 422);
      }
      result = addQualityWarnings(result, input.outputLocale);
      generationSucceeded = true;
      return jsonResponse({
        status: "ok",
        data: {
          ...result,
          references: [{
            type: input.selectedVideo.transcript
              ? "user_transcript"
              : "youtube_description",
            title: input.selectedVideo.inferredRecipeTitle,
            channelName: input.selectedVideo.channelName,
            youtubeUrl: input.selectedVideo.youtubeUrl,
          }],
        },
      });
    } catch (error) {
      logError({
        event: "openai_recipe_request_exception",
        function: "ai_youtube_recipe_assistant",
        errorType: error instanceof Error ? error.name : "unknown",
        model,
        fallbackModel,
      });
      return jsonResponse({
        status: "error",
        code: "ai_request_failed",
        message: input.outputLocale === "es-419"
          ? "Ocurrió un error al crear el borrador de la receta."
          : input.outputLocale === "en-US"
          ? "An error occurred while creating the AI recipe draft."
          : "AI 레시피 보강 중 오류가 발생했습니다.",
      }, 502);
    } finally {
      if (reservation && options.finishUsage) {
        await options.finishUsage(
          reservation,
          generationSucceeded,
          usedModel,
          requestTokens,
          responseTokens,
        ).catch((error) => {
          logError({
            event: "ai_usage_finalization_failed",
            function: "ai_youtube_recipe_assistant",
            errorType: error instanceof Error ? error.name : "unknown",
          });
        });
      }
      if (reservation && options.recordMetrics) {
        await options.recordMetrics({
          reservationId: reservation.id,
          userId: reservation.userId,
          succeeded: generationSucceeded,
          ingredientCount: finalIngredientCount,
          stepCount: finalStepCount,
          hadDescription: descriptionInfo.recipeEvidence.length > 0,
          hadTranscript: Boolean(input.selectedVideo.transcript),
          repairAttempted,
          promotionalLinesRemoved: descriptionInfo.removedLineCount,
        }).catch((error) => {
          logError({
            event: "youtube_recipe_metrics_failed",
            function: "ai_youtube_recipe_assistant",
            errorType: error instanceof Error ? error.name : "unknown",
          });
        });
      }
    }
  };
}
