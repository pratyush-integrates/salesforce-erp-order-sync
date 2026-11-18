# Creates demo data in the Salesforce org: the products the ERP accepts, an Account, and an open
# Opportunity with line items. Safe to run again: it reuses products and the Account, and each run
# adds one new Opportunity. Prints that Opportunity's ID.
#
#   .\scripts\seed-salesforce.ps1
#   .\scripts\seed-salesforce.ps1 -Name "Bad data demo" -NoLineItems
param([string]$Name = "Demo order $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", [string]$Account = 'Demo Customer Ltd', [switch]$NoLineItems, [string]$ProductCode = 'WIDGET-100')

$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$envFile = @{}
Get-Content "$repo\.env" | Where-Object { $_ -match '^\s*[^#\s][^=]*=' } | ForEach-Object { $k, $v = $_ -split '=', 2; $envFile[$k.Trim()] = $v.Trim() }

$token = Invoke-RestMethod -Method Post -Uri $envFile['salesforce.tokenUrl'] -Body @{
    grant_type = 'client_credentials'; client_id = $envFile['salesforce.clientId']; client_secret = $envFile['salesforce.clientSecret']
}
$headers = @{ Authorization = "Bearer $($token.access_token)" }
$api = "$($token.instance_url)/services/data/v62.0"

function Query($soql) { (Invoke-RestMethod -Uri "$api/query?q=$([uri]::EscapeDataString($soql))" -Headers $headers).records }
function Create($object, $body) {
    (Invoke-RestMethod -Method Post -Uri "$api/sobjects/$object" -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json)).id
}

$standard = (Query 'SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true')[0]
if (-not $standard.IsActive) {
    Invoke-RestMethod -Method Patch -Uri "$api/sobjects/Pricebook2/$($standard.Id)" -Headers $headers -ContentType 'application/json' -Body '{"IsActive":true}' | Out-Null
}

$prices = @{ 'WIDGET-100' = 100; 'WIDGET-200' = 250; 'SUPPORT-1Y' = 1200; 'UNKNOWN-1' = 10 }
foreach ($code in $prices.Keys) {
    $product = (Query "SELECT Id FROM Product2 WHERE ProductCode = '$code'") | Select-Object -First 1
    $productId = if ($product) { $product.Id } else { Create 'Product2' @{ Name = $code; ProductCode = $code; IsActive = $true } }
    if (-not (Query "SELECT Id FROM PricebookEntry WHERE Product2Id = '$productId' AND Pricebook2Id = '$($standard.Id)'")) {
        Create 'PricebookEntry' @{ Pricebook2Id = $standard.Id; Product2Id = $productId; UnitPrice = $prices[$code]; IsActive = $true } | Out-Null
    }
}

$escaped = $Account -replace "'", "\'"
$acct = (Query "SELECT Id FROM Account WHERE Name = '$escaped'") | Select-Object -First 1
$accountId = if ($acct) { $acct.Id } else { Create 'Account' @{ Name = $Account } }

$oppId = Create 'Opportunity' @{
    Name = $Name; AccountId = $accountId; StageName = 'Prospecting'
    CloseDate = (Get-Date).AddDays(30).ToString('yyyy-MM-dd'); Pricebook2Id = $standard.Id
}
if (-not $NoLineItems) {
    $entry = (Query "SELECT Id, UnitPrice FROM PricebookEntry WHERE Product2.ProductCode = '$ProductCode' AND Pricebook2Id = '$($standard.Id)'")[0]
    Create 'OpportunityLineItem' @{ OpportunityId = $oppId; PricebookEntryId = $entry.Id; Quantity = 2; UnitPrice = $entry.UnitPrice } | Out-Null
}
$oppId
