from pathlib import Path
import json
import subprocess
import sys
import shutil

root = Path(__file__).resolve().parents[2]
container = 'supabase_db_k-youtube'
def sql(query):
    result = subprocess.run(['docker','exec','-i',container,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','supabase_admin','-d','postgres'],
        input=query, text=True, encoding='utf-8', capture_output=True, cwd=root)
    if result.returncode:
        # SQL is repository DDL, with no supplied customer records or secrets.
        print(result.stderr[-2000:])
        raise RuntimeError('Local SQL failed')
    return result.stdout.strip()

state = subprocess.check_output(['docker','inspect','--format','{{.Name}}|{{.State.Running}}',container],text=True).strip()
assert state == '/supabase_db_k-youtube|true'
history = json.loads(sql("select coalesce(json_agg(version order by version),'[]') from supabase_migrations.schema_migrations"))
assert '0035' in history
targets = [{'version': p.name.split('_',1)[0], 'name':p.stem.split('_',1)[1]}
    for p in sorted((root/'supabase/migrations').glob('*.sql'))
    if '0035' < p.name.split('_',1)[0] <= '0058' and p.name[:4] not in {'0047','0048','0057'}]
pending = [row for row in targets if row['version'] not in history]
if pending:
    source = "BEGIN; SET LOCAL ROLE postgres; SET LOCAL lock_timeout='8s'; SET LOCAL statement_timeout='60s';\n"
    for row in pending:
        version, name = row['version'], row['name']
        files = list((root/'supabase/migrations').glob(version+'_*.sql'))
        assert len(files) == 1
        body = files[0].read_text(encoding='utf-8-sig')
        delimiter = '$web_local_'+version+'$'
        assert delimiter not in body
        source += body + f"\nINSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES ('{version}','{name}',ARRAY[{delimiter}{body}{delimiter}]);\n"
    source += "NOTIFY pgrst,'reload schema'; COMMIT;"
    sql(source)

cli = shutil.which('supabase') or 'C:/Users/ADMIN/tools/supabase/supabase.exe'
status = subprocess.run([str(cli),'status','-o','json'],capture_output=True,text=True,encoding='utf-8',cwd=root)
assert status.returncode == 0, 'Local status unavailable'
runtime = json.loads(status.stdout)
assert runtime['API_URL'] in ('http://127.0.0.1:54321','http://localhost:54321')
env_file = root/'.env.local'
if not env_file.exists():
    env_file.write_text('APP_ENV=local\nSUPABASE_URL_LOCAL='+runtime['API_URL']+'\nSUPABASE_ANON_KEY_LOCAL='+runtime['ANON_KEY']+'\n',encoding='utf-8')
report = {'environment':'local-only','container':container,'appliedMigrations':[r['version'] for r in pending],
          'clientConfigReady':True,'productionModified':False}
(root/'.artifacts/web-local-setup.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
