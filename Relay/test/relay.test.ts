import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import { createLiveCueServer } from "../src/server.ts";
import { hashToken, verifyToken } from "../src/security.ts";

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

