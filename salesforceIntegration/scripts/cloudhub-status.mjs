// Prints each CloudHub deployment's status, public URL and replica state.
//
//   node scripts/cloudhub-status.mjs
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
const get = async (url) => (await fetch(BASE + url, { headers: { authorization: `Bearer ${token}` } })).json();

const envs = await get(`/accounts/api/organizations/${e.ANYPOINT_ORG}/environments`);
const envId = envs.data.find((x) => x.name === e.ANYPOINT_ENVIRONMENT).id;
const root = `/amc/application-manager/api/v2/organizations/${e.ANYPOINT_ORG}/environments/${envId}/deployments`;

for (const item of (await get(root)).items ?? []) {
  const d = await get(`${root}/${item.id}`);
  console.log(`${d.name}: ${d.status} / app ${d.application?.status} / desired ${d.application?.desiredState}`);
  console.log(`  url ${d.target?.deploymentSettings?.http?.inbound?.publicUrl ?? 'none'}`);
  for (const r of d.replicas ?? []) console.log(`  replica ${r.state} ${r.deploymentLocation ?? ''} ${r.reason ?? ''}`);
  if (d.lastSuccessfulVersion) console.log(`  last good ${d.lastSuccessfulVersion}`);
  const errs = d.errors ?? d.application?.errors;
  if (errs?.length) console.log(`  errors ${JSON.stringify(errs).slice(0, 400)}`);
}
