# GitHub Actions Secrets Template (Internal Track Release Guard)

Last update: 2026-07-24

This template is for `.github/workflows/internal-track-release-guard.yml`.

## Required repository secrets

1. `SUPABASE_URL_PRODUCTION`
- Example: `https://<your-project-ref>.supabase.co`
- Source: Supabase project settings (Project URL)

2. `SUPABASE_ANON_KEY_PRODUCTION`
- Example: `eyJ...`
- Source: Supabase project settings (anon/public API key)

3. `PUBLIC_RECIPE_SYNC_FUNCTION_URL`
- Example: `https://<your-project-ref>.supabase.co/functions/v1/public_recipe_sync`
- Source: Construct from project ref + function path

4. `PUBLIC_RECIPE_SYNC_WORKER_SECRET`
- Example: long random string (32+ chars)
- Source: Value used by `PUBLIC_RECIPE_SYNC_WORKER_SECRET` in your Supabase function environment

5. `ANDROID_KEY_PROPERTIES`
- Multi-line text secret. Use real values.
- Recommended content format:
storePassword=<REAL_STORE_PASSWORD>
keyPassword=<REAL_KEY_PASSWORD>
keyAlias=upload
storeFile=../upload-keystore.jks

6. `ANDROID_UPLOAD_KEYSTORE_BASE64`
- Base64-encoded bytes of your upload keystore (`.jks`)

7. `ANDROID_GOOGLE_SERVICES_JSON`
- Raw JSON content of `android/app/google-services.json`
- Store full file content as one secret value

## Windows PowerShell helper commands

1. Generate a strong worker secret
$bytes = New-Object byte[] 48
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$workerSecret = [Convert]::ToBase64String($bytes).TrimEnd('=')
$workerSecret

2. Encode upload keystore as base64
$keystorePath = "C:\path\to\upload-keystore.jks"
[Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath))

3. Read key.properties as one secret string
Get-Content -Path "android/key.properties" -Raw

4. Read google-services.json as one secret string
Get-Content -Path "android/app/google-services.json" -Raw

## Optional: GitHub CLI secret upload example

Set-Location "c:\Users\ADMIN\K-youtube"

$repo = "guige01-guinsa/kyoutube"

gh secret set SUPABASE_URL_PRODUCTION --repo $repo --body "https://<your-project-ref>.supabase.co"
gh secret set SUPABASE_ANON_KEY_PRODUCTION --repo $repo --body "<YOUR_PRODUCTION_ANON_KEY>"
gh secret set PUBLIC_RECIPE_SYNC_FUNCTION_URL --repo $repo --body "https://<your-project-ref>.supabase.co/functions/v1/public_recipe_sync"
gh secret set PUBLIC_RECIPE_SYNC_WORKER_SECRET --repo $repo --body "<PUBLIC_RECIPE_SYNC_WORKER_SECRET>"

$keyProps = Get-Content "android/key.properties" -Raw
gh secret set ANDROID_KEY_PROPERTIES --repo $repo --body "$keyProps"

$gsJson = Get-Content "android/app/google-services.json" -Raw
gh secret set ANDROID_GOOGLE_SERVICES_JSON --repo $repo --body "$gsJson"

$keystoreBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("android/upload-keystore.jks"))
gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64 --repo $repo --body "$keystoreBase64"

## Dispatch input recommendations

For `.github/workflows/internal-track-release-guard.yml` workflow_dispatch:
- `localVerification`: false
- `skipPublicRecipeSyncSmoke`: false
- `publicRecipeSyncSmokeSize`: 1

## Fast preflight checklist

1. `SUPABASE_URL_PRODUCTION` and `SUPABASE_ANON_KEY_PRODUCTION` are production values.
2. `PUBLIC_RECIPE_SYNC_WORKER_SECRET` matches Supabase runtime env.
3. `ANDROID_KEY_PROPERTIES` points to `storeFile=../upload-keystore.jks`.
4. `ANDROID_UPLOAD_KEYSTORE_BASE64` decodes to the same keystore used by Play upload key.
5. `ANDROID_GOOGLE_SERVICES_JSON` matches package id `com.kyoutube.app`.
