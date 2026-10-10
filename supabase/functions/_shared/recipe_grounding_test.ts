import {recipeGroundingIssues} from './recipe_grounding.ts';
function check(v:unknown){if(!v)throw Error('Grounding assertion failed');}
const draft={summary:'Roasted carrots.',ingredientDetails:[{name:'carrots',quantity:'300',unit:'g',status:'confirmed'}],
  stepDetails:[{instruction:'Roast at 200 C for 20 minutes.',status:'confirmed',ingredientNames:['carrots']}]};
const source='300 g carrots. Roast at 200 C for 20 minutes.';
Deno.test('explicit ingredient measures compare compatible metrics only',()=>{
  check(recipeGroundingIssues(draft,source,'en-US').length===0);
  check(recipeGroundingIssues({...draft,ingredientDetails:[{...draft.ingredientDetails[0],quantity:'200'}]},source,'en-US').includes('source_ingredient_quantity_conflict'));
  check(recipeGroundingIssues({...draft,ingredientDetails:[{...draft.ingredientDetails[0],quantity:'0.3',unit:'kg'}]},source,'en-US').length===0);
  check(recipeGroundingIssues(draft,'carrots: 0.3 kg. Roast at 200 C for 20 minutes.','en-US').length===0);
  check(!recipeGroundingIssues(draft,'300 ml carrots.','en-US').includes('source_ingredient_quantity_conflict'));
});
Deno.test('clear cooking measure contradictions fail while equivalent units pass',()=>{
  check(recipeGroundingIssues({...draft,stepDetails:[{...draft.stepDetails[0],instruction:'Roast at 350 C for 2 minutes.'}]},source,'en-US').includes('source_cooking_measure_conflict'));
  check(recipeGroundingIssues({...draft,stepDetails:[{...draft.stepDetails[0],instruction:'Roast at 392 F for 1200 seconds.'}]},source,'en-US').length===0);
});
Deno.test('unknown ingredient links, missing evidence and wrong output script fail',()=>{
  check(recipeGroundingIssues({...draft,stepDetails:[{...draft.stepDetails[0],ingredientNames:['butter']}]},source,'en-US').includes('unknown_step_ingredient'));
  check(recipeGroundingIssues(draft,'','en-US').includes('missing_source_evidence'));
  check(recipeGroundingIssues({...draft,summary:'당근을 넣고 불을 켜서 충분히 익히세요. 잘 섞어서 끓여 맛있게 드세요.',stepDetails:[]},source,'es-419').includes('wrong_output_language'));
});
Deno.test('ambiguous amounts, different names and inferred estimates are not asserted false',()=>{
  check(!recipeGroundingIssues(draft,'200 g carrots or 400 g carrots.','en-US').includes('source_ingredient_quantity_conflict'));
  check(!recipeGroundingIssues(draft,'200 g carrot greens.','en-US').includes('source_ingredient_quantity_conflict'));
  check(!recipeGroundingIssues(draft,'1,000,000 g carrots.','en-US').includes('source_ingredient_quantity_conflict'));
  check(!recipeGroundingIssues({...draft,ingredientDetails:[{...draft.ingredientDetails[0],status:'inferred'}]},'200 g carrots.','en-US').includes('source_ingredient_quantity_conflict'));
});
