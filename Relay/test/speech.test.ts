import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { once } from "node:events";
import { WebSocket, WebSocketServer } from "ws";
import { attachSpeech } from "../src/speech.ts";
import { hashToken } from "../src/security.ts";

test("both PC models work without a Meta key and never contact Meta", async () => {
  for (const model of ["nemotron", "qwen3"]) {
    const service = new WebSocketServer({ port: 0, host: "127.0.0.1" }); await once(service, "listening");
    let audio = 0;
    service.on("connection", ws => {
      ws.send(JSON.stringify({ type: "ready", model, sampleRate: 16000 }));
      ws.on("message", (data, binary) => {
        if (binary) { audio += data.length; ws.send(JSON.stringify({ type: "transcript", transcript: "Local words", private: "hidden" })); }
        else { ws.send(JSON.stringify({ type: "speechComplete", transcript: "Local words", turnId: 1, audioProcessedMs: 80 })); ws.send(JSON.stringify({ type: "streamComplete", audioProcessedMs: 80 })); }
      });
    });
    const server = createServer(); let prepared = "", metaCalls = 0;
    attachSpeech(server, hashToken("paired"), {}, () => { metaCalls++; throw Error(); }, "", {
      prepare: async kind => { prepared = kind; },
      connect: () => new WebSocket(`ws://127.0.0.1:${(service.address() as any).port}`)
    });
    server.listen(0, "127.0.0.1"); await once(server, "listening");
    const phone = new WebSocket(`ws://127.0.0.1:${(server.address() as any).port}/v1/speech`, { headers: { Authorization: "Bearer paired", "X-LiveCue-Speech-Model": model } });
    const frames: any[] = [];
    phone.on("message", data => {
      const event = JSON.parse(data.toString()); frames.push(event);
      if (event.type === "ready") { assert.equal(event.provider, model); assert.equal(event.sampleRate, 16000); phone.send(Buffer.alloc(2560)); }
      if (event.type === "transcript") phone.send(JSON.stringify({ type: "endStream" }));
    });
    await once(phone, "close");
    assert.equal(prepared, model); assert.equal(metaCalls, 0); assert.equal(audio, 2560);
    assert.ok(frames.some(f => f.type === "streamComplete"));
    assert.equal(JSON.stringify(frames).includes("hidden"), false);
    server.close(); service.close();
  }
});

test("unknown speech model is rejected without launching a process", async () => {
  const server = createServer(); let calls = 0;
  attachSpeech(server, hashToken("paired"), {}, () => { calls++; throw Error(); }, "key", {
    prepare: async () => { calls++; }, connect: () => { calls++; throw Error(); }
  });
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  const phone = new WebSocket(`ws://127.0.0.1:${(server.address() as any).port}/v1/speech`, { headers: { Authorization: "Bearer paired", "X-LiveCue-Speech-Model": "../arbitrary" } });
  await once(phone, "error"); assert.equal(calls, 0); server.close();
});

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
