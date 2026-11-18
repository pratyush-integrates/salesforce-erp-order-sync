# Demo script (about 5 minutes)

## Before you start

1. Run `.\scripts\run-local.ps1` from `salesforceIntegration` and wait for all apps to deploy, about 3 minutes.
2. In a second terminal, run these and note the IDs. Each creates an open Opportunity in Salesforce.

   ```powershell
   .\scripts\seed-salesforce.ps1 -Name "Acme - 2 widgets" -Account "Acme Ltd"
   .\scripts\seed-salesforce.ps1 -Name "Globex - outage" -Account "Globex"
   ```

3. Open three things side by side: the first Opportunity in Salesforce, the `order-process-api` log, and a Claude Code session in the repo root.

## 1. The happy path (1 minute)

Set "Acme - 2 widgets" to **Closed Won**, then refresh the page.

**Point out:** the ERP order number and status are now on the Opportunity, and nobody typed them. In the log, follow `Event received`, then the ERP calls, then `synced to order`.

Show the order in the ERP:

```powershell
Invoke-RestMethod 'http://localhost:8090/api/resource/Sales Order' -Headers @{ authorization = 'token mock-key:mock-secret' } | ConvertTo-Json -Depth 5
```

## 2. A failure, and the retry (2 minutes)

Make the ERP fail, then close "Globex - outage":

```powershell
Invoke-RestMethod -Method Post 'http://localhost:8090/__admin/fail?count=8'
```

**Point out:** the log shows `Will retry` four times, then `Order sync FAILED`. Salesforce shows `Failed` with the reason, so the rep can see it without opening a log.

Replay it, which also clears the simulated outage:

```powershell
Invoke-RestMethod -Method Post 'http://localhost:8090/__admin/fail?count=0'
Invoke-RestMethod -Method Post http://localhost:8083/api/orders/sync -ContentType 'application/json' -Body '{"opportunityId":"<Globex ID>"}'
```

**Point out:** the error is gone and the order number is there. Replay this again and the log says `Creating nothing`, because the Opportunity ID is the idempotency key.

## 3. Ask Claude (1 minute)

Before the replay in step 2, or using a new bad order, ask:

> Which orders failed today, and why?

**Point out:** Claude has only two read-only tools, so it can answer questions but cannot change an order.

## Say plainly

- The ERP is a mock of ERPNext's API, and a real one would only change `erp-sys-api`.
- This runs locally, because CloudHub can't reach a mock on a laptop. The pipeline's deploy jobs are written but switched off.
