import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { LocalModelController, type Runtime } from "../src/local-model.ts";
import { createLiveCueServer } from "../src/server.ts";
import { hashToken } from "../src/security.ts";
import { createLiveCueProxy } from "../funnel/livecue-proxy.mjs";
import { WebSocket, WebSocketServer } from "ws";

const wait = async (controller: LocalModelController) => { for (let i = 0; i < 100 && controller.changing; i++) await new Promise(r => setTimeout(r, 5)); assert.equal(controller.changing, false); };
test("PC controller starts, preserves loading lock, switches and stops without exposing diagnostics", async () => {
  let loaded: string | undefined, starts = 0, stops = 0, release!: () => void;
  let pending = new Promise<void>(r => { release = r; });
  const controller = new LocalModelController({
    health: async () => ({ ready: Boolean(loaded), model: loaded, relayProtocol: 1 }),
    start: async model => { starts++; await pending; loaded = model; }, stop: async () => { stops++; loaded = undefined; }
  });
  assert.equal((await controller.status()).state, "stopped");
  assert.equal(controller.start("nemotron").state, "starting");
  assert.throws(() => controller.start("qwen3"), /already in progress/);
  assert.throws(() => controller.stop("nemotron"), /already in progress/);
  await new Promise(r => setTimeout(r, 5)); assert.equal((await controller.status()).state, "starting");
  release(); await wait(controller); assert.equal((await controller.status()).model, "nemotron");
  await controller.prepare("nemotron"); assert.equal(starts, 1);
  pending = Promise.resolve(); controller.start("qwen3"); await wait(controller);
  assert.equal((await controller.status()).model, "qwen3");
  controller.stop("qwen3"); await wait(controller); assert.equal(stops, 1); assert.equal((await controller.status()).state, "stopped");
  const failed = new LocalModelController({ health: async () => { throw Error(); }, start: async () => { throw Error("PRIVATE API SECRET"); }, stop: async () => {} });
  failed.start("nemotron"); await wait(failed); const status = await failed.status();
  assert.equal(status.state, "error"); assert.equal(status.message.includes("PRIVATE"), false);
  assert.throws(() => failed.start("../evil" as any), /Choose/);
});

test("paired native model controls work through Funnel, reject browser/unpaired and protect active speech", async () => {
  const token = randomBytes(32).toString("base64url"); let loaded: string | undefined, active = false, launches = 0, stops = 0;
  const runtime: Runtime = { health: async () => ({ ready: Boolean(loaded), model: loaded, busy: active, relayProtocol: 1 }),
    start: async model => { launches++; loaded = model; }, stop: async () => { stops++; loaded = undefined; } };
  const models = new LocalModelController(runtime);
  const upstream = new WebSocketServer({ port: 0, host: "127.0.0.1" }); await once(upstream, "listening");
  upstream.on("connection", ws => ws.send(JSON.stringify({type: "ready", model: "nemotron", sampleRate: 16000})));
  const relay = createLiveCueServer(hashToken(token), undefined, {}, models, () => new WebSocket(`ws://127.0.0.1:${(upstream.address() as any).port}`));
  relay.listen(0, "127.0.0.1"); await once(relay, "listening");
  const proxy = createLiveCueProxy({ port: (relay.address() as any).port });
  const gateway = createServer((req, res) => { if (!proxy.request(req, res)) res.end(); });
  gateway.on("upgrade", (req, socket, head) => proxy.upgrade(req, socket, head));
  gateway.listen(0, "127.0.0.1"); await once(gateway, "listening");
  const base = `http://127.0.0.1:${(gateway.address() as any).port}`;
  const call = (path: string, model?: string, auth = token, extra = {}) => fetch(base + path, { method: model ? "POST" : "GET", headers: { authorization: "Bearer " + auth, ...extra }, ...(model ? {body: JSON.stringify({model})} : {}) });
  try {
    assert.equal((await call("/v1/local-model/start", "nemotron", "x".repeat(43))).status, 401);
    assert.equal((await call("/v1/local-model/start", "nemotron", token, {origin: "https://bad.test"})).status, 401);
    assert.equal((await call("/v1/local-model/start", "../shell")).status, 400);
    assert.equal(launches, 0);
    assert.equal((await call("/v1/local-model/start", "nemotron")).status, 202); await wait(models);
    assert.equal((await (await call("/v1/local-model")).json()).state, "ready");
    active = true;
    assert.equal((await call("/v1/local-model/stop", "nemotron")).status, 409);
    assert.equal((await call("/v1/local-model/start", "qwen3")).status, 409); assert.equal(stops, 0);
    active = false;
    assert.equal((await call("/v1/local-model/stop", "qwen3")).status, 409);
    // A live socket owns the speech lease even before the lab reports busy.
    const phone = new WebSocket(base.replace("http:", "ws:") + "/v1/speech", { headers: {authorization: "Bearer " + token, "X-LiveCue-Speech-Model": "nemotron"} });
    await new Promise<void>(resolve => phone.on("message", data => { if (JSON.parse(data.toString()).type === "ready") resolve(); }));
    assert.equal((await call("/v1/local-model/stop", "nemotron")).status, 409);
    phone.close(); await once(phone, "close"); await new Promise(r => setTimeout(r, 10));
    assert.equal((await call("/v1/local-model/stop", "nemotron")).status, 202); await wait(models);
    assert.equal((await (await call("/v1/local-model")).json()).state, "stopped"); assert.equal(stops, 1);
  } finally { proxy.close(); for (const ws of upstream.clients) ws.terminate(); upstream.close(); gateway.closeAllConnections(); relay.closeAllConnections(); await Promise.all([new Promise<void>(r => gateway.close(() => r())), new Promise<void>(r => relay.close(() => r()))]); }
});
