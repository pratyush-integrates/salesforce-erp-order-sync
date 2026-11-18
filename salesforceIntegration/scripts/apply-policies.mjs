// Applies the API Manager policies. Safe to run again: a policy already on an API is left alone.
// The internal APIs have public URLs on a CloudHub shared space, so they get Basic Auth: Simple with
// one service credential. The Experience API gets Client ID Enforcement and Rate Limiting.
//
//   node scripts/apply-policies.mjs
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const e = {};
for (const line of fs.readFileSync(path.join(repo, '.env'), 'utf8').split(/\r?\n/)) {
  const m = line.match(/^\s*([^#\s][^=]*)=(.*)$/);
  if (m) e[m[1].trim()] = m[2].trim();
}

const BASE = 'https://anypoint.mulesoft.com';
const token = (await (await fetch(`${BASE}/accounts/api/v2/oauth2/token`, {
  method: 'POST',
  body: new URLSearchParams({ grant_type: 'client_credentials', client_id: e.ANYPOINT_CLIENT_ID, client_secret: e.ANYPOINT_CLIENT_SECRET }),
})).json()).access_token;
const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json' };
const org = e.ANYPOINT_ORG;

async function call(method, url, body) {
  const res = await fetch(BASE + url, { method, headers, body: body && JSON.stringify(body) });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url} returned ${res.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

const envs = await call('GET', `/accounts/api/organizations/${org}/environments`);
const envId = envs.data.find((x) => x.name === e.ANYPOINT_ENVIRONMENT).id;
const apiRoot = `/apimanager/api/v1/organizations/${org}/environments/${envId}/apis`;
const POLICY_GROUP = '68ef9520-24e9-4cf2-b2f5-620025690913';

const basicAuth = { assetId: 'http-basic-authentication', assetVersion: '1.3.3', configurationData: { username: e.INTERNAL_USER, password: e.INTERNAL_PASSWORD } };
const plan = {
  [e.API_ID_salesforce_sys_api]: [basicAuth],
  [e.API_ID_erp_sys_api]: [basicAuth],
  [e.API_ID_order_process_api]: [basicAuth],
  [e.API_ID_order_status_exp_api]: [
    {
      assetId: 'client-id-enforcement',
      assetVersion: '1.3.4',
      configurationData: {
        credentialsOriginHasHttpBasicAuthenticationHeader: 'customExpression',
        clientIdExpression: "#[attributes.headers['client_id']]",
        clientSecretExpression: "#[attributes.headers['client_secret']]",
      },
    },
    {
      assetId: 'rate-limiting',
      assetVersion: '1.4.2',
      configurationData: {
        rateLimits: [{ maximumRequests: 60, timePeriodInMilliseconds: 60000 }],
        clusterizable: true,
        exposeHeaders: true,
        keySelector: "#[attributes.headers['client_id']]",
      },
    },
  ],
};

for (const [apiId, policies] of Object.entries(plan)) {
  const current = await call('GET', `${apiRoot}/${apiId}/policies`);
  const applied = (current.policies ?? current).map((p) => p.template?.assetId ?? p.assetId);
  for (const policy of policies) {
    if (applied.includes(policy.assetId)) {
      console.log(`${apiId}: ${policy.assetId} already applied`);
      continue;
    }
    await call('POST', `${apiRoot}/${apiId}/policies`, {
      configurationData: policy.configurationData,
      groupId: POLICY_GROUP,
      assetId: policy.assetId,
      assetVersion: policy.assetVersion,
      pointcutData: null,
    });
    console.log(`${apiId}: applied ${policy.assetId} ${policy.assetVersion}`);
  }
}
