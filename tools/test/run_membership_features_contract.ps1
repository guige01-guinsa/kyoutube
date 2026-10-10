$ErrorActionPreference = 'Stop'
$db = 'supabase_db_k-youtube'
$state = & docker inspect --type container --format '{{.Name}}|{{.State.Running}}' $db
if ($LASTEXITCODE -ne 0 -or $state.Trim() -ne '/supabase_db_k-youtube|true') { throw 'Expected local DB unavailable' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sql = "BEGIN; SET LOCAL ROLE postgres;" + [Environment]::NewLine
foreach ($version in 36..54) {
  $pattern = '{0:D4}_*.sql' -f $version
  $path = Get-ChildItem (Join-Path $root 'supabase/migrations') -Filter $pattern
  if (@($path).Count -ne 1) { throw "Expected exactly one migration: $pattern" }
  if ($version -eq 54) {
    $sql += "CREATE TEMP TABLE plans_before_features AS SELECT * FROM public.membership_plans; CREATE TEMP TABLE members_before_features AS SELECT * FROM public.member_entitlements;" + [Environment]::NewLine
  }
  $sql += (Get-Content -LiteralPath $path.FullName -Raw -Encoding UTF8) + [Environment]::NewLine
}
$sql += @'
DO $$ BEGIN
 IF EXISTS((TABLE public.membership_plans EXCEPT TABLE plans_before_features) UNION ALL
           (TABLE plans_before_features EXCEPT TABLE public.membership_plans))
 OR EXISTS((TABLE public.member_entitlements EXCEPT TABLE members_before_features) UNION ALL
           (TABLE members_before_features EXCEPT TABLE public.member_entitlements))
 THEN RAISE EXCEPTION 'EXISTING_SUBSCRIPTIONS_CHANGED'; END IF;
END;$$;
'@ + [Environment]::NewLine
foreach ($contract in @('membership_features_contract.sql','security_rollout_contract.sql','shopping_assistant_contract.sql','shopping_store_directory_contract.sql','supplier_request_contract.sql')) {
  # Each standalone contract starts as a local fixture administrator, then sets
  # its own authenticated claims before exercising public endpoints and RLS.
  $sql += 'RESET ROLE; SELECT set_config(''request.jwt.claims'',''{"role":"service_role"}'',true); SELECT set_config(''request.jwt.claim.sub'','''',true);' + [Environment]::NewLine
  $sql += (Get-Content (Join-Path $PSScriptRoot $contract) -Raw -Encoding UTF8) + [Environment]::NewLine
}
$sql += 'ROLLBACK;'
$sql | & docker exec -i $db psql -X -q -v ON_ERROR_STOP=1 -U supabase_admin -d postgres
if ($LASTEXITCODE -ne 0) { throw 'Membership features contract failed; transaction rolls back' }
