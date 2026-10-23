// Synthetic test data, not published food advice or a real restaurant claim.
export const edition = { title:'One more meal',chapters:['One','Two','Three'],captions:Array(6).fill('One more meal.') };
export const creative = {...edition, summary:'A new visitor arrives.', image_prompt:'A fictional cook in a green apron, gentle webtoon style.',
  panels:Array(6).fill('An original fictional kitchen scene.'),translations:{en:{...edition},es:{...edition,title:'Una comida más'}}};
export const researchResponse = {status:'completed',output:[{type:'message',content:[{type:'output_text',text:'Synthetic research memo for local tests only.',annotations:[
  {type:'url_citation',url:'https://example.com/source-one',title:'Test source one'},
  {type:'url_citation',url:'https://example.org/source-two',title:'Test source two'},
]}]}]};
export const research = {text:'Synthetic research memo for local tests only.',checked_at:'2026-10-23T00:00:00Z',status:'human_review_required',
  sources:[{url:'https://example.com/source-one',title:'Test source one'},{url:'https://example.org/source-two',title:'Test source two'}]};
export const draft = {...creative,research};
