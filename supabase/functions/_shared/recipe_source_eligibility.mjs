// Shared by YouTube search (Deno) and the studio worker (Node).
// This is a prerequisite for extracting a recipe, not a correctness verdict.
// No network calls, credentials, AI requests, or persistent video bans.
/** @param {unknown} description */
export function inspectRecipeDescription(description) {
  if (typeof description !== 'string' || !description.trim())
    return {eligible:false,reason:'missing_description'};
  const text=description.normalize('NFKC').replace(/[\u200b-\u200d\ufeff]/g,'');
  const prose=text.replace(/https?:\/\/\S+/gi,'');
  const amounts=prose.match(/(?:\d+(?:[.,/⁄]\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞])\s*(?:kg\b|mg\b|g\b|ml\b|l\b|cups?\b|tbsps?\b|tsps?\b|tablespoons?\b|teaspoons?\b|pounds?\b|ounces?\b|tazas?\b|cucharadas?\b|cucharaditas?\b|gramos?\b|litros?\b|컵|큰술|작은술|스푼|개|대|쪽|포기|근|줌|장)/giu)??[];
  const ingredientHeading=/(재료|ingredients?|ingredientes)/iu.test(prose);
  const instructionHeading=/(만드는\s*(법|방법)|조리\s*(법|방법|순서)|요리\s*순서|directions?|instructions?|method|preparación|preparacion|pasos|elaboración)/iu.test(prose);
  const cookingLines=prose.split(/\r?\n/).filter(line=>/(끓|볶|썰|섞|넣|굽|익|찌|무치|버무|삶|\b(?:add|mix|cook|simmer|boil|stir|slice|chop|fry|bake|heat|añad\w*|agreg\w*|mezcl\w*|cocin\w*|herv\w*|cort\w*|sofr\w*)\b)/iu.test(line));
  const eligible=amounts.length>=2&&ingredientHeading&&instructionHeading&&cookingLines.length>=2;
  return {eligible,reason:eligible?'readable_description':/https?:\/\//i.test(text)?'external_recipe_required':'insufficient_recipe'};
}
