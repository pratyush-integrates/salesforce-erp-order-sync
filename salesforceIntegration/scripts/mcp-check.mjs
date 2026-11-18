// Calls the MCP server the way a client does: initialize, list the tools, then call each one.
// Usage: node scripts/mcp-check.mjs [opportunityId]
const URL_MCP = process.env.MCP_URL ?? 'http://127.0.0.1:8085/mcp';
const oppId = process.argv[2] ?? '006000000000000AAA';
let session;
let nextId = 1;

async function rpc(method, params, notification = false) {
  const headers = { 'content-type': 'application/json', accept: 'application/json, text/event-stream' };
  if (session) headers['mcp-session-id'] = session;
  const body = { jsonrpc: '2.0', method, params, ...(notification ? {} : { id: nextId++ }) };
  const res = await fetch(URL_MCP, { method: 'POST', headers, body: JSON.stringify(body) });
  session = res.headers.get('mcp-session-id') ?? session;
  if (notification) return null;
  if (!res.ok) throw new Error(`${method}: HTTP ${res.status} ${await res.text()}`);
  if (!res.headers.get('content-type')?.includes('event-stream')) return res.json();
  // The server answers on a stream that stays open, so stop at the reply instead of waiting for the end.
  let buffer = '';
  const decoder = new TextDecoder();
  for await (const chunk of res.body) {
    buffer += decoder.decode(chunk, { stream: true });
    const line = buffer.split(/\r?\n/).find((l) => l.startsWith('data:') && l.includes(`"id":${body.id}`));
    if (line && buffer.includes('\n\n')) return JSON.parse(line.slice(5).trim());
  }
  throw new Error(`${method}: the stream ended with no reply`);
}

const init = await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'mcp-check', version: '1.0.0' } });
console.log('server:', JSON.stringify(init.result?.serverInfo ?? init.error));
await rpc('notifications/initialized', {}, true);

const tools = await rpc('tools/list', {});
console.log('tools:', tools.result.tools.map((t) => t.name).join(', '));

const today = new Date().toISOString().slice(0, 10) + 'T00:00:00Z';
const failed = await rpc('tools/call', { name: 'list_failed_orders', arguments: { since: today } });
console.log('list_failed_orders isError:', failed.result?.isError ?? false, '\n ', failed.result?.content?.[0]?.text?.slice(0, 400) ?? JSON.stringify(failed));

const status = await rpc('tools/call', { name: 'get_order_status', arguments: { opportunityId: oppId } });
console.log('get_order_status isError:', status.result?.isError ?? false, '\n ', status.result?.content?.[0]?.text?.slice(0, 400) ?? JSON.stringify(status));

const bad = await rpc('tools/call', { name: 'get_order_status', arguments: { opportunityId: '../../admin' } });
console.log('get_order_status with a bad ID, isError:', bad.result?.isError ?? !!bad.error, '\n ', bad.result?.content?.[0]?.text?.slice(0, 200) ?? JSON.stringify(bad.error));
