# End-to-end check against the running local stack and the real Salesforce org. Each case creates
# its own Opportunity and closes it, so the Flow, the Platform Event and the listener are all used.
# Start the stack first with run-local.ps1. Exits 1 if any case fails.
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$envFile = @{}
Get-Content "$repo\.env" | Where-Object { $_ -match '^\s*[^#\s][^=]*=' } | ForEach-Object { $k, $v = $_ -split '=', 2; $envFile[$k.Trim()] = $v.Trim() }
$token = Invoke-RestMethod -Method Post -Uri $envFile['salesforce.tokenUrl'] -Body @{
    grant_type = 'client_credentials'; client_id = $envFile['salesforce.clientId']; client_secret = $envFile['salesforce.clientSecret']
}
$headers = @{ Authorization = "Bearer $($token.access_token)" }
$api = "$($token.instance_url)/services/data/v62.0"
$seed = "$PSScriptRoot\seed-salesforce.ps1"
$script:failures = 0

function Close-Won($id) {
    Invoke-RestMethod -Method Patch -Uri "$api/sobjects/Opportunity/$id" -Headers $headers -ContentType 'application/json' -Body '{"StageName":"Closed Won"}' | Out-Null
}
function Wait-Result($id, $seconds = 90) {
    $deadline = (Get-Date).AddSeconds($seconds)
    do {
        Start-Sleep -Seconds 2
        $o = Invoke-RestMethod -Uri "$api/sobjects/Opportunity/${id}?fields=ERP_Order_Id__c,ERP_Status__c,ERP_Error__c" -Headers $headers
    } while (-not $o.ERP_Status__c -and (Get-Date) -lt $deadline)
    $o
}
# Windows PowerShell returns a JSON array as one object, so pipe it to unroll it before counting.
function Get-List($url, $headers = @{}) { @(Invoke-RestMethod $url -Headers $headers | ForEach-Object { $_ }) }
function Erp-Orders($id) { Get-List "http://localhost:8082/api/sales-orders?sfOpportunityId=$id" }
$erpToken = if ($envFile['ERP_API_KEY']) { "token $($envFile['ERP_API_KEY']):$($envFile['ERP_API_SECRET'])" } else { 'token mock-key:mock-secret' }
function Erp-CustomerCount { @((Invoke-RestMethod 'http://localhost:8090/api/resource/Customer' -Headers @{ authorization = $erpToken }).data).Count }
function Check($name, $ok, $detail) {
    if ($ok) { Write-Host "PASS  $name  ($detail)" } else { Write-Host "FAIL  $name  ($detail)"; $script:failures++ }
}

# Happy path, with a new customer.
$account = "E2E Customer $(Get-Date -Format 'HHmmss')"
$id = & $seed -Name "E2E happy path" -Account $account
Close-Won $id
$r = Wait-Result $id
Check 'Closed Won creates an order and writes it back' ($r.ERP_Order_Id__c -and $r.ERP_Status__c -ne 'Failed') "$($r.ERP_Order_Id__c) / $($r.ERP_Status__c)"

# Duplicate event: replay the same Opportunity.
$before = @(Erp-Orders $id).Count
Invoke-RestMethod -Method Post http://localhost:8083/api/orders/sync -ContentType 'application/json' -Body (@{ opportunityId = $id } | ConvertTo-Json) | Out-Null
$after = @(Erp-Orders $id).Count
Check 'Duplicate event creates no second order' ($before -eq 1 -and $after -eq 1) "orders in ERP: $before -> $after"

# Customer already exists: same Account, new Opportunity.
$customersBefore = Erp-CustomerCount
$id2 = & $seed -Name "E2E existing customer" -Account $account
Close-Won $id2
$r2 = Wait-Result $id2
$customersAfter = Erp-CustomerCount
Check 'Existing customer is reused' ($r2.ERP_Order_Id__c -and $customersBefore -ge 1 -and $customersAfter -eq $customersBefore) "$($r2.ERP_Order_Id__c), customers $customersBefore -> $customersAfter"

# Short outage: two 503s, then the retry succeeds.
Invoke-RestMethod -Method Post 'http://localhost:8090/__admin/fail?count=2' | Out-Null
$id3 = & $seed -Name "E2E retry" -Account $account
Close-Won $id3
$r3 = Wait-Result $id3
Check 'Short ERP outage recovers by retrying' ($r3.ERP_Order_Id__c -and $r3.ERP_Status__c -ne 'Failed') "$($r3.ERP_Order_Id__c) / $($r3.ERP_Status__c)"

# Long outage: retries run out, the Opportunity is marked Failed, and a replay fixes it.
Invoke-RestMethod -Method Post 'http://localhost:8090/__admin/fail?count=8' | Out-Null
$id4 = & $seed -Name "E2E outage" -Account $account
Close-Won $id4
$r4 = Wait-Result $id4
Check 'Long ERP outage marks Failed' ($r4.ERP_Status__c -eq 'Failed') "$($r4.ERP_Status__c): $($r4.ERP_Error__c)"
Invoke-RestMethod -Method Post 'http://localhost:8090/__admin/fail?count=0' | Out-Null
Invoke-RestMethod -Method Post http://localhost:8083/api/orders/sync -ContentType 'application/json' -Body (@{ opportunityId = $id4 } | ConvertTo-Json) | Out-Null
$r4b = Wait-Result $id4
Check 'Replay after the outage succeeds and clears the error' ($r4b.ERP_Order_Id__c -and $r4b.ERP_Status__c -ne 'Failed' -and -not $r4b.ERP_Error__c) "$($r4b.ERP_Order_Id__c) / $($r4b.ERP_Status__c)"

# Bad data: no line items, caught before the ERP.
$id5 = & $seed -Name "E2E no line items" -Account $account -NoLineItems
Close-Won $id5
$r5 = Wait-Result $id5
Check 'No line items marks Failed with the reason' ($r5.ERP_Status__c -eq 'Failed' -and $r5.ERP_Error__c -match 'line items') "$($r5.ERP_Error__c)"

# Bad data: the ERP does not know this product.
$id6 = & $seed -Name "E2E unknown product" -Account $account -ProductCode 'UNKNOWN-1'
Close-Won $id6
$r6 = Wait-Result $id6
Check 'Unknown product marks Failed with the reason' ($r6.ERP_Status__c -eq 'Failed' -and $r6.ERP_Error__c -match 'Item Code') "$($r6.ERP_Error__c)"

# Read-only status API.
$s = Invoke-RestMethod "http://localhost:8084/api/orders/$id/status"
Check 'Status API returns the order' ($s.erpOrderId -eq $r.ERP_Order_Id__c) "$($s.erpOrderId)"
$since = (Get-Date).ToUniversalTime().Date.ToString('yyyy-MM-ddTHH:mm:ssZ')
$failed = Get-List "http://localhost:8084/api/orders/failed?since=$since"
Check 'Failed-orders API lists the failures' (($failed.opportunityId -contains $id5) -and ($failed.opportunityId -contains $id6)) "$($failed.Count) failed today"

if ($script:failures) { Write-Host "$script:failures case(s) failed"; exit 1 }
Write-Host 'All cases passed'
