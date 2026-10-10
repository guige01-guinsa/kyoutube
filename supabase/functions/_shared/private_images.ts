import { fetchWithTimeout } from "./http.ts";
export function creatorImagePath(value: unknown, origin: string): string | null {
 if(typeof value!=="string")return null;
 try {
 const u=new URL(value); if(u.origin!==new URL(origin).origin)return null;
 const match=u.pathname.match(/^\/storage\/v1\/object\/(?:public|sign|authenticated)\/creator-recipe-images\/(.+)$/);
 if(!match)return null;
 const path=decodeURIComponent(match[1]);
 if(path.split('/').some(x=>!x||x==='.'||x==='..'))return null;
 return path;
 }catch{return null;}
}
export async function creatorImageForOwner(row: Record<string,unknown>,userId:string):Promise<Record<string,unknown>> {
 const origin=Deno.env.get('SUPABASE_URL')??'';
 const path=creatorImagePath(row.image_path,origin); if(!path)return row;
 if(!path.startsWith(userId+'/'))return {...row,image_path:null};
 try {
 const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
 const response=await fetchWithTimeout(`${origin}/storage/v1/object/sign/creator-recipe-images/${path.split('/').map(encodeURIComponent).join('/')}`,{
 method:'POST',headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({expiresIn:600})});
 if(!response.ok){await response.body?.cancel();return {...row,image_path:null};}
 const data=await response.json();
 return {...row,image_path:typeof data.signedURL==='string'?`${origin}/storage/v1${data.signedURL}`:null};
 }catch{return {...row,image_path:null};}
}
