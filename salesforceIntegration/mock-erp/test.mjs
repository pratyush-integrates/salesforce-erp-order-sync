// Checks the mock behaves as erp-sys-api expects. Start the server first, then: node mock-erp/test.mjs
import assert from 'node:assert/strict';

const BASE = process.env.ERP_URL ?? 'http://localhost:8090';
const run = Date.now().toString(36);
const auth = { authorization: 'token mock-key:mock-secret', 'content-type': 'application/json' };
const post = (path, body, headers = auth) => fetch(BASE + path, { method: 'POST', headers, body: JSON.stringify(body) });
const get = (path) => fetch(BASE + path, { headers: auth });

const CUSTOMERS = '/api/resource/Customer';
const ORDERS = '/api/resource/Sales%20Order';
const acc = `001${run}`;
const opp = `006${run}`;
const order = (over = {}) => ({
  customer: `Acme ${run}`, company: 'Demo Manufacturing', transaction_date: '2026-11-01', delivery_date: '2026-11-15',
  custom_sf_opportunity_id: opp, items: [{ item_code: 'WIDGET-100', qty: 2, rate: 95 }], ...over,
});
const byField = (field, value) => `?filters=${encodeURIComponent(JSON.stringify([[field, '=', value]]))}`;

assert.equal((await post(CUSTOMERS, {}, { 'content-type': 'application/json' })).status, 401);

assert.deepEqual((await (await get(CUSTOMERS + byField('custom_sf_account_id', acc))).json()).data, []);
assert.equal((await post(CUSTOMERS, { customer_name: `Acme ${run}`, custom_sf_account_id: acc })).status, 200);
assert.equal((await post(CUSTOMERS, { customer_name: `Acme ${run}`, custom_sf_account_id: acc })).status, 409);
assert.equal((await (await get(CUSTOMERS + byField('custom_sf_account_id', acc))).json()).data.length, 1);

const created = await post(ORDERS, order());
assert.equal(created.status, 200);
const { data } = await created.json();
assert.equal(data.status, 'To Deliver and Bill');
assert.equal(data.grand_total, 190);

assert.equal((await post(ORDERS, order())).status, 409);
assert.equal((await (await get(ORDERS + byField('custom_sf_opportunity_id', opp))).json()).data[0].name, data.name);
assert.equal((await get(`${ORDERS}/${encodeURIComponent(data.name)}`)).status, 200);
assert.equal((await get(`${ORDERS}/NOPE`)).status, 404);

assert.equal((await post(ORDERS, order({ custom_sf_opportunity_id: `${opp}b`, items: [{ item_code: 'NOPE', qty: 1, rate: 1 }] }))).status, 417);
assert.equal((await post(ORDERS, order({ custom_sf_opportunity_id: `${opp}c`, items: [] }))).status, 417);
assert.equal((await post(ORDERS, order({ custom_sf_opportunity_id: `${opp}d`, delivery_date: '2026-10-01' }))).status, 417);
assert.equal((await post(ORDERS, order({ custom_sf_opportunity_id: `${opp}e`, customer: 'Nobody' }))).status, 417);

await post('/__admin/fail?count=2', {});
assert.equal((await get(CUSTOMERS)).status, 503);
assert.equal((await get(CUSTOMERS)).status, 503);
assert.equal((await get(CUSTOMERS)).status, 200);

console.log('All mock ERP checks passed');
