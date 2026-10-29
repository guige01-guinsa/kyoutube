import {assertEquals} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {inspectRecipeDescription} from './recipe_source_eligibility.mjs';

Deno.test('complete Korean, English and Spanish descriptions share eligibility without AI',()=>{
 for(const description of [
  '[재료]\n김치 200g\n물 2컵\n[만드는 법]\n김치를 넣습니다.\n물을 붓고 끓입니다.',
  'Ingredients\npork 200g\nwater 2 cups\nDirections\nAdd pork.\nBoil with water.',
  'Ingredientes\n200 gramos de carne\n2 tazas de agua\nPreparación\nAgrega la carne.\nCocina con agua.',
 ]) assertEquals(inspectRecipeDescription(description),{eligible:true,reason:'readable_description'});
});
Deno.test('links and titles are not evidence of a readable complete recipe',()=>{
 for(const description of [undefined,'','김치찌개 레시피 2인분, 맛있게 끓이세요.',
  '[재료]\n김치 200g\n물 2컵',
  '[재료]\nhttps://example.test/200g\nhttps://example.test/2cups\n[만드는 법]\n넣습니다.\n끓입니다.',
  'Recipe: https://example.test/recipe\nSubscribe to my newsletter.',
 ]) assertEquals(inspectRecipeDescription(description).eligible,false);
 assertEquals(inspectRecipeDescription('조리법: https://example.test/recipe').reason,'external_recipe_required');
});
Deno.test('promotional link does not hide a recipe already readable in the description',()=>{
 assertEquals(inspectRecipeDescription('[재료]\n김치 200g\n물 2컵\n[만드는 법]\n김치를 넣습니다.\n끓입니다.\nhttps://example.test/book').eligible,true);
});
