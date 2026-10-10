// Conservative contradiction checks, not a claim of factual recipe verification.
// Compare exact ingredient names and explicit measures only; never guess density,
// serving ratios, translated names, package weights or missing source evidence.
type Draft = {
  summary:string;
  ingredientDetails:{name:string;quantity:string|null;unit:string|null;status:string}[];
  stepDetails:{instruction:string;status:string;ingredientNames:string[]}[];
};
const escape=(s:string)=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
const norm=(s:string)=>s.normalize('NFKC').trim().toLowerCase();
const units:Record<string,[string,number]>={g:['mass',1],kg:['mass',1000],ml:['volume',1],l:['volume',1000]};
const numeric='(?<![0-9.,])([0-9]+(?:[.,][0-9]+)?)';
function number(s:string) {
  const text=/^\d{1,3}(,\d{3})+(\.\d+)?$/.test(s)?s.replaceAll(',',''):s.replace(',','.');
  const n=Number(text);return Number.isFinite(n)?n:null;
}
const same=(a:number,b:number)=>Math.abs(a-b)<=Math.max(1e-6,Math.abs(a)*1e-6);
function cookingMeasures(text:string) {
  const values:{dimension:string;value:number}[]=[];
  for(const m of text.matchAll(/(?<![0-9.,])\b(\d+(?:[.,]\d+)?)\s*(?:°\s*)?(c|f|minutos?|minutes?|min|seconds?|segundos?|sec|분|초)(?![\p{L}])/giu)) {
    const n=number(m[1]);if(n===null)continue;
    const u=m[2].toLowerCase();
    values.push(u==='c'||u==='f'?{dimension:'temperature',value:u==='f'?(n-32)*5/9:n}:
      {dimension:'time',value:/^(sec|seg|초)/.test(u)?n:n*60});
  }
  return values;
}
export function recipeGroundingIssues(draft:Draft,evidence:string,locale:string):string[] {
  const issues=new Set<string>(),source=norm(evidence);
  if(!source)issues.add('missing_source_evidence');
  const prose=draft.summary+' '+draft.stepDetails.map(s=>s.instruction).join(' ');
  const hangul=(prose.match(/[가-힣]/g)??[]).length,latin=(prose.match(/[A-Za-zÁ-ÿ]/g)??[]).length;
  if(locale!=='ko-KR' && hangul>10 && hangul>latin)issues.add('wrong_output_language');
  const names=new Set(draft.ingredientDetails.map(i=>norm(i.name)));
  const measured=cookingMeasures(source);
  for(const step of draft.stepDetails) {
    if(step.ingredientNames.some(n=>!names.has(norm(n))))issues.add('unknown_step_ingredient');
    if(step.status!=='confirmed')continue;
    for(const value of cookingMeasures(step.instruction)) {
      const candidates=measured.filter(v=>v.dimension===value.dimension);
      if(candidates.length && !candidates.some(v=>same(v.value,value.value)))issues.add('source_cooking_measure_conflict');
    }
  }
  for(const item of draft.ingredientDetails) {
    if(item.status!=='confirmed'||!item.quantity||!item.unit)continue;
    const unit=units[norm(item.unit)],amount=number(item.quantity);
    if(!unit||amount===null||!/^\d+(?:[.,]\d+)?$/.test(item.quantity))continue;
    const name=escape(norm(item.name));if(!name)continue;
    const measuredName=[
      new RegExp(numeric+'\\s*(kg|ml|g|l)\\s+'+name+'(?![\\p{L}])','gu'),
      new RegExp('(?<![\\p{L}])'+name+'\\s*[:：]?\\s*'+numeric+'\\s*(kg|ml|g|l)(?![\\p{L}])','gu'),
    ];
    const values:number[]=[];
    for(const re of measuredName)for(const m of source.matchAll(re)) {
      const sourceUnit=units[m[2]],n=number(m[1]);
      if(sourceUnit?.[0]===unit[0]&&n!==null)values.push(n*sourceUnit[1]);
    }
    // Multiple different source amounts may represent portions or alternatives.
    if(values.length && values.every(v=>same(v,values[0])) && !same(amount*unit[1],values[0])) {
      issues.add('source_ingredient_quantity_conflict');
    }
  }
  return [...issues];
}
