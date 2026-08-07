[CmdletBinding()]
param([switch]$Run, [switch]$AuthPreflight, [switch]$HttpPreflight)

$ErrorActionPreference = 'Stop'

function Fail([string]$Name) { if(-not $script:OriginalFailureStage){ $script:OriginalFailureStage=$script:CurrentStage }; throw "EDGE_CONTRACT_FAIL:$Name" }
function Write-SafeStatus([string]$Message) { Microsoft.PowerShell.Utility\Write-Host $Message }
function Assert-Status([string]$Name, [int]$Actual, [int]$Expected) {
  if ($Actual -ne $Expected) { Fail "$Name status=$Actual" }
  Write-SafeStatus "PASS $Name status=$Actual"
}
function Assert-True([string]$Name, [bool]$Condition) {
  if (-not $Condition) { Fail $Name }
  Write-SafeStatus "PASS $Name status=200"
}
function Assert-ErrorCode([string]$Name, $Response, [string]$Expected) {
  Write-ErrorBodyDiagnostics $Response
  if($Response.BodyText -isnot [string] -or [string]::IsNullOrWhiteSpace($Response.BodyText)){ Fail 'error_response_body_missing' }
  $payload=Convert-Body $Response
  if($null -eq $payload){ Fail 'error_response_parse_invalid' }
  if($null -eq $payload.details -or $null -eq $payload.details.code){ Fail 'error_response_code_missing' }
  if([string]$payload.details.code -cne $Expected){ Fail $Name }
  Write-SafeStatus "PASS $Name status=$($Response.Status)"
}
function Get-StructuredCreateData([string]$Name, $Response, [bool]$ExpectedCreated, [bool]$ExpectedReplayed, [string]$ExpectedIdempotencyKey) {
  $payload=Convert-Body $Response
  if($null -eq $payload){ Fail "${Name}_response_parse" }
  $dataProperty=$payload.PSObject.Properties['data']
  if($null -eq $dataProperty){ Fail "${Name}_data_missing" }
  $data=$dataProperty.Value
  if($data -isnot [System.Management.Automation.PSCustomObject]){ Fail "${Name}_data_not_object" }
  if($data.list_id -isnot [string] -or [string]::IsNullOrWhiteSpace($data.list_id)){ Fail "${Name}_list_id_invalid" }
  if($data.status -isnot [string] -or $data.status -cne 'active'){ Fail "${Name}_status_invalid" }
  if($data.created -isnot [bool] -or $data.created -ne $ExpectedCreated){ Fail "${Name}_created_invalid" }
  if($data.replayed -isnot [bool] -or $data.replayed -ne $ExpectedReplayed){ Fail "${Name}_replayed_invalid" }
  if($data.idempotency_key -isnot [string] -or $data.idempotency_key -cne $ExpectedIdempotencyKey){ Fail "${Name}_idempotency_invalid" }
  return $data
}
function Get-ShoppingItemData([string]$Name, $Response, [string]$ExpectedId, [string]$ExpectedListId, [string]$ExpectedStatus, [int]$ExpectedRevision) {
  $payload=Convert-Body $Response
  if($null -eq $payload){ Fail "${Name}_response_parse" }
  $dataProperty=$payload.PSObject.Properties['data']
  if($null -eq $dataProperty -or $dataProperty.Value -isnot [System.Management.Automation.PSCustomObject]){ Fail "${Name}_data_invalid" }
  $data=$dataProperty.Value
  foreach($field in @('id','list_id','name','ingredient_text','quantity','unit','status','review_status','needs_review','is_checked','revision','updated_at')) {
    if($null -eq $data.PSObject.Properties[$field]){ Fail "${Name}_field_missing_$field" }
  }
  if($data.id -cne $ExpectedId -or $data.list_id -cne $ExpectedListId){ Fail "${Name}_identity_invalid" }
  if($data.status -cne $ExpectedStatus -or [int]$data.revision -ne $ExpectedRevision){ Fail "${Name}_state_invalid" }
  if($data.needs_review -isnot [bool] -or $data.needs_review -ne ([string]$data.review_status -ceq 'required')){ Fail "${Name}_needs_review_invalid" }
  if($null -ne $data.PSObject.Properties['owner_id'] -or $null -ne $data.PSObject.Properties['normalized_name']){ Fail "${Name}_managed_field_exposed" }
  return $data
}
function ConvertTo-SafeBodyText($Value) {
  if($null -eq $Value){ return $null }
  if($Value -is [System.Array]){
    $text=[string]::Join([Environment]::NewLine, [string[]]@($Value | ForEach-Object { if($null -eq $_){ '' }else{ [string]$_ } }))
  } else {
    $text=[string]$Value
  }
  $text=$text.Trim().TrimStart([char]0xFEFF).Trim()
  if([string]::IsNullOrWhiteSpace($text)){ return $null }
  return [string]$text
}
function Write-ErrorBodyDiagnostics($Response) {
  if($Response.Status -notin @(401,422)){ return }
  $bodyPresent=($Response.BodyText -is [string]) -and -not [string]::IsNullOrWhiteSpace($Response.BodyText)
  $bodyType=if($null -eq $Response.BodyText){ 'null' }else{ $Response.BodyText.GetType().Name }
  $contentTypeJson=([string]$Response.ContentType -match '(?i)^\s*application/(?:[a-z0-9!#$&^_.+-]+\+)?json(?:\s*;|$)')
  Write-SafeStatus "ERROR_BODY_SOURCE=$($Response.BodySource)"
  Write-SafeStatus "ERROR_BODY_PRESENT=$bodyPresent"
  Write-SafeStatus "ERROR_BODY_TYPE=$bodyType"
  Write-SafeStatus "ERROR_CONTENT_TYPE_JSON=$contentTypeJson"
}
function Invoke-SafeHttp([string]$Method, [string]$Uri, [hashtable]$Headers, $Body) {
  $response=$null; $bodyText=$null; $contentType=$null; $bodySource='none'
  try {
    $params = @{ Method=$Method; Uri=$Uri; Headers=$Headers; ErrorAction='Stop'; UseBasicParsing=$true }
    if ($null -ne $Body) { $params.ContentType='application/json'; $params.Body=($Body | ConvertTo-Json -Depth 8 -Compress) }
    $response=Invoke-WebRequest @params
    $bodyText=ConvertTo-SafeBodyText $response.Content
    $contentType=[string]$response.Headers['Content-Type']
    return [pscustomobject]@{ Status=[int]$response.StatusCode; BodyText=$bodyText; ContentType=$contentType; BodySource=$bodySource }
  } catch {
    $status=0
    $errorResponse=$null
    try { $errorResponse=$_.Exception.Response } catch {}
    if($null -ne $errorResponse){
      try { $status=[int]$errorResponse.StatusCode } catch {}
      try { $contentType=[string]$errorResponse.ContentType } catch {}
    }
    $errorDetailsMessage=$null
    try { $errorDetailsMessage=$_.ErrorDetails.Message } catch {}
    $bodyText=ConvertTo-SafeBodyText $errorDetailsMessage
    if($null -ne $bodyText){
      $bodySource='errordetails'
    } elseif($null -ne $errorResponse){
      try {
        $stream=$errorResponse.GetResponseStream()
        if($null -ne $stream){
          $reader=[IO.StreamReader]::new($stream)
          try { $bodyText=ConvertTo-SafeBodyText $reader.ReadToEnd() } finally { $reader.Dispose() }
          if($null -ne $bodyText){ $bodySource='response_stream' }
        }
      } catch {}
    }
    return [pscustomobject]@{ Status=[int]$status; BodyText=$bodyText; ContentType=$contentType; BodySource=$bodySource }
  } finally {
    $response=$null; $bodyText=$null; $contentType=$null; $bodySource=$null
  }
}
function Convert-Body($Response) {
  if ([string]::IsNullOrWhiteSpace([string]$Response.BodyText)) { return $null }
  try { return $Response.BodyText | ConvertFrom-Json } catch { return $null }
}
function Invoke-CapturedProcess([string]$FileName, [string]$Arguments, [int]$TimeoutMilliseconds) {
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=$FileName; $info.Arguments=$Arguments; $info.UseShellExecute=$false
  $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true; $info.CreateNoWindow=$true
  try { $process=[Diagnostics.Process]::new(); $process.StartInfo=$info; [void]$process.Start() } catch { return @{ State='start_failed'; StdOut=''; StdErr='' } }
  $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit($TimeoutMilliseconds)) {
    try { $process.Kill() } catch {}
    $process.WaitForExit()
    $outTask.Wait(); $errTask.Wait()
    return @{ State='timed_out'; StdOut=$outTask.Result; StdErr=$errTask.Result }
  }
  $outTask.Wait(); $errTask.Wait()
  return @{ State=$(if($process.ExitCode -eq 0){'ok'}else{'failed'}); StdOut=$outTask.Result; StdErr=$errTask.Result }
}
function Convert-EnvLines([string]$Raw) {
  $map=@{}
  foreach($line in ($Raw -split "`r?`n")) { if($line -match '^([^=]+)=(.*)$') { $map[$matches[1]]=$matches[2] } }
  return $map
}
function Assert-LocalApiUrl([string]$Url) {
  try { $uri=[Uri]$Url } catch { Fail 'local_url_validation_failed' }
  if($uri.Scheme -ne 'http' -or $uri.Host -notin @('localhost','127.0.0.1') -or $uri.Port -ne 54321) { Fail 'local_url_validation_failed' }
  return $uri.GetLeftPart([UriPartial]::Authority)
}
function Get-DockerPath {
  try { $dockerCommand=Get-Command docker.exe -ErrorAction Stop } catch { Fail 'docker_executable_missing' }
  if(-not $dockerCommand.Source) { Fail 'docker_executable_missing' }
  return $dockerCommand.Source
}
function Get-ContainerInspect([string]$ContainerName) {
  $script:inspectRaw=@(& $script:dockerPath inspect --type container $ContainerName 2>$null)
  if($LASTEXITCODE -ne 0 -or $script:inspectRaw.Count -eq 0) { Fail 'docker_inspect_failed' }
  try { $script:inspectJson=(($script:inspectRaw -join "`n") | ConvertFrom-Json) } catch { Fail 'docker_inspect_parse_failed' }
  if($script:inspectJson.Count -ne 1 -or $script:inspectJson[0].Name.TrimStart('/') -ne $ContainerName) { Fail 'docker_inspect_failed' }
  return $script:inspectJson[0]
}
function Get-LocalStackState {
  $script:dockerPath=Get-DockerPath
  $names=@('supabase_db_k-youtube','supabase_kong_k-youtube','supabase_auth_k-youtube','supabase_edge_runtime_k-youtube')
  foreach($name in $names) {
    $container=Get-ContainerInspect $name
    if(-not $container.State.Running) { Fail 'stack_container_missing' }
    if($container.State.Health -and $container.State.Health.Status -ne 'healthy') { Fail 'stack_container_missing' }
    if($name -eq 'supabase_edge_runtime_k-youtube') { $script:edgeInspect=$container }
  }
  if($script:edgeInspect.Config.Labels.'com.supabase.cli.project' -ne 'k-youtube') { Fail 'edge_label_mismatch' }
  $denoVersion=Invoke-CapturedProcess $script:dockerPath 'exec supabase_edge_runtime_k-youtube edge-runtime --version' 10000
  if($denoVersion.State -ne 'ok' -or $denoVersion.StdOut -notmatch '(?m)^deno 2\.1\.4(?:\s|\()') { Fail 'deno_version_mismatch' }
  $script:edgeRuntimeUp=$true
}
function Get-LocalConfig {
  Get-LocalStackState
  $cli=Invoke-CapturedProcess 'npx.cmd' '--yes --offline supabase@latest status -o env' 18000
  if($cli.State -eq 'ok') {
    $map=Convert-EnvLines $cli.StdOut
    $url=$map['API_URL']; if(-not $url){ $url=$map['SUPABASE_URL'] }
    $base=Assert-LocalApiUrl $url
    if(-not $map['ANON_KEY'] -or -not $map['SERVICE_ROLE_KEY']) { Fail 'required_local_env_missing' }
    $script:statusSource='supabase-cli'
    $script:configStage='config_acquire_success'
    return [pscustomobject]@{ Url=$base; Anon=$map['ANON_KEY']; Service=$map['SERVICE_ROLE_KEY'] }
  }
  if($cli.State -eq 'timed_out') { $script:configStage='config_acquire_cli_failed' } else { $script:configStage='config_acquire_cli_failed' }
  $script:configFallback=$true
  if(-not $script:edgeInspect) { Fail 'docker_fallback_unavailable' }
  $script:environmentMap=@{}
  foreach($entry in @($script:edgeInspect.Config.Env)) {
    $parts=$entry -split '=',2
    if($parts.Count -eq 2) { $script:environmentMap[$parts[0]]=$parts[1] }
  }
  $containerUrl=[string]$script:environmentMap['SUPABASE_URL']
  try { $containerUri=[Uri]$containerUrl } catch { Fail 'local_url_validation_failed' }
  if($containerUri.Scheme -eq 'http' -and $containerUri.Host -eq 'kong' -and $containerUri.Port -eq 8000) {
    $base=Assert-LocalApiUrl 'http://127.0.0.1:54321'
  } else {
    $base=Assert-LocalApiUrl $containerUrl
  }
  if(-not $script:environmentMap['SUPABASE_ANON_KEY'] -or -not $script:environmentMap['SUPABASE_SERVICE_ROLE_KEY']) { Fail 'required_local_env_missing' }
  $script:statusSource='edge-container'
  $script:configStage='config_acquire_success'
  return [pscustomobject]@{ Url=$base; Anon=$script:environmentMap['SUPABASE_ANON_KEY']; Service=$script:environmentMap['SUPABASE_SERVICE_ROLE_KEY'] }
}
function New-Password { -join ((48..57)+(65..90)+(97..122)|Get-Random -Count 40|ForEach-Object{[char]$_}) }
function New-Key { [guid]::NewGuid().ToString() }
function Get-LocalAuthUserCount {
  $users=@(Get-LocalAuthUsers)
  if($users.Count -lt 0) { Fail 'auth_baseline_count_invalid' }
  return [int]$users.Count
}
function Get-LocalAuthUsers {
  $headers=Get-ServiceHeaders; $response=$null; $payload=$null
  try {
    $response=Invoke-WebRequest -Method Get -Uri "$($config.Url)/auth/v1/admin/users?page=1&per_page=100" -Headers $headers -UseBasicParsing -ErrorAction Stop
  } catch {
    $status=if($_.Exception.Response){ [int]$_.Exception.Response.StatusCode }else{ 0 }
    if($status -eq 0){ Fail 'auth_admin_list_transport_failed' }
    Fail "auth_admin_list_http_$status"
  }
  try {
    if([int]$response.StatusCode -ne 200){ Fail "auth_admin_list_http_$([int]$response.StatusCode)" }
    if([string]$response.Headers['Content-Type'] -notmatch '(?i)application/json'){ Fail 'auth_admin_list_not_json' }
    $payload=$response.Content | ConvertFrom-Json -ErrorAction Stop
    if($null -eq $payload){ Fail 'auth_admin_list_response_invalid' }
    if($payload -is [System.Array] -or $null -eq $payload.users){ Fail 'auth_admin_list_users_missing' }
    if($payload.users -isnot [System.Array]){ Fail 'auth_admin_list_response_invalid' }
    return @($payload.users)
  } catch {
    if($_.Exception.Message -match '^EDGE_CONTRACT_FAIL:'){ throw }
    Fail 'auth_admin_list_response_invalid'
  } finally {
    $headers=$null; $response=$null; $payload=$null
  }
}
function Get-ServiceHeaders { @{ apikey=$config.Service; Authorization="Bearer $($config.Service)"; Accept='application/json' } }
function Get-UserHeaders([string]$Token, [string]$Key=$config.Anon) { @{ apikey=$Key; Authorization="Bearer $Token" } }
function Invoke-ServiceRest([string]$Method, [string]$Path, $Body=$null) { Invoke-SafeHttp $Method "$($config.Url)/rest/v1/$Path" (Get-ServiceHeaders) $Body }
function Get-Count([string]$Path) {
  $response=Invoke-ServiceRest 'GET' $Path $null
  $null=Assert-Status 'fixture_query' $response.Status 200
  $rows=Convert-Body $response
  return [int]@($rows).Count
}
function Get-Rows([string]$Path) {
  $response=Invoke-ServiceRest 'GET' $Path $null
  $null=Assert-Status 'fixture_query' $response.Status 200
  $body=Convert-Body $response
  if($null -eq $body){ return @() }
  if($body -isnot [System.Array]){ Fail 'fixture_rows_parse_invalid' }
  return @($body)
}
function New-LocalUser([string]$Label) {
  $password=New-Password
  $email="$marker-$Label@local.test"
  $fixture=[pscustomobject]@{ Email=$email; Id=$null }
  $script:fixtureUsers+=,$fixture
  $created=Invoke-SafeHttp 'POST' "$($config.Url)/auth/v1/admin/users" (Get-ServiceHeaders) @{ email=$email; password=$password; email_confirm=$true }
  if($created.Status -notin @(200,201)) { Fail "fixture_user_$Label status=$($created.Status)" }
  Write-SafeStatus "PASS fixture_user_$Label status=$($created.Status)"
  $user=Convert-Body $created
  if($null -eq $user -or -not $user.id){ Fail 'fixture_user_response_invalid' }
  $fixture.Id=[string]$user.id
  $profile=Invoke-ServiceRest 'POST' 'profiles' @{ id=[string]$user.id }
  $null=Assert-Status "fixture_profile_$Label" $profile.Status 201
  $token=Invoke-SafeHttp 'POST' "$($config.Url)/auth/v1/token?grant_type=password" @{ apikey=$config.Anon } @{ email=$email; password=$password }
  $null=Assert-Status "password_grant_$Label" $token.Status 200
  $session=Convert-Body $token
  if(-not $session.access_token){ Fail "password_grant_$Label" }
  $userObject=[pscustomobject]@{ Id=[string]$user.id; Token=[string]$session.access_token }
  if(-not $userObject.Id -or -not $userObject.Token) { Fail "fixture_user_$Label" }
  return ,$userObject
}
function Remove-Fixtures {
  foreach($user in @($script:fixtureUsers)) {
    $targetId=[string]$user.Id
    if(-not $targetId) {
      $matches=@(Get-LocalAuthUsers | Where-Object { $_.email -eq $user.Email })
      if($matches.Count -gt 1) { Fail 'auth_fixture_cleanup_ambiguous' }
      if($matches.Count -eq 1) { $targetId=[string]$matches[0].id }
    }
    if(-not $targetId){ continue }
    $ownerFilter=[uri]::EscapeDataString("eq.$targetId")
    $listRows=Get-Rows "kitchen_shopping_lists?select=id&owner_id=$ownerFilter&source_recipe_id=$([uri]::EscapeDataString("eq.user:$marker"))"
    $listIds=@($listRows | ForEach-Object { [string]$_.id } | Where-Object { $_ })
    if($listIds.Count -gt 0) {
      $inFilter=[uri]::EscapeDataString("in.($($listIds -join ','))")
      $null=Invoke-ServiceRest 'DELETE' "kitchen_shopping_idempotency?list_id=$inFilter" $null
      $null=Invoke-ServiceRest 'DELETE' "kitchen_shopping_items?list_id=$inFilter" $null
      $null=Invoke-ServiceRest 'DELETE' "kitchen_shopping_lists?id=$inFilter" $null
    }
    $null=Invoke-ServiceRest 'DELETE' "kitchen_ingredients?owner_id=$ownerFilter" $null
    $null=Invoke-ServiceRest 'DELETE' "profiles?id=$ownerFilter" $null
    $deleted=Invoke-SafeHttp 'DELETE' "$($config.Url)/auth/v1/admin/users/$targetId" (Get-ServiceHeaders) $null
    if($deleted.Status -notin @(200,204)) { Fail "auth_fixture_delete status=$($deleted.Status)" }
  }
}

