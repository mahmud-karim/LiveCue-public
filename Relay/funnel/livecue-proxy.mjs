import http from 'node:http';
import {createHash, timingSafeEqual} from 'node:crypto';

// Native LiveCue credentials are separate from the gateway's browser cookies.
// No provider key, upstream URL, admin API, or file route is exposed here.
export function createLiveCueProxy({tokenHash, port = 47831}) {
  const sockets = new Set();
  let requests = 0, streams = 0;
  const claimed = req => String(req.url || '').startsWith('/v1/');
  const authorized = req => {
    if (req.headers.origin || req.headers['sec-fetch-site']) return false;
    const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.authorization || '');
    if (!match) return false;
    try {
      const expected = tokenHash();
      if (!/^[a-f0-9]{64}$/.test(expected || '')) return false;
      return timingSafeEqual(createHash('sha256').update(match[1]).digest(), Buffer.from(expected, 'hex'));
    } catch { return false; }
  };
  const reply = (res, code) => {
    if (res.headersSent) return res.destroy();
    res.writeHead(code, {'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'});
    res.end(JSON.stringify({error: code === 401 ? 'Invalid LiveCue pairing token.' : 'LiveCue request unavailable.'}));
  };
  const reject = (socket, code) => socket.end(`HTTP/1.1 ${code} Rejected\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
  return {
    request(req, res) {
      if (!claimed(req)) return false;
      if (!authorized(req)) { reply(res, 401); return true; }
      const allowed = (req.method === 'GET' && ['/v1/health', '/v1/models'].includes(req.url)) ||
        (req.method === 'POST' && ['/v1/pair/verify', '/v1/assist', '/v1/session-summary'].includes(req.url)) ||
        (req.method === 'DELETE' && /^\/v1\/requests\/[A-Za-z0-9_-]{1,80}$/.test(req.url));
      if (!allowed) { reply(res, 404); return true; }
      if (Number(req.headers['content-length'] || 0) > 128 * 1024) { reply(res, 413); return true; }
      if (requests >= 16) { reply(res, 429); return true; }
      requests++;
      const client = res.socket;
      sockets.add(client);
      const upstream = http.request({hostname: '127.0.0.1', port, path: req.url, method: req.method,
        headers: {authorization: req.headers.authorization, 'content-type': 'application/json'}}, response => {
        res.writeHead(response.statusCode, {'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'});
        response.pipe(res);
      });
      let bytes = 0;
      const deadline = setTimeout(() => { upstream.destroy(); reply(res, 504); }, 70_000);
      deadline.unref();
      req.on('data', chunk => {
        bytes += chunk.length;
        if (bytes > 128 * 1024) { req.unpipe(upstream); upstream.destroy(); reply(res, 413); }
      });
      upstream.on('error', () => { if (!res.writableEnded) reply(res, 502); });
      req.on('aborted', () => upstream.destroy());
      req.on('error', () => upstream.destroy());
      res.once('close', () => { clearTimeout(deadline); requests--; sockets.delete(client); upstream.destroy(); });
      req.pipe(upstream);
      return true;
    },
    upgrade(req, socket, head) {
      if (!claimed(req)) return false;
      if (!authorized(req)) { reject(socket, 401); return true; }
      if (req.url !== '/v1/speech' || req.method !== 'GET' || req.headers.upgrade?.toLowerCase() !== 'websocket') {
        reject(socket, 404); return true;
      }
      if (streams >= 2) { reject(socket, 429); return true; }
      streams++; sockets.add(socket);
      let peer;
      const upstream = http.request({hostname: '127.0.0.1', port, path: '/v1/speech', headers: {
        authorization: req.headers.authorization, connection: 'Upgrade', upgrade: 'websocket',
        'sec-websocket-key': req.headers['sec-websocket-key'] || '',
        'sec-websocket-version': req.headers['sec-websocket-version'] || ''
      }});
      const handshake = setTimeout(() => { upstream.destroy(); reject(socket, 504); }, 15_000);
      const lifetime = setTimeout(() => socket.destroy(), 31 * 60_000);
      handshake.unref(); lifetime.unref();
      socket.setTimeout(30_000, () => socket.destroy());
      socket.on('error', () => socket.destroy());
      socket.once('close', () => { streams--; sockets.delete(socket); clearTimeout(handshake); clearTimeout(lifetime); upstream.destroy(); peer?.destroy(); });
      upstream.on('upgrade', (response, duplex, upstreamHead) => {
        clearTimeout(handshake); peer = duplex;
        if (socket.destroyed) return duplex.destroy();
        socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + response.headers['sec-websocket-accept'] + '\r\n\r\n');
        if (upstreamHead.length) socket.write(upstreamHead);
        if (head.length) duplex.write(head);
        duplex.on('error', () => socket.destroy());
        duplex.on('close', () => socket.destroy());
        socket.pipe(duplex); duplex.pipe(socket);
      });
      upstream.on('response', response => { clearTimeout(handshake); response.resume(); reject(socket, response.statusCode || 502); });
      upstream.on('error', () => { clearTimeout(handshake); if (!socket.destroyed) reject(socket, 502); });
      upstream.end();
      return true;
    },
    close() { for (const socket of sockets) socket.destroy(); sockets.clear(); }
  };
}
