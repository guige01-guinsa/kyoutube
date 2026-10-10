// Runs only inside the isolated database created by business_workspaces_contract.cjs.
module.exports=async({db,q,scalar,denied,ok,login,workspace,owner,buyer,cook,owner2,second,crypto,samples})=>{
 const profileSql='select public.business_member_profile_update($1,$2,$3,$4,$5,$6)';
 await login(owner);
 let before=(await q('select * from public.business_members where workspace_id=$1 and user_id=$2',[workspace,buyer]))[0];
 await q(profileSql,[workspace,buyer,'  Kim Buyer  ','  Purchasing lead  ',' buyer@example.test ',Number(before.profile_revision)]);
 let after=(await q('select * from public.business_members where workspace_id=$1 and user_id=$2',[workspace,buyer]))[0];
 ok(after.display_name==='Kim Buyer' && after.job_title==='Purchasing lead' && after.work_contact==='buyer@example.test','owner can edit and trim staff profile');
 ok(JSON.stringify(before.permissions)===JSON.stringify(after.permissions) && after.active===before.active,'profile update preserves grants and suspension');
 ok(Number(after.profile_revision)===Number(before.profile_revision)+1,'profile revision increments');
 await denied(profileSql,[workspace,buyer,'Old name','','',Number(before.profile_revision)],'BUSINESS_STALE','stale profile cannot overwrite newer details');
 const revision=Number(after.profile_revision);
 await q(profileSql,[workspace,buyer,'Kim Buyer','Purchasing lead','buyer@example.test',revision]);
 ok(Number(await scalar('select profile_revision from public.business_members where workspace_id=$1 and user_id=$2',[workspace,buyer]))===revision,'identical profile save is idempotent');
 for (const [name,title,contact,label] of [
   ['','Lead','','blank name'],['X'.repeat(121),'','','oversized name'],
   ['Valid','X'.repeat(81),'','oversized title'],['Valid','','X'.repeat(121),'oversized contact'],
   ['Valid','Bad\nTitle','','control characters']])
   await denied(profileSql,[workspace,buyer,name,title,contact,revision],'BUSINESS_PROFILE_INVALID','reject '+label);
 await denied(profileSql,[workspace,buyer,null,'','',revision],'BUSINESS_PROFILE_INVALID','null name rejected');
 await denied(profileSql,[workspace,crypto.randomUUID(),'Missing','','',1],'BUSINESS_NOT_FOUND','missing member cannot be created through profile update');
 const self=(await q('select * from public.business_members where workspace_id=$1 and user_id=$2',[workspace,owner]))[0];
 await q(profileSql,[workspace,owner,'Owner display','Owner','office@example.test',Number(self.profile_revision)]);
 ok(await scalar('select owner_id=$1 from public.business_workspaces where id=$2',[owner,workspace]),'owner profile edit preserves workspace ownership');
 ok(Number(await scalar("select count(*) from public.business_access_events where workspace_id=$1 and subject_id=$2 and action='profile'",[workspace,buyer]))===1,'profile edit has an owner audit event; retry does not duplicate it');
 await denied('update public.business_members set job_title=$1 where workspace_id=$2',['Hacked',workspace],'42501','direct profile write denied even to owner');
 await login(cook);
 await denied(profileSql,[workspace,cook,'Promoted','Owner','',1],'BUSINESS_DENIED','staff cannot edit own profile through owner RPC');
 ok(Number(await scalar('select count(*) from public.business_members where workspace_id=$1 and user_id=$2',[workspace,owner]))===0,'staff cannot read another member contact');
 ok(Number(await scalar('select count(*) from public.business_members where workspace_id=$1 and user_id=$2',[workspace,cook]))===1,'active staff can still read own profile');
 await login(owner2);
 await denied(profileSql,[workspace,buyer,'Foreign','','',revision],'BUSINESS_DENIED','another owner cannot edit this workspace');
 await denied(profileSql,[second,buyer,'Foreign','','',revision],'BUSINESS_NOT_FOUND','member ID cannot be moved between workspaces');
 await login(owner,true);
 await denied(profileSql,[workspace,buyer,'Anonymous','','',revision],'BUSINESS_DENIED','anonymous authenticated identity rejected');
 await db.exec('reset role;set role anon');
 await denied(profileSql,[workspace,buyer,'Anon','','',revision],'42501','anonymous role cannot call profile RPC');
 await db.exec('reset role');
 ok(!await scalar("select has_function_privilege('authenticated','public.business_member_profile_revision()','EXECUTE')"),'internal revision trigger is not callable by members');
 // A legacy invitation can change display_name too; the new revision must still protect open forms.
 await q("update public.business_members set display_name='Changed by invitation' where workspace_id=$1 and user_id=$2",[workspace,buyer]);
 await login(owner);
 await denied(profileSql,[workspace,buyer,'Stale editor','','',revision],'BUSINESS_STALE','legacy name changes invalidate open profile editors');
 if(samples) {
  const admin=crypto.randomUUID(),tester=crypto.randomUUID();
  await db.exec('reset role');
  await q("insert into auth.users values($1,'profile-admin@example.test',now()),($2,'profile-tester@example.test',now())",[admin,tester]);
  await q("insert into public.profiles values($1,'admin')",[admin]);
  async function asAdmin(){
   await db.exec('reset role');
   await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[admin,JSON.stringify({sub:admin,aal:'aal2'})]);
   await db.exec('set role authenticated');
  }
  await asAdmin();
  const campaign=await scalar('select public.admin_business_test_create($1,14,$2)',['Profile test','members']);
  await login(tester);
  const practice=await scalar('select public.business_test_start($1,$2,$3)',[campaign,'ko','Tester']);
  await q(profileSql,[practice,tester,'Practice owner','Chef','',1]);ok(true,'practice owner can manage profile while campaign is active');
  await asAdmin();await q('select public.admin_business_test_end($1)',[campaign]);
  await login(tester);
  await denied(profileSql,[practice,tester,'Closed','','',2],'BUSINESS_DENIED','ended practice cannot update staff profiles');
  await asAdmin();await q('select public.admin_business_test_cleanup($1)',[campaign]);
 }
 await db.exec('reset role');
};