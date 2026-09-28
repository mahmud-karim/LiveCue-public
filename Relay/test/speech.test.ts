import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { once } from "node:events";
import { WebSocket, WebSocketServer } from "ws";
import { attachSpeech } from "../src/speech.ts";
import { hashToken } from "../src/security.ts";

test("speech rejects unauthenticated, browser, missing-key and paused connections", async () => {
  for (const setup of [{ auth: false }, { origin: true }, { missing: true }, { paused: true }]) {
    const server = createServer(); let calls = 0;
    attachSpeech(server, hashToken("paired"), { accepting: () => !setup.paused }, () => { calls++; throw Error(); }, setup.missing ? "" : "fixture-key");
    server.listen(0, "127.0.0.1"); await once(server, "listening");
    const ws = new WebSocket(`ws://127.0.0.1:${(server.address() as any).port}/v1/speech`, { headers: { ...(setup.auth === false ? {} : { Authorization: "Bearer paired" }), ...(setup.origin ? { Origin: "https://bad.test" } : {}) } });
    await once(ws, "error"); assert.equal(calls, 0); server.close();
  }
});

test("speech forwards PCM and sanitized events, finalizes and closes upstream", async () => {
  const upstreamServer = new WebSocketServer({ port: 0, host: "127.0.0.1" }); await once(upstreamServer, "listening");
  let handshake: any; let audio = 0;
  upstreamServer.on("connection", ws => ws.on("message", (data, binary) => {
    if (binary) { audio += data.length; ws.send(JSON.stringify({ type: "transcript", transcript: "fixture-key words", authorization: "should-not-leak", audioProcessedMs: 80 })); }
    else if (!handshake) { handshake = JSON.parse(data.toString()); ws.send(JSON.stringify({ sessionId: "fixture" })); }
    else { ws.send(JSON.stringify({ type: "speechComplete", turnId: 1, transcript: "Final words", audioProcessedMs: 80 })); ws.close(); }
  }));
  const server = createServer(); const events: any[] = [];
  attachSpeech(server, hashToken("paired"), { emit: e => events.push(e) }, () => new WebSocket(`ws://127.0.0.1:${(upstreamServer.address() as any).port}`), "fixture-key");
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  const phone = new WebSocket(`ws://127.0.0.1:${(server.address() as any).port}/v1/speech`, { headers: { Authorization: "Bearer paired" } });
  const frames: any[] = [];
  phone.on("message", data => {
    const message = JSON.parse(data.toString()); frames.push(message);
    if (message.type === "ready") phone.send(Buffer.alloc(3840));
    if (message.type === "transcript") phone.send(JSON.stringify({ type: "endStream" }));
  });
  await once(phone, "close");
  assert.equal(handshake.authorization.accessToken, "Bearer fixture-key");
  assert.equal(handshake.mode, "ENDPOINTING"); assert.equal(audio, 3840);
  assert.ok(frames.some(f => f.type === "speechComplete"));
  assert.equal(JSON.stringify([...frames, ...events]).includes("fixture-key"), false);
  assert.equal(JSON.stringify(frames).includes("should-not-leak"), false);
  server.close(); upstreamServer.close();
});
