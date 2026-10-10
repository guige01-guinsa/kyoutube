export type OutputLocale = "ko-KR" | "en-US" | "es-419";

export function outputLanguage(locale: OutputLocale): string {
  return locale === "es-419" ? "Latin American Spanish"
    : locale === "en-US" ? "US English" : "Korean";
}

export function localizedMessage(
  locale: unknown, ko: string, en: string, es: string,
): string {
  return locale === "es-419" ? es : locale === "en-US" ? en : ko;
}
