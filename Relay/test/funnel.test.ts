import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {randomBytes, createHash} from 'node:crypto';
import {WebSocket, WebSocketServer} from 'ws';
import {createLiveCueProxy} from '../funnel/livecue-proxy.mjs';
import {createLiveCueServer} from '../src/server.ts';

test('Funnel native bearer isolation, allowlist, bounded bodies, HTTP and binary WebSocket', async () => {
  const token = randomBytes(32).toString('base64url');
  let hash = createHash('sha256').update(token).digest('hex');
  let hits = 0, headers: http.IncomingHttpHeaders = {};
  const valid = req => createHash('sha256').update((req.headers.authorization || '').slice(7)).digest('hex') === hash;
  const upstream = http.createServer((req, res) => {
    if (!valid(req)) { res.writeHead(401); res.end(); return; }
    hits++; headers = req.headers; req.resume(); req.on('end', () => { res.setHeader('Set-Cookie', 'should-not-leak=test'); res.end('{"ok":true}'); });
  });
  const hub = new WebSocketServer({server: upstream, verifyClient: ({req}) => valid(req)});
  hub.on('connection', (ws, req) => { headers = req.headers; ws.on('message', (data, binary) => ws.send(data, {binary})); });
  upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
  const proxy = createLiveCueProxy({port: (upstream.address() as any).port});
  const gateway = http.createServer((req, res) => { if (!proxy.request(req, res)) { res.writeHead(404); res.end(); } });
  gateway.on('upgrade', (req, socket, head) => { if (!proxy.upgrade(req, socket, head)) socket.destroy(); });
  gateway.listen(0, '127.0.0.1'); await once(gateway, 'listening');
  const base = `http://127.0.0.1:${(gateway.address() as any).port}`;
  const authorization = `Bearer ${token}`;
  try {
    for (const h of [{}, {cookie: '__Host-local_chat_session=not-livecue'}, {authorization:'Bearer '+ 'x'.repeat(43)}, {authorization, origin:'https://example.test'}, {authorization,'sec-fetch-site':'same-origin'}]) {
      assert.equal((await fetch(base+'/v1/health', {headers:h})).status, 401);
    }
    assert.equal(hits, 0);
    for (const route of ['/v1/admin','/v1/health?token=x','/v1/%68ealth','/v1/speech']) {
      assert.equal((await fetch(base+route,{headers:{authorization}})).status,404);
    }
    const result = await fetch(base+'/v1/health', {headers:{authorization,cookie:'private-cookie=secret','x-hermes-session-token':'private'}});
    assert.equal(result.status,200); assert.equal(result.headers.get('set-cookie'), null);
    assert.deepEqual(await result.json(),{ok:true}); assert.equal(headers.cookie,undefined); assert.equal(headers['x-hermes-session-token'],undefined);
    assert.equal((await fetch(base+'/v1/pair/verify',{method:'POST',headers:{authorization},body:'{}'})).status,200);
    assert.equal((await fetch(base+'/v1/assist',{method:'POST',headers:{authorization},body:'x'.repeat(128*1024+1)})).status,413);
    const ws = new WebSocket(base.replace('http:','ws:')+'/v1/speech',{headers:{authorization,'x-livecue-speech-model':'qwen3'}});
    await once(ws,'open');
    assert.equal(headers['x-livecue-speech-model'], 'qwen3');
    const received = once(ws,'message'); const pcm = Buffer.from([0,1,2,3,255,128]); ws.send(pcm);
    const [payload,binary] = await received; assert.equal(binary,true); assert.deepEqual(payload,pcm);
    const textMessage = once(ws,'message'); ws.send('{"type":"endStream"}'); assert.equal((await textMessage)[0].toString(),'{"type":"endStream"}');
    ws.close(); await once(ws,'close');
    hash = createHash('sha256').update('rotated').digest('hex');
    assert.equal((await fetch(base+'/v1/health',{headers:{authorization}})).status,401);
    const badWs = new WebSocket(base.replace('http:','ws:')+'/v1/speech',{headers:{authorization}});
    const denied = new Promise<number>(resolve => badWs.on('unexpected-response', (_req,res) => { res.resume(); badWs.terminate(); resolve(res.statusCode!); }));
    badWs.on('error',()=>{}); assert.equal(await denied,401);
  } finally {
    proxy.close(); for (const ws of hub.clients) ws.terminate(); hub.close();
    gateway.closeAllConnections(); upstream.closeAllConnections();
    await Promise.all([new Promise<void>(r=>gateway.close(()=>r())),new Promise<void>(r=>upstream.close(()=>r()))]);
  }
});

test('Funnel uses the real relay pairing authority, fails closed and respects rotation', async () => {
  const token = randomBytes(32).toString('base64url');
  const next = randomBytes(32).toString('base64url');
  const digest = value => createHash('sha256').update(value).digest('hex');
  let currentHash = digest(token), assistantCalls = 0, seen = 0;
  const relay = createLiveCueServer(() => currentHash, {
    run: async () => { assistantCalls++; throw Error('Must not run'); }, cancel: () => false
  } as any, {emit: event => { if (event.type === 'phone-seen') seen++; }});
  relay.listen(0, '127.0.0.1'); await once(relay, 'listening');
  const proxy = createLiveCueProxy({port: (relay.address() as any).port});
  const gateway = http.createServer((req, res) => { if (!proxy.request(req, res)) { res.writeHead(404); res.end(); } });
  gateway.on('upgrade', (req, socket, head) => { if (!proxy.upgrade(req, socket, head)) socket.destroy(); });
  gateway.listen(0, '127.0.0.1'); await once(gateway, 'listening');
  const base = `http://127.0.0.1:${(gateway.address() as any).port}`;
  const request = (token, route = '/v1/health', method = 'GET') => fetch(base + route, {
    method, headers: {authorization: `Bearer ${token}`}, ...(method === 'POST' ? {body: '{}'} : {})
  });
  try {
    assert.equal((await request(next)).status, 401);
    assert.equal((await request(next, '/v1/assist', 'POST')).status, 401);
    assert.equal(seen, 0); assert.equal(assistantCalls, 0);
    assert.equal((await request(token)).status, 200);
    assert.equal((await request(token, '/v1/pair/verify', 'POST')).status, 200);
    currentHash = digest(next);
    assert.equal((await request(token)).status, 401);
    assert.equal((await request(next)).status, 200);
    const ws = new WebSocket(base.replace('http:', 'ws:') + '/v1/speech', {headers: {authorization: `Bearer ${token}`}});
    const denied = new Promise<number>(resolve => ws.on('unexpected-response', (_req, res) => { res.resume(); ws.terminate(); resolve(res.statusCode!); }));
    ws.on('error', () => {}); assert.equal(await denied, 401);
    assert.equal(assistantCalls, 0);
    relay.closeAllConnections(); await new Promise<void>(resolve => relay.close(() => resolve()));
    assert.equal((await request(next)).status, 502);
  } finally {
    proxy.close(); gateway.closeAllConnections(); relay.closeAllConnections();
    await Promise.all([new Promise<void>(r => gateway.close(() => r())), new Promise<void>(r => relay.close(() => r()))]);
  }
});
