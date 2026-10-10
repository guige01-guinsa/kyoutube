"""Exercise two authenticated clients against the existing local v65 backend.
Creates isolated synthetic accounts; removes them in finally. Never targets production.
"""
from pathlib import Path
import json, subprocess, urllib.request, urllib.error, uuid, copy
ROOT=Path(__file__).resolve().parents[2]
CLI='C:/Users/ADMIN/tools/supabase/supabase.exe'

def main():
    status=subprocess.run([CLI,'status','-o','json'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',check=True)
    cfg=json.loads(status.stdout)
    base=cfg['API_URL']
    assert base in ('http://127.0.0.1:54321','http://localhost:54321'), 'Local endpoint required'
    anon, admin=cfg['ANON_KEY'],cfg['SERVICE_ROLE_KEY']
    checks=[]; users=[]
    def call(path, payload=None, token=None, method=None, expected=200):
        data=None if payload is None else json.dumps(payload).encode()
        req=urllib.request.Request(base+path,data=data,method=method or ('POST' if data else 'GET'),headers={
            'apikey':anon,'Authorization':'Bearer '+(token or anon),'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(req,timeout=30) as r: code,body=r.status,r.read()
        except urllib.error.HTTPError as e: code,body=e.code,e.read()
        result=json.loads(body) if body else None
        assert code == expected, 'Unexpected HTTP '+str(code)+' for '+path.split('?')[0]+': '+str(result.get('message',result.get('msg','')) if isinstance(result,dict) else '')
        return result
    def rpc(name,payload,token,expected=200): return call('/rest/v1/rpc/'+name,payload,token,expected=expected)
    def sql(source):
        r=subprocess.run(['docker','exec','-i','supabase_db_k-youtube','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','supabase_admin','-d','postgres'],input=source,capture_output=True,text=True,encoding='utf-8')
        assert r.returncode==0, 'Local fixture SQL failed: '+r.stderr[-600:]
    password='Local-only-test-account-65!'
    try:
        suffix=uuid.uuid4().hex[:10]
        for n in range(2):
            email=f'workspace-{suffix}-{n}@example.test'
            u=call('/auth/v1/admin/users',{'email':email,'password':password,'email_confirm':True},admin)
            users.append(u['id'])
        def session(n):
            return call('/auth/v1/token?grant_type=password',{'email':f'workspace-{suffix}-{n}@example.test','password':password})['access_token']
        pc,mobile,other=session(0),session(0),session(1)
        rid=str(uuid.uuid4()); uid=users[0]
        sql(f"SET ROLE postgres; INSERT INTO public.profiles(id,role) VALUES ('{uid}','creator') ON CONFLICT(id) DO NOTHING; INSERT INTO public.recipes_creator(id,author_id,title) VALUES ('{rid}','{uid}','Local workspace test'); INSERT INTO public.member_entitlements(user_id,plan_code,status,source,started_at,valid_until) VALUES ('{uid}','business_monthly','active','admin',now(),now()+interval '1 day') ON CONFLICT(user_id) DO UPDATE SET plan_code='business_monthly',status='active',source='admin',started_at=now(),valid_until=now()+interval '1 day';")
        assert rpc('has_chef_paid_access',{},pc) is True
        assert rpc('has_chef_paid_access',{},other) is False
        checks.append('server_membership_gate')
        doc={'schema':1,'title':'Local workspace test','steps':'Roast carrots','notes':'','currency':'KRW','baseServings':4,'targetServings':10,'extraCost':1000,'inputWeight':1000,'outputWeight':750,
          'ingredients':[{'id':'carrots','name':'Carrots','quantity':800,'unit':'g','purchaseQuantity':1,'purchaseUnit':'kg','purchasePrice':8000,'yieldPercent':80}]}
        def save(d,revision,token):return rpc('save_chef_workspace',{'p_recipe_id':rid,'p_document':d,'p_expected_revision':revision,'p_version_label':None,'p_version_note':''},token)
        assert save(doc,0,pc)==1
        second=rpc('get_chef_workspace',{'p_recipe_id':rid},mobile)[0]
        assert second['document']['targetServings']==10 and second['revision']==1
        changed=copy.deepcopy(doc); changed['targetServings']=20
        assert save(changed,1,mobile)==2
        stale=rpc('save_chef_workspace',{'p_recipe_id':rid,'p_document':doc,'p_expected_revision':1,'p_version_label':None,'p_version_note':''},pc,expected=400)
        assert 'CHEF_REVISION_CONFLICT' in stale['message']
        assert rpc('get_chef_workspace',{'p_recipe_id':rid},pc)[0]['document']['targetServings']==20
        assert rpc('get_chef_workspace',{'p_recipe_id':rid},other)==[]
        checks.extend(['two_sessions_shared_chef_save','stale_write_rejected','other_user_chef_isolation'])
        key=str(uuid.uuid4())
        args={'p_source_recipe_id':'creator:'+rid,'p_items':[{'name':'Carrots','ingredient_text':'Carrots 800 g (recipe only)','quantity':0.125,'unit':'kg'},{'name':'Salt','ingredient_text':'Salt to taste','quantity':None,'unit':None}],'p_idempotency_key':key}
        created=rpc('create_kitchen_shopping_list',args,pc)[0]
        lid=created['list_id']
        rows=call('/rest/v1/kitchen_shopping_items?list_id=eq.'+lid+'&select=name,quantity,unit,ingredient_text',token=mobile)
        byname={r['name']:r for r in rows}
        assert byname['Carrots']['quantity']==0.125 and byname['Carrots']['unit']=='kg'
        assert byname['Salt']['quantity'] is None
        assert rpc('create_kitchen_shopping_list',args,mobile)[0]['replayed'] is True
        assert call('/rest/v1/kitchen_shopping_items?list_id=eq.'+lid+'&select=name',token=other)==[]
        checks.extend(['shared_purchase_precision','unknown_purchase_quantity_allowed','shopping_idempotency','other_user_shopping_isolation'])
    finally:
        for uid in users: call('/auth/v1/admin/users/'+uid,token=admin,method='DELETE')
    report={'environment':'local-only','checks':checks,'passed':len(checks),'fixture_accounts_removed':len(users),'production_modified':False}
    (ROOT/'.artifacts/web-backend-verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))
if __name__=='__main__':main()
