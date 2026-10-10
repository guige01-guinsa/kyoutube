// Read-only, deterministic audit of v54's acceptance gate. All model outputs
// below are deliberately injected fixtures, NOT observed live AI responses.
import { createYoutubeRecipeAssistantHandler } from '../../supabase/functions/ai_youtube_recipe_assistant/handler.ts';

const source = {
  outputLocale:'en-US',
  recipe:{title:'Roasted carrots',youtubeUrl:'https://www.youtube.com/watch?v=abc123XYZ00'},
  selectedVideo:{videoId:'abc123XYZ00',youtubeUrl:'https://www.youtube.com/watch?v=abc123XYZ00',
    originalTitle:'Roasted carrots recipe',inferredRecipeTitle:'Roasted carrots',channelName:'Synthetic audit kitchen',durationSec:240,
    description:'Serves 2. Ingredients: 300 g carrots, 15 ml olive oil, 2 g salt. Cut carrots. Toss with oil and salt. Roast at 200 C for 20 minutes.'},
};
const base = {
  title:'Roasted carrots',summary:'Roasted carrots with oil and salt.',servings:2,cookTimeMinutes:20,
  ingredients:[{name:'carrots',quantity:'300',unit:'g',status:'confirmed'},
    {name:'olive oil',quantity:'15',unit:'ml',status:'confirmed'},
    {name:'salt',quantity:'2',unit:'g',status:'confirmed'}],
  steps:[{instruction:'Cut the carrots.',status:'confirmed',ingredientNames:['carrots']},
    {instruction:'Toss with olive oil and salt.',status:'confirmed',ingredientNames:['carrots','olive oil','salt']},
    {instruction:'Roast at 200 C for 20 minutes.',status:'confirmed',durationMinutes:20,ingredientNames:['carrots']}],
  warnings:[],
};
type Draft = Record<string,unknown>;
const cases: {id:string;expected:'accept'|'reject';draft:Draft;emptyEvidence?:boolean}[] = [
  {id:'faithful_control',expected:'accept',draft:base},
  {id:'wrong_quantity',expected:'reject',draft:{...base,ingredients:base.ingredients.map(x=>x.name==='salt'?{...x,quantity:'200'}:x)}},
  {id:'wrong_heat_and_time',expected:'reject',draft:{...base,cookTimeMinutes:2,steps:[...base.steps.slice(0,2),{instruction:'Roast at 350 C for 2 minutes.',status:'confirmed',durationMinutes:2,ingredientNames:['carrots']}]}},
  {id:'all_evidence_unverified',expected:'reject',draft:{...base,ingredients:base.ingredients.map(x=>({...x,status:'unverified'})),steps:base.steps.map(x=>({...x,status:'unverified'}))}},
  {id:'duplicate_items_and_steps',expected:'reject',draft:{...base,ingredients:Array(3).fill(base.ingredients[0]),steps:Array(3).fill(base.steps[0])}},
  {id:'korean_output_for_english_request',expected:'reject',draft:{...base,title:'당근구이',summary:'당근을 굽는 요리입니다.',ingredients:['당근 300g','올리브유 15ml','소금 2g'],steps:['당근을 자릅니다.','기름과 소금을 넣습니다.','200도에서 20분 굽습니다.']}},
  {id:'empty_summary_client_rejects',expected:'reject',draft:{...base,summary:''}},
  {id:'unknown_ingredient_link',expected:'reject',draft:{...base,steps:base.steps.map(x=>({...x,ingredientNames:['butter']}))}},
  {id:'missing_source_evidence',expected:'reject',draft:base,emptyEvidence:true},
  {id:'valid_two_ingredient_recipe',expected:'accept',draft:{title:'Banana milk',summary:'Blend banana with milk.',ingredients:['banana 1','milk 200 ml'],steps:['Peel the banana.','Blend with milk.'],warnings:[]}},
];
const results=[];
for(const item of cases){
  let calls=0,recordedSuccess:boolean|null=null;
  const handler=createYoutubeRecipeAssistantHandler({
    getEnv:n=>n==='OPENAI_API_KEY'?'synthetic-test-only':undefined,
    fetchOpenAi:async()=>{calls++;return new Response(JSON.stringify({choices:[{message:{content:JSON.stringify(item.draft)}}],usage:{prompt_tokens:0,completion_tokens:0}}),{status:200});},
    reserveUsage:async()=>({id:'audit',userId:'audit',planCode:'free',recipeModel:'gpt-4o-mini'}),
    finishUsage:async(_,succeeded)=>{recordedSuccess=succeeded;},logError:()=>{},
  });
  const requestBody=structuredClone(source);
  if(item.emptyEvidence) requestBody.selectedVideo.description='';
  if(item.id==='valid_two_ingredient_recipe') {
    requestBody.recipe.title='Banana milk';
    requestBody.selectedVideo.originalTitle='Banana milk recipe';
    requestBody.selectedVideo.inferredRecipeTitle='Banana milk';
    requestBody.selectedVideo.description='Blend 1 peeled banana with 200 ml milk. Peel the banana, then blend with milk.';
  }
  const response=await handler(new Request('https://local.test/ai_youtube_recipe_assistant',{method:'POST',headers:{Authorization:'Bearer synthetic-test-only','Content-Type':'application/json'},body:JSON.stringify(requestBody)}));
  const body=await response.json();
  const accepted=response.status===200&&body.status==='ok';
  results.push({id:item.id,expected:item.expected,httpStatus:response.status,accepted,recordedSuccess,modelCalls:calls,
    matchesDesiredGate:accepted===(item.expected==='accept'),
    clientWouldAcceptShape:accepted&&Boolean(body.data?.summary)&&body.data.ingredients.length>0&&body.data.steps.length>0});
}
console.log(JSON.stringify({kind:'synthetic_acceptance_gate_audit_not_live_success_rate',results},null,2));
