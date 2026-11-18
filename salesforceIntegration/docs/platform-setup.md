# Anypoint Platform setup

**Status: not done yet, and none of these steps have been run.** They need an Anypoint Platform trial, and the trial is time-limited, so start it shortly before you need it. The steps below are written from the plan and may need small corrections on the first run.

## 1. Connected App

In Anypoint, open **Access Management > Connected Apps** and create an app that acts on its own behalf. Give it these scopes in your environment:

- Exchange Contributor
- Runtime Manager: Read and Create Applications, plus Cloudhub Network Viewer
- API Manager: Environment Administrator

Use the client ID and secret in the next steps.

## 2. Exchange

```powershell
$env:ANYPOINT_CLIENT_ID = '...'; $env:ANYPOINT_CLIENT_SECRET = '...'; $env:ANYPOINT_ORG = '<business group ID>'
.\salesforceIntegration\scripts\publish-exchange.ps1
```

## 3. GitHub Actions

Add these under **Settings > Secrets and variables > Actions**. The first two are needed for every build, because the Salesforce and MCP connectors come from Exchange.

| Secret | Value |
|---|---|
| `ANYPOINT_CLIENT_ID`, `ANYPOINT_CLIENT_SECRET` | From step 1 |
| `SF_CLIENT_ID`, `SF_CLIENT_SECRET`, `SF_TOKEN_URL` | Same values as `.env`. Only needed to deploy |
| `ERP_API_KEY`, `ERP_API_SECRET` | Your ERP's values. Only needed to deploy |

## 4. API Manager (Experience API)

1. Open **API Manager > Add API** and choose `order-status-exp-api` from Exchange.
2. Copy the API instance ID into `order-status-exp-api.xml`, so the gateway can pair the app with it:

   ```xml
   <api-gateway:autodiscovery apiId="${api.id}" flowRef="order-status-exp-api-main"/>
   ```

   Add the `api-gateway` namespace, and pass your platform client ID and secret as `anypoint.platform.client_id` and `anypoint.platform.client_secret` at startup.
3. Under **Policies**, add **Client ID Enforcement**.
4. Add **Rate Limiting**. Start with 60 requests per minute.
5. Check it: a call with no client ID should get `401`, and going over the limit should get `429`.

The MCP endpoint is a separate listener, so these policies do not cover it. It listens on `127.0.0.1` only. If it ever moves off this machine, it needs its own authentication first.

## 5. Monitoring and alerts

Add alerts in **Anypoint Monitoring** or Runtime Manager for:

| Alert | Condition |
|---|---|
| App down | Any of the four apps stops |
| Errors rising | `order-process-api` error count above 0 for 5 minutes |

Log-based alerts depend on your plan. If yours doesn't include them, schedule a call to `GET /orders/failed` and notify someone when it returns anything. The runbook lists the log lines to alert on.

## 6. CloudHub 2.0 (only with a public ERP)

CloudHub cannot reach a mock ERP on a laptop, so this project runs locally and the deploy jobs stay off. To turn them on:

1. Host the ERP where CloudHub can reach it, and set `ERP_API_KEY` and `ERP_API_SECRET`.
2. In each `pom.xml`, set `groupId` to your business group ID. CloudHub deploys from Exchange, so it has to match.
3. Create `dev` and `prod` GitHub environments. In each, set the variables `ANYPOINT_ENVIRONMENT` and `CLOUDHUB_TARGET`. Add required reviewers to `prod`.
4. Set the repo variable `DEPLOY_ENABLED` to `true`.

Keep `order-process-api` on one replica. The Platform Event listener would otherwise run once per replica.
