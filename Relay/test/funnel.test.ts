import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {randomBytes, createHash} from 'node:crypto';
import {WebSocket, WebSocketServer} from 'ws';
import {createLiveCueProxy} from '../funnel/livecue-proxy.mjs';

test('Funnel native bearer isolation, allowlist, bounded bodies, HTTP and binary WebSocket', async () => {
  const token = randomBytes(32).toString('base64url');
  let hash = createHash('sha256').update(token).digest('hex');
  let hits = 0, headers: http.IncomingHttpHeaders = {};
  const upstream = http.createServer((req, res) => { hits++; headers = req.headers; req.resume(); req.on('end', () => { res.setHeader('Set-Cookie', 'should-not-leak=test'); res.end('{"ok":true}'); }); });
  const hub = new WebSocketServer({server: upstream});
  hub.on('connection', ws => ws.on('message', (data, binary) => ws.send(data, {binary})));
  upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
  const proxy = createLiveCueProxy({port: (upstream.address() as any).port, tokenHash: () => hash});
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
    const ws = new WebSocket(base.replace('http:','ws:')+'/v1/speech',{headers:{authorization}});
    await once(ws,'open');
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
