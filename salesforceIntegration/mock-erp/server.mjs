// Mock ERP. Stands in for ERPNext: same URLs, token auth, { data } envelope and status codes.
// Data is in memory and resets on restart. Usage: node mock-erp/server.mjs
import { createServer } from 'node:http';

const PORT = process.env.PORT ?? 8090;
const TOKEN = `token ${process.env.ERP_API_KEY ?? 'mock-key'}:${process.env.ERP_API_SECRET ?? 'mock-secret'}`;
const ITEMS = ['WIDGET-100', 'WIDGET-200', 'SUPPORT-1Y'];

const customers = new Map();
const orders = new Map();
let failNext = 0;

const error = (status, excType, message) => ({ status, body: { exc_type: excType, message } });

// Applies ERPNext-style filters: [["field", "=", "value"]]
function list(store, url) {
  const filters = JSON.parse(url.searchParams.get('filters') ?? '[]');
  const data = [...store.values()].filter((doc) => filters.every(([field, , value]) => doc[field] === value));
  return { status: 200, body: { data } };
}

function createCustomer(body) {
  if (!body.customer_name) return error(417, 'MandatoryError', 'customer_name is required');
  const taken = [...customers.values()].some((c) => c.custom_sf_account_id === body.custom_sf_account_id);
  if (taken) return error(409, 'DuplicateEntryError', `SF Account ${body.custom_sf_account_id} already exists`);
  let name = body.customer_name;
  for (let n = 1; customers.has(name); n++) name = `${body.customer_name} - ${n}`;
  const doc = { ...body, name };
  customers.set(name, doc);
  return { status: 200, body: { data: doc } };
}

function createOrder(body) {
  const taken = [...orders.values()].some((o) => o.custom_sf_opportunity_id === body.custom_sf_opportunity_id);
  if (taken) return error(409, 'DuplicateEntryError', `SF Opportunity ${body.custom_sf_opportunity_id} already has an order`);
  if (!customers.has(body.customer)) return error(417, 'LinkValidationError', `Could not find Customer: ${body.customer}`);
  if (!body.items?.length) return error(417, 'MandatoryError', 'items are required');
  const unknown = body.items.find((i) => !ITEMS.includes(i.item_code));
  if (unknown) return error(417, 'LinkValidationError', `Could not find Item Code: ${unknown.item_code}`);
  if (body.delivery_date < body.transaction_date) return error(417, 'ValidationError', 'Expected Delivery Date should be after Sales Order Date');
  const name = `SAL-ORD-${new Date().getFullYear()}-${String(orders.size + 1).padStart(5, '0')}`;
  const grand_total = body.items.reduce((sum, i) => sum + i.qty * i.rate, 0);
  const doc = { ...body, name, docstatus: 1, status: 'To Deliver and Bill', grand_total };
  orders.set(name, doc);
  return { status: 200, body: { data: doc } };
}

function route(method, url, headers, body) {
  // Demo control: POST /__admin/fail?count=2 makes the next 2 ERP calls return 503.
  if (method === 'POST' && url.pathname === '/__admin/fail') {
    // Cloudflare adds this header, so the switch only works from this machine, not through the tunnel.
    if (headers['cf-connecting-ip']) return error(403, 'PermissionError', 'Local use only');
    failNext = Number(url.searchParams.get('count') ?? 1);
    return { status: 200, body: { failNext } };
  }
  if (headers.authorization !== TOKEN) return error(401, 'AuthenticationError', 'Invalid API key');
  if (failNext > 0) {
    failNext--;
    return error(503, 'ServiceUnavailable', 'Mock ERP: simulated outage');
  }
  const path = decodeURIComponent(url.pathname);
  if (method === 'GET' && path === '/api/resource/Customer') return list(customers, url);
  if (method === 'POST' && path === '/api/resource/Customer') return createCustomer(body);
  if (method === 'GET' && path === '/api/resource/Sales Order') return list(orders, url);
  if (method === 'POST' && path === '/api/resource/Sales Order') return createOrder(body);
  const match = path.match(/^\/api\/resource\/Sales Order\/(.+)$/);
  if (method === 'GET' && match) {
    const doc = orders.get(match[1]);
    return doc ? { status: 200, body: { data: doc } } : error(404, 'DoesNotExistError', `Sales Order ${match[1]} not found`);
  }
  return error(404, 'NotFound', `${method} ${path} is not supported`);
}

createServer((req, res) => {
  let raw = '';
  req.on('data', (chunk) => { raw += chunk; });
  req.on('end', () => {
    let result;
    try {
      result = route(req.method, new URL(req.url, 'http://localhost'), req.headers, raw ? JSON.parse(raw) : {});
    } catch {
      result = error(400, 'BadRequest', 'Request is not valid JSON');
    }
    const via = req.headers['cf-connecting-ip'] ? ' (via tunnel)' : '';
    console.log(`${new Date().toISOString()} ${req.method} ${decodeURIComponent(req.url)} -> ${result.status}${via}`);
    res.writeHead(result.status, { 'content-type': 'application/json' });
    res.end(JSON.stringify(result.body));
  });
}).listen(PORT, () => console.log(`Mock ERP on http://localhost:${PORT}`));
