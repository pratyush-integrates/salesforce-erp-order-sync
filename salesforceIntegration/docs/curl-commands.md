# curl commands

Every endpoint on the local stack. Start it first with `.\scripts\run-local.ps1 -Tunnel`.

These are for Windows PowerShell, run from `salesforceIntegration`. They use `curl.exe`, because `curl` on its own is an alias for `Invoke-WebRequest` there. JSON bodies are piped in with `-d '@-'`, because PowerShell 5.1 breaks JSON that contains spaces when it's passed as an argument.

## Setup

Run this once in your terminal. Every command below uses these variables.

```powershell
$opp   = '006fj00000P7zGTAAZ'    # An Opportunity ID. seed-salesforce.ps1 prints a new one
$order = 'SAL-ORD-2026-00001'    # An ERP order ID. Mock ERP data resets when the stack restarts
$since = (Get-Date).ToUniversalTime().Date.ToString('yyyy-MM-ddTHH:mm:ssZ')    # Start of today, UTC
$json  = 'Content-Type: application/json'

$envVals = @{}
Get-Content ..\.env | Where-Object { $_ -match '^\s*[^#\s][^=]*=' } | ForEach-Object { $k, $v = $_ -split '=', 2; $envVals[$k.Trim()] = $v.Trim() }
$erpAuth = "authorization: token $($envVals['ERP_API_KEY']):$($envVals['ERP_API_SECRET'])"
$tunnel  = (Get-Content .mule-local\logs\tunnel-url.txt).Trim()
```

## salesforce-sys-api (port 8081)

```powershell
# List Opportunities by ERP status. since is optional
curl.exe "http://localhost:8081/api/opportunities?erpStatus=Failed&since=$since"

# Get an Opportunity with its Account and line items
curl.exe "http://localhost:8081/api/opportunities/$opp"

# Write an ERP result to the Opportunity. Changes the record in Salesforce. Returns 204
'{"erpOrderId":"SAL-ORD-2026-00001","erpStatus":"To Deliver and Bill","erpError":null}' | curl.exe -i -X PATCH "http://localhost:8081/api/opportunities/$opp" -H $json -d '@-'

# Not found. Returns 404
curl.exe -i "http://localhost:8081/api/opportunities/006000000000000AAA"
```

## erp-sys-api (port 8082)

```powershell
# Create a customer. Returns 201, or 409 if the Account already has one
'{"name":"Curl Test Customer","sfAccountId":"001CURLTEST"}' | curl.exe -i -X POST "http://localhost:8082/api/customers" -H $json -d '@-'

# Find a customer by Salesforce Account ID
curl.exe "http://localhost:8082/api/customers?sfAccountId=001CURLTEST"

# Create a sales order. customerId is the id returned when the customer was created.
# The ERP accepts WIDGET-100, WIDGET-200 and SUPPORT-1Y. Returns 201, or 409 if the Opportunity already has one
$today = (Get-Date).ToString('yyyy-MM-dd'); $later = (Get-Date).AddDays(14).ToString('yyyy-MM-dd')
('{"customerId":"Curl Test Customer","sfOpportunityId":"006CURLTEST","orderDate":"' + $today + '","deliveryDate":"' + $later + '","items":[{"itemCode":"WIDGET-100","quantity":2,"unitPrice":100}]}') | curl.exe -i -X POST "http://localhost:8082/api/sales-orders" -H $json -d '@-'

# Find a sales order by Salesforce Opportunity ID
curl.exe "http://localhost:8082/api/sales-orders?sfOpportunityId=006CURLTEST"

# Get a sales order and its status
curl.exe "http://localhost:8082/api/sales-orders/$order"
```

## order-process-api (port 8083)

```powershell
# Create the ERP order for an Opportunity, or return the existing one. This is how a failed order is replayed.
# Changes the record in Salesforce, and marks it Failed if the ERP can't be reached
('{"opportunityId":"' + $opp + '"}') | curl.exe -i -X POST "http://localhost:8083/api/orders/sync" -H $json -d '@-'

# List orders by status. since is optional
curl.exe "http://localhost:8083/api/orders?status=Failed&since=$since"

# Get the order status for an Opportunity
curl.exe "http://localhost:8083/api/orders/$opp"
```

## order-status-exp-api (port 8084)

```powershell
# List failed orders with the reason for each. since is optional
curl.exe "http://localhost:8084/api/orders/failed?since=$since"

# Get the ERP order status for an Opportunity
curl.exe "http://localhost:8084/api/orders/$opp/status"
```

## MCP server (port 8085)

MCP needs a session, so run `initialize` first. Replies are streamed, so `-m 5` stops curl after 5 seconds instead of leaving it waiting on the open stream. curl reports a timeout when that happens, which is expected.

```powershell
$mcp = @('-s', '-m', '5', '-X', 'POST', 'http://127.0.0.1:8085/mcp', '-H', $json, '-H', 'Accept: application/json, text/event-stream')

# Start a session and keep its ID
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}' | curl.exe @mcp -i -d '@-'
$init
$session = (($init | Select-String -Pattern '^mcp-session-id:\s*(.+)$').Matches.Groups[1].Value).Trim()
'{"jsonrpc":"2.0","method":"notifications/initialized"}' | curl.exe @mcp -H "mcp-session-id: $session" -d '@-'

# List the tools
'{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | curl.exe @mcp -H "mcp-session-id: $session" -d '@-'

# Call get_order_status
('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_order_status","arguments":{"opportunityId":"' + $opp + '"}}}') | curl.exe @mcp -H "mcp-session-id: $session" -d '@-'

# Call list_failed_orders
('{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_failed_orders","arguments":{"since":"' + $since + '"}}}') | curl.exe @mcp -H "mcp-session-id: $session" -d '@-'
```

## Mock ERP (port 8090)

```powershell
# List customers and sales orders
curl.exe "http://localhost:8090/api/resource/Customer" -H $erpAuth
curl.exe "http://localhost:8090/api/resource/Sales%20Order" -H $erpAuth

# Get one sales order
curl.exe "http://localhost:8090/api/resource/Sales%20Order/$order" -H $erpAuth

# Make the next 2 ERP calls return 503. The retry recovers, so the order still succeeds
curl.exe -X POST "http://localhost:8090/__admin/fail?count=2"

# Make the next 8 fail, so retries run out and the order is marked Failed
curl.exe -X POST "http://localhost:8090/__admin/fail?count=8"

# End a simulated outage
curl.exe -X POST "http://localhost:8090/__admin/fail?count=0"
```

## Mock ERP through the tunnel

```powershell
# Works. Returns 200
curl.exe -i "$tunnel/api/resource/Customer" -H $erpAuth

# No API key. Returns 401
curl.exe -i "$tunnel/api/resource/Customer"

# The failure switch is blocked from outside. Returns 403
curl.exe -i -X POST "$tunnel/__admin/fail?count=1"
```
