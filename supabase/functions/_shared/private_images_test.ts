import {assertEquals} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {creatorImagePath,creatorImageForOwner} from './private_images.ts';
Deno.test('private images reject foreign hosts and traversal',()=>{
 assertEquals(creatorImagePath('https://evil.invalid/storage/v1/object/public/creator-recipe-images/u/a.jpg','https://unit.invalid'),null);
 assertEquals(creatorImagePath('https://unit.invalid/storage/v1/object/public/creator-recipe-images/u/%2E%2E%2Fa.jpg','https://unit.invalid'),null);
 assertEquals(creatorImagePath('https://unit.invalid/storage/v1/object/sign/creator-recipe-images/u/a.jpg?token=old','https://unit.invalid'),'u/a.jpg');
});
Deno.test('image signing is owner bound and short lived',async()=>{
 const old=Deno.env.get('SUPABASE_URL'),original=globalThis.fetch;
 Deno.env.set('SUPABASE_URL','https://unit.invalid');
 let calls=0;
 globalThis.fetch=(_input,init)=>{
 calls++;assertEquals(JSON.parse(String(init?.body)),{expiresIn:600});
 return Promise.resolve(Response.json({signedURL:'/object/sign/creator-recipe-images/owner/a.jpg?token=test'}));
 };
 try {
 const row={image_path:'https://unit.invalid/storage/v1/object/public/creator-recipe-images/owner/a.jpg'};
 assertEquals((await creatorImageForOwner(row,'other')).image_path,null);assertEquals(calls,0);
 assertEquals((await creatorImageForOwner(row,'owner')).image_path,'https://unit.invalid/storage/v1/object/sign/creator-recipe-images/owner/a.jpg?token=test');assertEquals(calls,1);
 }finally{globalThis.fetch=original;old===undefined?Deno.env.delete('SUPABASE_URL'):Deno.env.set('SUPABASE_URL',old);}
});
