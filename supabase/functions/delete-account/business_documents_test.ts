import { deleteBusinessDocuments } from './business_documents.ts';
const owner='61000000-0000-4000-8000-000000000001';
for(const kind of ['success','traversal','list error','remove error']) {
  Deno.test(`private certificate cleanup: ${kind}`,async()=>{
    const removed:string[]=[];
    const admin={storage:{from:(name:string)=>{
      if(name!=='purchase-business-documents')throw Error('wrong bucket');
      return {list:async(prefix:string)=>{
        if(prefix!==owner)throw Error('wrong owner');
        return {data:[{id:'1',name:kind==='traversal'?'../other.png':`${owner}.png`}],error:kind==='list error'?Error('offline'):null};
      },remove:async(paths:string[])=>{removed.push(...paths);return {error:kind==='remove error'?Error('offline'):null};}};
    }}};
    let failed=false;
    try{await deleteBusinessDocuments(admin,owner);}catch{failed=true;}
    if(failed!==(kind!=='success'))throw Error('wrong outcome');
    if(kind==='success'&&JSON.stringify(removed)!==JSON.stringify([`${owner}/${owner}.png`]))throw Error('wrong files');
    if((kind==='traversal'||kind==='list error')&&removed.length)throw Error('unsafe cleanup');
  });
}
