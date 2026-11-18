# Day 1 setup

The files are already written. These steps connect them to your accounts.

## 1. Start the mock ERP

```powershell
node mock-erp/server.mjs
```

It runs on `http://localhost:8090`. In a second terminal, check it:

```powershell
node mock-erp/test.mjs
```

## 2. Create the Salesforce org

Sign up for a free Developer Edition org at developer.salesforce.com/signup.

## 3. Deploy the Salesforce metadata

This adds the Opportunity fields, the `OrderRequested__e` event, the Flow, a permission set and the page layout.

```powershell
npm install -g @salesforce/cli
cd salesforce
sf org login web --alias erp-demo --instance-url https://YOUR-ORG.develop.my.salesforce.com
sf project deploy start --target-org erp-demo
sf org assign permset --name ERP_Order_Sync --target-org erp-demo
```

To get your login URL, take your Salesforce address and replace `.lightning.force.com` and everything after it with `.my.salesforce.com`. The login has only worked once the terminal prints `Successfully authorized`. Being signed in to Salesforce in the browser isn't enough.

The deploy also adds an **ERP Order** section with the four ERP fields to the Opportunity page layout.

## 4. Create the External Client App

This replaces the Connected App in the original plan, because new Connected Apps are off by default.

1. In Setup, open **External Client App Manager** and click **New External Client App**.
2. Enable OAuth. Use `http://localhost:8081/callback` as the callback URL, and add the `api` scope.
3. Enable **Client Credentials Flow**.
4. Under **Policies**, enable Client Credentials and set **Run As** to your user.
5. Copy the consumer key and secret into `.env` at the repo root (see `.env.example`). This file is gitignored, so don't put them in `config.yaml`.

Check that it works. Replace the three values, and use your org's My Domain URL:

```powershell
curl.exe -X POST "https://YOUR-DOMAIN.my.salesforce.com/services/oauth2/token" -d "grant_type=client_credentials&client_id=YOUR_KEY&client_secret=YOUR_SECRET"
```

You should get back JSON containing `access_token`.

## 5. Add test products

Create products in Salesforce with these Product Codes, then add them to an Opportunity as line items. The mock ERP only accepts these codes.

- `WIDGET-100`
- `WIDGET-200`
- `SUPPORT-1Y`

## 6. Test the Flow

Set an Opportunity's stage to Closed Won. In **Setup > Flows**, the Flow should be active with no errors. You'll see the event arrive once the Mule app is running on Day 2.

## 7. Exchange

Publish `specs/` to Exchange on Day 3, when the Anypoint trial starts. The specs stay local until then.
