// Conservative guard for quantities, measured amounts and explicit package types.
// It does not establish semantic equivalence of all product attributes; users
// still review wording before applying it.
export function purchaseFacts(value: string): string {
  const normalized = value.normalize("NFKC").toLowerCase();
  const numbers = [...normalized.matchAll(/[+-]?\d+(?:[.,]\d+)*/g)].map((m) =>
    m[0]
  ).sort();
  const measures = [
    ...normalized.matchAll(
      /\d+(?:[.,]\d+)*\s*(?:kg|mg|ml|cl|g|l|oz|lb|킬로그램|그램|밀리리터|리터)(?![a-z])/g,
    ),
  ]
    .map((m) => m[0].replace(/\s/g, "")).sort();
  const aliases: Record<string, string> = {
    봉지: "봉",
    상자: "박스",
    bags: "bag",
    boxes: "box",
    packs: "pack",
    bottles: "bottle",
    cans: "can",
    cases: "case",
    nets: "net",
  };
  const packages = [
    ...normalized.matchAll(
      /(?<![가-힣])(?:봉지|포대|박스|상자|묶음|봉|망|팩|통|병|캔|개|판)(?![가-힣])|\b(?:bags?|boxes|box|packs?|bottles?|cans?|cases?|nets?)\b/g,
    ),
  ]
    .map((m) => aliases[m[0]] ?? m[0]).sort();
  return JSON.stringify({ numbers, measures, packages });
}
