param(
    [Parameter(Mandatory = $false)]
    [string]$BaseUrl = "http://127.0.0.1:54321/functions/v1/recipe_api",

    [Parameter(Mandatory = $true)]
    [string]$AnonKey,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [string]$RecipeId = "smoke-recipe-1",

    [Parameter(Mandatory = $false)]
    [string]$RecipeTitle = "스모크 테스트 레시피"
)

$ErrorActionPreference = "Stop"

function New-Headers {
    return @{
        "apikey"        = $AnonKey
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
}

function Invoke-Kitchen {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST", "PATCH", "DELETE")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [object]$Body
    )

    $headers = New-Headers

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers
    }

    $jsonBody = $Body | ConvertTo-Json -Depth 10
    return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers -Body $jsonBody
}

function Assert-OkResponse {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Response,

        [Parameter(Mandatory = $true)]
        [string]$Step
    )

    if ($null -eq $Response -or $Response.status -ne "ok") {
        throw "[$Step] Kitchen API failed."
    }
}

$ingredientNameOwned = "감자"
$ingredientNameMissing = "양파"

Write-Host "[1/7] Create ingredient..."
$createIngredientUrl = "$($BaseUrl)?type=kitchen&view=ingredients"
$createIngredientRes = Invoke-Kitchen -Method POST -Url $createIngredientUrl -Body @{ name = $ingredientNameOwned }
Assert-OkResponse -Response $createIngredientRes -Step "create ingredient"
$ingredientId = $createIngredientRes.data.id
if ([string]::IsNullOrWhiteSpace($ingredientId)) {
    throw "[create ingredient] ingredient id is empty"
}

Write-Host "[2/7] Create shopping list from recipe..."
$createShoppingUrl = "$($BaseUrl)?type=kitchen&action=create-shopping-from-recipe"
$createShoppingRes = Invoke-Kitchen -Method POST -Url $createShoppingUrl -Body @{
    recipe_type = "public"
    recipe_id = $RecipeId
    recipe_title = $RecipeTitle
    required_ingredients = @($ingredientNameOwned, $ingredientNameMissing)
}
Assert-OkResponse -Response $createShoppingRes -Step "create shopping"
$listId = $createShoppingRes.data.shopping_list.id
if ([string]::IsNullOrWhiteSpace($listId)) {
    throw "[create shopping] shopping list id is empty"
}

Write-Host "[3/7] Fetch shopping list and pick one item..."
$listUrl = "$($BaseUrl)?type=kitchen&view=shopping-lists&status=active"
$listRes = Invoke-Kitchen -Method GET -Url $listUrl
Assert-OkResponse -Response $listRes -Step "list shopping"

$firstList = $listRes.data | Where-Object { $_.id -eq $listId } | Select-Object -First 1
if ($null -eq $firstList) {
    throw "[list shopping] created list not found"
}

$firstItem = $firstList.items | Select-Object -First 1
if ($null -eq $firstItem) {
    throw "[list shopping] no shopping item found"
}

Write-Host "[4/7] Toggle shopping item checked=true..."
$toggleUrl = "$($BaseUrl)?type=kitchen&view=shopping-item&id=$($firstItem.id)"
$toggleRes = Invoke-Kitchen -Method PATCH -Url $toggleUrl -Body @{ is_checked = $true }
Assert-OkResponse -Response $toggleRes -Step "toggle shopping item"

Write-Host "[5/7] Complete shopping list..."
$completeShoppingUrl = "$($BaseUrl)?type=kitchen&action=complete-shopping-list&id=$listId"
$completeShoppingRes = Invoke-Kitchen -Method POST -Url $completeShoppingUrl
Assert-OkResponse -Response $completeShoppingRes -Step "complete shopping"

Write-Host "[6/7] Complete cook session with feedback..."
$completeCookUrl = "$($BaseUrl)?type=kitchen&action=complete-cook"
$completeCookRes = Invoke-Kitchen -Method POST -Url $completeCookUrl -Body @{
    recipe_type = "public"
    recipe_id = $RecipeId
    recipe_title = $RecipeTitle
    rating = 4
    liked = $true
    note = "kitchen smoke"
}
Assert-OkResponse -Response $completeCookRes -Step "complete cook"

Write-Host "[7/7] Fetch summary and history..."
$summaryUrl = "$($BaseUrl)?type=kitchen&view=summary"
$summaryRes = Invoke-Kitchen -Method GET -Url $summaryUrl
Assert-OkResponse -Response $summaryRes -Step "summary"

$historyUrl = "$($BaseUrl)?type=kitchen&view=cook-sessions"
$historyRes = Invoke-Kitchen -Method GET -Url $historyUrl
Assert-OkResponse -Response $historyRes -Step "history"

$historyCount = @($historyRes.data).Count
if ($historyCount -lt 1) {
    throw "[history] expected at least one cook session"
}

Write-Host "Smoke passed."
Write-Host ("Summary: ingredients={0}, expiring={1}, active_lists={2}, open_items={3}, recent_cook_7d={4}" -f `
    $summaryRes.data.ingredient_count,
    $summaryRes.data.expiring_soon_count,
    $summaryRes.data.active_shopping_list_count,
    $summaryRes.data.open_shopping_item_count,
    $summaryRes.data.recent_cook_count_7d)
