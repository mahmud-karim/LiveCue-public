import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import { createLiveCueServer } from "../src/server.ts";
import { hashToken, verifyToken } from "../src/security.ts";

test("desktop feed reports input and reply without exposing control routes", async () => {
  const events: Record<string, unknown>[] = [];
  let token = hashToken("desktop-test-token"); let accepting = true;
  const runner = { active: new Map(), run: async () => ({ answer: "Fixture reply" }), cancel: () => false };
  const server = createLiveCueServer(() => token, runner as never, { emit: event => events.push(event), accepting: () => accepting });
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  try {
    const address = server.address(); assert.ok(address && typeof address !== "string");
    const base = `http://127.0.0.1:${address.port}`;
    const headers = { Authorization: "Bearer desktop-test-token" };
    assert.equal((await fetch(base + "/v1/assist", { method: "POST", headers, body: JSON.stringify({ requestId: "fixture", transcript: "Fixture question" }) })).status, 200);
    assert.ok(events.some(e => e.type === "request" && (e.payload as { transcript: string }).transcript === "Fixture question"));
    assert.ok(events.some(e => e.type === "reply"));
    assert.equal(JSON.stringify(events).includes("desktop-test-token"), false);
    assert.equal((await fetch(base + "/desktop/pair", { method: "POST", headers })).status, 404);
    accepting = false;
    assert.equal((await fetch(base + "/v1/assist", { method: "POST", headers, body: "{}" })).status, 503);
    accepting = true; token = hashToken("rotated-token");
    assert.equal((await fetch(base + "/v1/health", { headers })).status, 401);
    assert.equal((await fetch(base + "/v1/health", { headers: { Authorization: "Bearer rotated-token" } })).status, 200);
  } finally { server.close(); }
});

test("token hashing and constant-time verification", () => {
  const hash = hashToken("secret");
  assert.equal(verifyToken("secret", hash), true);
  assert.equal(verifyToken("wrong", hash), false);
  assert.equal(hash.includes("secret"), false);
});

test("relay authenticates and returns structured assist data", async () => {
  const runner = {
    active: new Map(),
    run: async () => ({ detectedQuestion: "Question?", answer: "Answer.", details: "Detail.", memory: { summary: "Memory", facts: [], openQuestions: [], throughSegmentId: null } }),
    cancel: () => false
  };
  const server = createLiveCueServer(hashToken("test-token"), runner as never);
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  const address = server.address(); assert.ok(address && typeof address !== "string");
  const url = `http://127.0.0.1:${address.port}/v1/assist`;
  const denied = await fetch(url, { method: "POST", body: "{}" });
  assert.equal(denied.status, 401);
  const response = await fetch(url, { method: "POST", headers: { Authorization: "Bearer test-token", "Content-Type": "application/json" }, body: JSON.stringify({ requestId: "r1" }) });
  assert.equal(response.status, 200);
  assert.equal((await response.json() as { answer: string }).answer, "Answer.");
  server.close();
});

test("relay rejects payloads over 128 KB", async () => {
  const runner = { active: new Map(), run: async () => ({}), cancel: () => false };
  const server = createLiveCueServer(hashToken("token"), runner as never);
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  const address = server.address(); assert.ok(address && typeof address !== "string");
  const response = await fetch(`http://127.0.0.1:${address.port}/v1/assist`, { method: "POST", headers: { Authorization: "Bearer token" }, body: JSON.stringify({ requestId: "r", transcript: "x".repeat(140_000) }) });
  assert.equal(response.status, 413);
  server.close();
});