$config=$null; $script:dockerPath=$null; $script:inspectRaw=$null; $script:inspectJson=$null; $script:edgeInspect=$null; $script:environmentMap=$null; $script:edgeRuntimeUp=$false; $script:statusSource=$null; $script:configStage='config_acquire_start'; $script:configFallback=$false; $script:CurrentStage='main_config_before'; $script:OriginalFailureStage=$null; $script:CleanupStage=$null
try {
  if((@($Run,$AuthPreflight,$HttpPreflight | Where-Object { $_ }).Count) -gt 1) { Fail 'preflight_mode_conflict' }
  $root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  if((Split-Path $root -Leaf) -ne 'K-youtube'){ Fail 'project_root' }
  Write-SafeStatus 'main_config_before'; $config=Get-LocalConfig; $script:CurrentStage='main_config_after'; Write-SafeStatus 'main_config_after'
  if($config -isnot [System.Management.Automation.PSCustomObject] -or -not $config.Url -or -not $config.Anon -or -not $config.Service) { Fail 'config_object_invalid' }
  $script:CurrentStage='preflight_before'; Write-SafeStatus 'preflight_before'
  if($script:edgeRuntimeUp) { Write-SafeStatus 'EDGE_RUNTIME=UP' }
  Write-SafeStatus "STATUS_SOURCE=$($script:statusSource)"
  if($script:configFallback) { Write-SafeStatus 'config_acquire_docker_fallback' }
  Write-SafeStatus 'config_acquire_success'; Write-SafeStatus 'LOCAL_PREFLIGHT=PASS'; $script:CurrentStage='preflight_after'; Write-SafeStatus 'preflight_after'
  if($HttpPreflight){
    $authProbe=Invoke-SafeHttp 'GET' "$($config.Url)/auth/v1/admin/users?page=1&per_page=100" (Get-ServiceHeaders) $null
    if($authProbe.Status -ne 200){ Fail "http_preflight_auth_$($authProbe.Status)" }
    $edgeProbe=Invoke-SafeHttp 'GET' "$($config.Url)/functions/v1/recipe_api?type=kitchen" @{ apikey=$config.Anon } $null
    if($edgeProbe.Status -ne 401){ Fail "http_preflight_edge_$($edgeProbe.Status)" }
    Write-ErrorBodyDiagnostics $edgeProbe
    $edgeProbeParseable=$false
    if($edgeProbe.BodyText -is [string] -and -not [string]::IsNullOrWhiteSpace($edgeProbe.BodyText)){
      try { $null=$edgeProbe.BodyText | ConvertFrom-Json; $edgeProbeParseable=$true } catch {}
    }
    Write-SafeStatus "HTTP_ERROR_BODY_JSON_PARSEABLE=$edgeProbeParseable"
    Write-SafeStatus 'HTTP_SUCCESS_STATUS=200'; Write-SafeStatus 'HTTP_ERROR_STATUS=401'; Write-SafeStatus 'HTTP_PREFLIGHT=PASS'
  } elseif($AuthPreflight){
    $authPreflightUsers=@(Get-LocalAuthUsers)
    Write-SafeStatus 'AUTH_PREFLIGHT=PASS'
    Write-SafeStatus "AUTH_USER_COUNT=$($authPreflightUsers.Count)"
  } elseif(-not $Run){
    Write-SafeStatus 'NOT_RUN'
  } else {
    $script:CurrentStage='fixture_setup_before'; Write-SafeStatus 'fixture_setup_before'; $marker='edge-contract-'+[guid]::NewGuid().ToString('N')
    $users=@(); $script:fixtureUsers=@(); $baselineAuthCount=Get-LocalAuthUserCount
    try {
  $script:CurrentStage='jwt_issue_before'; Write-SafeStatus 'jwt_issue_before'; $userA=New-LocalUser 'a'; $users+=@($userA); $script:CurrentStage='jwt_issue_after'; Write-SafeStatus 'jwt_issue_after'; $script:CurrentStage='fixture_setup_after'; Write-SafeStatus 'fixture_setup_after'
  $userB=New-LocalUser 'b'; $users+=@($userB)
  $script:CurrentStage='edge_assertions_before'; Write-SafeStatus 'edge_assertions_before'; $edgeUrl="$($config.Url)/functions/v1/recipe_api?type=kitchen"
  $createUrl="$edgeUrl&action=create-shopping-from-recipe"

  Assert-Status 'jwt_missing' (Invoke-SafeHttp 'POST' $createUrl @{ apikey=$config.Anon } @{}).Status 401
  Assert-Status 'jwt_invalid' (Invoke-SafeHttp 'POST' $createUrl (Get-UserHeaders 'invalid') @{}).Status 401
  Assert-Status 'idempotency_missing' (Invoke-SafeHttp 'POST' $createUrl (Get-UserHeaders $userA.Token) @{ source_recipe_id="user:$marker"; items=@() }).Status 400
  Assert-Status 'idempotency_invalid' (Invoke-SafeHttp 'POST' $createUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userA.Token)"; 'Idempotency-Key'='invalid' }) @{ source_recipe_id="user:$marker"; items=@() }).Status 400

  $beforeLegacy=Get-Count "kitchen_shopping_lists?select=id&owner_id=$([uri]::EscapeDataString("eq.$($userA.Id)"))&source_recipe_id=$([uri]::EscapeDataString("eq.user:$marker"))"
  $legacy=Invoke-SafeHttp 'POST' $createUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userA.Token)"; 'Idempotency-Key'=(New-Key) }) @{ source_recipe_id="user:$marker"; ingredients=@('legacy') }
  Assert-Status 'legacy_ingredient_review_required' $legacy.Status 422
  Assert-ErrorCode 'legacy_ingredient_review_code' $legacy 'ingredient_review_required'
  Assert-True 'legacy_no_database_change' ((Get-Count "kitchen_shopping_lists?select=id&owner_id=$([uri]::EscapeDataString("eq.$($userA.Id)"))&source_recipe_id=$([uri]::EscapeDataString("eq.user:$marker"))") -eq $beforeLegacy)

  $items=@(@{ name='contract potato'; ingredient_text='contract potato 2kg'; quantity=2; unit='kg' })
  $createKey=New-Key
  $created=Invoke-SafeHttp 'POST' $createUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userA.Token)"; 'Idempotency-Key'=$createKey }) @{ source_recipe_id="user:$marker"; items=$items }
  Assert-Status 'structured_create' $created.Status 201
  $createdData=Get-StructuredCreateData 'structured_create' $created $true $false $createKey
  $listId=[string]$createdData.list_id
  $createdListCount=Get-Count "kitchen_shopping_lists?select=id&owner_id=$([uri]::EscapeDataString("eq.$($userA.Id)"))&source_recipe_id=$([uri]::EscapeDataString("eq.user:$marker"))"
  $createdItemCount=Get-Count "kitchen_shopping_items?select=id&owner_id=$([uri]::EscapeDataString("eq.$($userA.Id)"))&list_id=$([uri]::EscapeDataString("eq.$listId"))"
  $replay=Invoke-SafeHttp 'POST' $createUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userA.Token)"; 'Idempotency-Key'=$createKey }) @{ source_recipe_id="user:$marker"; items=$items }
  Assert-Status 'structured_create_replay' $replay.Status 200
  $replayData=Get-StructuredCreateData 'structured_create_replay' $replay $false $true $createKey
  if([string]$replayData.list_id -cne $listId){ Fail 'structured_create_replay_list_id_mismatch' }
  Assert-True 'structured_create_replay_list_count_unchanged' ((Get-Count "kitchen_shopping_lists?select=id&owner_id=$([uri]::EscapeDataString("eq.$($userA.Id)"))&source_recipe_id=$([uri]::EscapeDataString("eq.user:$marker"))") -eq $createdListCount)
  Assert-True 'structured_create_replay_item_count_unchanged' ((Get-Count "kitchen_shopping_items?select=id&owner_id=$([uri]::EscapeDataString("eq.$($userA.Id)"))&list_id=$([uri]::EscapeDataString("eq.$listId"))") -eq $createdItemCount)

  foreach($invalid in @(
    @{ name='managed_field_rejected'; item=@{ name='managed'; ingredient_text='managed'; owner_id=$userA.Id } },
    @{ name='name_validation'; item=@{ name=''; ingredient_text='valid text' } },
    @{ name='ingredient_text_validation'; item=@{ name='valid name'; ingredient_text='' } },
    @{ name='quantity_validation'; item=@{ name='valid quantity'; ingredient_text='valid quantity'; quantity=0 } }
  )) {
    $response=Invoke-SafeHttp 'POST' $createUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userA.Token)"; 'Idempotency-Key'=(New-Key) }) @{ source_recipe_id="user:$marker"; items=@($invalid.item) }
    Assert-Status $invalid.name $response.Status $(if($invalid.name -eq 'managed_field_rejected'){400}else{422})
  }

  $completeUrl="$edgeUrl&action=complete-shopping-list&id=$listId"
  Assert-Status 'pending_completion_rejected' (Invoke-SafeHttp 'POST' $completeUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userA.Token)"; 'Idempotency-Key'=(New-Key) }) @{}).Status 422
  Assert-Status 'other_user_completion_rejected' (Invoke-SafeHttp 'POST' $completeUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userB.Token)"; 'Idempotency-Key'=(New-Key) }) @{}).Status 404

  $script:CurrentStage='fixture_item_lookup'
  $listResponse=Invoke-SafeHttp 'GET' "$edgeUrl&view=shopping-lists&status=all" (Get-UserHeaders $userA.Token) $null
  Assert-Status 'fixture_list_lookup' $listResponse.Status 200
  $script:CurrentStage='fixture_item_parse'
  $listPayload=Convert-Body $listResponse
  if($null -eq $listPayload){ Fail 'fixture_item_rows_parse_invalid' }
  $dataProperty=$listPayload.PSObject.Properties['data']
  if($null -eq $dataProperty -or $dataProperty.Value -isnot [System.Array]){ Fail 'fixture_item_rows_parse_invalid' }
  $rows=@($dataProperty.Value | Where-Object {
    if($_ -isnot [System.Management.Automation.PSCustomObject]){ return $false }
    $rowIdProperty=$_.PSObject.Properties['id']
    return $null -ne $rowIdProperty -and $rowIdProperty.Value -is [string] -and $rowIdProperty.Value -ceq $listId
  })
  $script:CurrentStage='fixture_item_validate'
  if($rows.Count -eq 0){ Fail 'fixture_item_missing' }
  if($rows.Count -ne 1){ Fail 'fixture_item_count_invalid' }
  $fixtureList=$rows[0]
  $itemsProperty=$fixtureList.PSObject.Properties['items']
  if($null -eq $itemsProperty -or $itemsProperty.Value -isnot [System.Array]){ Fail 'fixture_item_rows_parse_invalid' }
  $itemRows=@($itemsProperty.Value)
  if($itemRows.Count -eq 0){ Fail 'fixture_item_missing' }
  if($itemRows.Count -ne 1){ Fail 'fixture_item_count_invalid' }
  $fixtureItem=$itemRows[0]
  if($fixtureItem -isnot [System.Management.Automation.PSCustomObject]){ Fail 'fixture_item_id_missing' }
  $itemIdProperty=$fixtureItem.PSObject.Properties['id']
  if($null -eq $itemIdProperty -or $null -eq $itemIdProperty.Value -or [string]::IsNullOrWhiteSpace([string]$itemIdProperty.Value)){ Fail 'fixture_item_id_missing' }
  if($itemIdProperty.Value -isnot [string]){ Fail 'fixture_item_id_invalid' }
  $itemId=[string]$itemIdProperty.Value
  $itemGuid=[guid]::Empty
  if(-not [guid]::TryParse($itemId, [ref]$itemGuid)){ Fail 'fixture_item_id_invalid' }
  $itemListIdProperty=$fixtureItem.PSObject.Properties['list_id']
  if($null -eq $itemListIdProperty -or $itemListIdProperty.Value -isnot [string] -or $itemListIdProperty.Value -cne $listId){ Fail 'fixture_item_list_mismatch' }
  foreach($field in @('id','list_id','name','ingredient_text','quantity','unit','status','review_status','needs_review','is_checked','revision','updated_at')) {
    if($null -eq $fixtureItem.PSObject.Properties[$field]){ Fail "fixture_item_field_missing_$field" }
  }
  if($fixtureItem.needs_review -isnot [bool] -or $fixtureItem.needs_review -ne ([string]$fixtureItem.review_status -ceq 'required')){ Fail 'fixture_item_needs_review_invalid' }
  if($null -ne $fixtureItem.PSObject.Properties['owner_id'] -or $null -ne $fixtureItem.PSObject.Properties['normalized_name']){ Fail 'fixture_item_managed_field_exposed' }
  Write-SafeStatus 'PASS shopping_item_response_fields status=200'

  $itemIdQuery=[uri]::EscapeDataString($itemId)
  $reviewUrl="$edgeUrl&action=review-shopping-item&id=$itemIdQuery"
  $statusUrl="$edgeUrl&action=set-shopping-item-status&id=$itemIdQuery"
  Assert-Status 'review_missing_expected_revision' (Invoke-SafeHttp 'POST' $reviewUrl (Get-UserHeaders $userA.Token) @{ name='Reviewed'; quantity=3; unit='kg' }).Status 422
  Assert-Status 'review_managed_field_rejected' (Invoke-SafeHttp 'POST' $reviewUrl (Get-UserHeaders $userA.Token) @{ name='Reviewed'; ingredient_text='forbidden'; expected_revision=0 }).Status 400
  Assert-Status 'review_quantity_unit_pair_rejected' (Invoke-SafeHttp 'POST' $reviewUrl (Get-UserHeaders $userA.Token) @{ name='Reviewed'; quantity=3; expected_revision=0 }).Status 422
  $reviewResponse=Invoke-SafeHttp 'POST' $reviewUrl (Get-UserHeaders $userA.Token) @{ name='Contract Potato Reviewed'; quantity=3; unit='kg'; expected_revision=0 }
  Assert-Status 'review_shopping_item_rpc' $reviewResponse.Status 200
  $reviewedItem=Get-ShoppingItemData 'review_shopping_item_rpc' $reviewResponse $itemId $listId 'pending' 1
  if($reviewedItem.ingredient_text -cne 'contract potato 2kg'){ Fail 'review_ingredient_text_changed' }

  $staleStatus=Invoke-SafeHttp 'POST' $statusUrl (Get-UserHeaders $userA.Token) @{ status='skipped'; expected_revision=0 }
  Assert-Status 'status_stale_revision' $staleStatus.Status 409
  Assert-ErrorCode 'status_stale_revision_code' $staleStatus 'shopping_item_conflict'
  $otherUserStatus=Invoke-SafeHttp 'POST' $statusUrl (Get-UserHeaders $userB.Token) @{ status='purchased'; expected_revision=1 }
  Assert-Status 'status_other_user_rejected' $otherUserStatus.Status 404

  $statusResponse=Invoke-SafeHttp 'POST' $statusUrl (Get-UserHeaders $userA.Token) @{ status='purchased'; expected_revision=1 }
  Assert-Status 'status_shopping_item_rpc' $statusResponse.Status 200
  $purchasedItem=Get-ShoppingItemData 'status_shopping_item_rpc' $statusResponse $itemId $listId 'purchased' 2
  if($purchasedItem.is_checked -isnot [bool] -or -not $purchasedItem.is_checked){ Fail 'status_is_checked_sync_invalid' }

  $legacyResponse=Invoke-SafeHttp 'PATCH' "$edgeUrl&view=shopping-item&id=$itemIdQuery" (Get-UserHeaders $userA.Token) @{ is_checked=$false; expected_revision=2 }
  Assert-Status 'legacy_is_checked_rpc_mapping' $legacyResponse.Status 200
  $legacyItem=Get-ShoppingItemData 'legacy_is_checked_rpc_mapping' $legacyResponse $itemId $listId 'pending' 3
  if($legacyItem.is_checked -isnot [bool] -or $legacyItem.is_checked){ Fail 'legacy_is_checked_sync_invalid' }
  $statusResponse=Invoke-SafeHttp 'POST' $statusUrl (Get-UserHeaders $userA.Token) @{ status='purchased'; expected_revision=3 }
  Assert-Status 'status_after_legacy_mapping' $statusResponse.Status 200
  $purchasedItem=Get-ShoppingItemData 'status_after_legacy_mapping' $statusResponse $itemId $listId 'purchased' 4
  if(-not $purchasedItem.is_checked){ Fail 'status_after_legacy_sync_invalid' }

  $inventoryBefore=Get-Count "kitchen_ingredients?select=id&owner_id=$([uri]::EscapeDataString("eq.$($userA.Id)"))&normalized_name=eq.contract%20potato%20reviewed"
  $completeKey=New-Key
  $completed=Invoke-SafeHttp 'POST' $completeUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userA.Token)"; 'Idempotency-Key'=$completeKey }) @{}
  Assert-Status 'complete_success' $completed.Status 200
  $inventoryAfter=Get-Count "kitchen_ingredients?select=id&owner_id=$([uri]::EscapeDataString("eq.$($userA.Id)"))&normalized_name=eq.contract%20potato%20reviewed"
  Assert-True 'inventory_applied_once' ($inventoryAfter -eq ($inventoryBefore + 1))
  Assert-Status 'complete_same_key_replay' (Invoke-SafeHttp 'POST' $completeUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userA.Token)"; 'Idempotency-Key'=$completeKey }) @{}).Status 200
  Assert-Status 'complete_different_key_noop' (Invoke-SafeHttp 'POST' $completeUrl (@{ apikey=$config.Anon; Authorization="Bearer $($userA.Token)"; 'Idempotency-Key'=(New-Key) }) @{}).Status 200
  Assert-True 'inventory_replay_noop' ((Get-Count "kitchen_ingredients?select=id&owner_id=$([uri]::EscapeDataString("eq.$($userA.Id)"))&normalized_name=eq.contract%20potato%20reviewed") -eq $inventoryAfter)
  $inactiveStatus=Invoke-SafeHttp 'POST' $statusUrl (Get-UserHeaders $userA.Token) @{ status='pending'; expected_revision=4 }
  Assert-Status 'status_inactive_list_rejected' $inactiveStatus.Status 409
    } finally {
      $script:CleanupStage='cleanup_before'; Write-SafeStatus 'cleanup_before'
      Remove-Fixtures
      $finalAuthCount=Get-LocalAuthUserCount
      if($finalAuthCount -ne $baselineAuthCount) { Fail 'auth_fixture_count_mismatch' }
      Write-SafeStatus 'PASS auth_cleanup_restored status=200'
      $script:CleanupStage='cleanup_after'; Write-SafeStatus 'cleanup_after'; Write-SafeStatus 'PASS cleanup status=200'
    }
  }
} catch {
  Write-SafeStatus 'LOCAL_PREFLIGHT=FAIL'
  $safeMessage=$_.Exception.Message
  $safeCodes=@('docker_executable_missing','stack_container_missing','edge_label_mismatch','cli_status_timeout','cli_status_failed','docker_fallback_unavailable','docker_inspect_failed','docker_inspect_parse_failed','required_local_env_missing','local_url_validation_failed','config_object_invalid')
  if($safeMessage -notmatch '^EDGE_CONTRACT_FAIL:') { $safeMessage="EDGE_CONTRACT_FAIL:unexpected_$($script:CurrentStage)" }
  throw $safeMessage
} finally {
  foreach($configEntry in @($config)) {
    if($configEntry -is [Collections.IDictionary]) { $configEntry['Anon']=$null; $configEntry['Service']=$null; $configEntry['Url']=$null }
  }
  $config=$null
  $script:inspectRaw=$null; $script:inspectJson=$null; $script:edgeInspect=$null; $script:environmentMap=$null; $script:dockerPath=$null; $script:edgeRuntimeUp=$null; $script:statusSource=$null
  if($users) { foreach($user in $users) { $user.Token=$null; $user.Id=$null } }
}
