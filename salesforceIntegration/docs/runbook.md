# Runbook: order sync

**What it does:** turns a Closed Won Opportunity into an ERP sales order and writes the result back to Salesforce.

**Logs:** `salesforceIntegration/.mule-local/logs/mule-app-<api>-app-1.0.0-mule-application.log`

## Is it healthy?

```powershell
node salesforceIntegration/scripts/mcp-check.mjs         # MCP server and status API
powershell salesforceIntegration/scripts/e2e-test.ps1    # Full check. Creates test Opportunities
```

Or ask Claude: "which orders failed today?"

## Find failures

| Where | What to look for |
|---|---|
| Salesforce | `ERP_Status__c = Failed`, with the reason in `ERP_Error__c` |
| `order-process-api` log | `Order sync FAILED for Opportunity <id>` at ERROR |
| `order-process-api` log | `ALERT: could not mark Opportunity <id> as Failed`: Salesforce was down too, so **Salesforce won't show this failure** |
| `erp-sys-api` log | `ERP request failed: <error type> -> <status>` |

These two log lines are the alert conditions:

```powershell
Select-String -Path salesforceIntegration\.mule-local\logs\mule-app-order-process-api-*.log -Pattern 'Order sync FAILED|ALERT:'
```

## Fix failures

| `ERP_Error__c` | Cause | Fix |
|---|---|---|
| `A downstream system was unavailable after retries` | ERP or Salesforce was down | Fix the outage, then replay |
| `Could not find Item Code: X` | The Product Code isn't in the ERP | Add the item or correct the product, then replay |
| `Opportunity has no line items` | Rep closed it with no products | Add line items, then replay |
| `Opportunity has no Account` | No Account on the Opportunity | Set the Account, then replay |

**To replay:** safe to run any number of times, because the code looks for an existing order first.

```powershell
Invoke-RestMethod -Method Post http://localhost:8083/api/orders/sync -ContentType 'application/json' -Body '{"opportunityId":"<id>"}'
```

## Outage longer than 72 hours

Salesforce keeps events for 72 hours. After a longer outage, find Closed Won Opportunities with an empty `ERP_Status__c` and replay each one.

## Drills

Both were run on 2 November 2026 against the real Salesforce org. The output below is from those runs.

### Stop the ERP

Stopped the mock ERP process, then closed an Opportunity.

**Salesforce, 9 seconds later:** `ERP_Status__c = Failed`, `ERP_Error__c = A downstream system was unavailable after retries`.

**How the logs showed the cause.** The ERROR line in `order-process-api` gave the symptom, and the `erp-sys-api` log gave the reason:

```text
order-process-api
15:44:04 INFO  Event received for Opportunity 006fj00000P6xS1AAJ
15:44:04 WARN  Got 503 from /api/sales-orders. Will retry.
15:44:06 WARN  Got 503 from /api/sales-orders. Will retry.
15:44:08 WARN  Got 503 from /api/sales-orders. Will retry.
15:44:10 WARN  Got 503 from /api/sales-orders. Will retry.
15:44:10 ERROR Order sync FAILED for Opportunity 006fj00000P6xS1AAJ: A downstream system was unavailable after retries

erp-sys-api
15:44:10 WARN  ERP request failed: HTTP:CONNECTIVITY -> 503
Message : HTTP GET on resource 'http://localhost:8090/api/resource/Sales%20Order' failed: Connection refused
```

**Recovery:** restarted the ERP and replayed. Salesforce then showed order `SAL-ORD-2026-00001`, status `To Deliver and Bill`, with the error cleared.

### Send a duplicate

Published `OrderRequested__e` again for the same Opportunity.

```text
15:44:22 INFO  Opportunity 006fj00000P6xS1AAJ already has order SAL-ORD-2026-00001. Creating nothing.
```

The ERP held 1 order for that Opportunity before and after.

## Known problems

| Symptom | Cause | Fix |
|---|---|---|
| Closed Won does nothing, with no `Event received` log and no errors | Mule saved the listener as stopped after a `-NoEvents` run, and it prefers that over the XML | `run-local.ps1` now clears the saved state. On a runtime you manage, delete `flows.deployment.properties` for the app and restart |
| `Couldn't find configuration property value for key ${http.port}` | `config.yaml` has a byte-order mark, usually from PowerShell's `-Encoding utf8` | Save it as UTF-8 without a BOM |
| Order numbers restart at `00001` | The mock ERP keeps data in memory and was restarted | Expected. Restart it only when you need a clean demo |
| The build fails to load the Mule plugin | Maven 3.10 | Use Maven 3.9, as `run-local.ps1` and CI do |
