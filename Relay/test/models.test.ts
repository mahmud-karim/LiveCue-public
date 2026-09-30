import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import { modelCatalog, ModelCatalogReader, CatalogUnavailableError, supportedEfforts, validateSelection } from "../src/models.ts";
import { createLiveCueServer } from "../src/server.ts";
import { hashToken } from "../src/security.ts";

const lunaCache = JSON.stringify({ models: [{ slug: "gpt-6-luna", visibility: "list", supported_reasoning_levels: [{ effort: "low" }] }] });
test("temporary cache read failures keep Luna Low, but a valid removal takes effect", async () => {
  let cache = lunaCache;
  const reader = new ModelCatalogReader(async () => cache);
  const offered = await reader.read();
  cache = "{";
  assert.deepEqual(await reader.read(), offered);
  assert.deepEqual(validateSelection({model: "gpt-6-luna", reasoningEffort: "low"}, await reader.read()), {model: "gpt-6-luna", reasoningEffort: "low"});
  offered[0].reasoningEfforts.length = 0;
  assert.deepEqual((await reader.read())[0].reasoningEfforts, ["low"]);
  cache = JSON.stringify({models: []});
  assert.deepEqual(await reader.read(), []);
  assert.throws(() => validateSelection({model: "gpt-6-luna", reasoningEffort: "low"}, []));
});
test("first-run catalog failure does not invent a 5.6-only fallback; partial writes retry", async () => {
  await assert.rejects(new ModelCatalogReader(async () => "{").read(), CatalogUnavailableError);
  let reads = 0;
  const reader = new ModelCatalogReader(async () => ++reads === 1 ? "{" : lunaCache);
  assert.equal((await reader.read())[0].id, "gpt-6-luna");
  assert.equal(reads, 2);
});
test("catalog outage is 503, not a model rejection, and does not run Codex", async () => {
  let calls = 0;
  const runner = { active: new Map(), run: async () => { calls++; }, cancel: () => false };
  const server = createLiveCueServer(hashToken("fixture"), runner as never, {}, undefined, undefined, async () => { throw new CatalogUnavailableError(); });
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  try {
    const address = server.address(); assert.ok(address && typeof address !== "string");
    for (const path of ["/v1/models", "/v1/assist"]) {
      const response = await fetch(`http://127.0.0.1:${address.port}` + path, { method: path.endsWith("assist") ? "POST" : "GET", headers: {Authorization:"Bearer fixture"}, ...(path.endsWith("assist") ? {body: JSON.stringify({requestId:"fixture", assistant:{model:"gpt-6-luna",reasoningEffort:"low"}})} : {}) });
      assert.equal(response.status, 503);
      assert.equal((await response.json() as any).code, "ASSISTANT_CATALOG_UNAVAILABLE");
    }
    assert.equal(calls, 0);
  } finally { server.close(); }
});

test("verified no-reasoning models are exposed without enabling it for Astra or Spark", () => {
  for (const model of ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]) {
    assert.deepEqual(supportedEfforts(model, ["low", "high", "ultra"]), ["none", "low", "high"]);
  }
  for (const model of ["gpt-6-astra", "gpt-5.3-codex-spark"]) {
    assert.deepEqual(supportedEfforts(model, ["low", "medium", "ultra"]), ["low", "medium"]);
  }
});

test("selection rejects model/config injection and invalid reasoning combinations", () => {
  const catalog = [{ id: "gpt-test", name: "Test", reasoningEfforts: ["low"] }];
  assert.deepEqual(validateSelection({ model: "gpt-test", reasoningEffort: "low" }, catalog), { model: "gpt-test", reasoningEffort: "low" });
  for (const bad of [null, [], "model", {model:"--config", reasoningEffort:"low"}, {model:"gpt-test", reasoningEffort:'low";shell=true'}]) {
    assert.throws(() => validateSelection(bad, catalog));
  }
});

test("authenticated model catalog, selection forwarding and non-overlapping relay timings", async () => {
  let received: unknown;
  const runner = { active: new Map(), run: async (_id: string, _kind: string, _body: unknown, _timeout: number, selection: unknown) => {
    received = selection; return { answer: "Fixture" };
  }, cancel: () => false };
  const server = createLiveCueServer(hashToken("fixture"), runner as never);
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  try {
    const address = server.address(); assert.ok(address && typeof address !== "string");
    const base = `http://127.0.0.1:${address.port}`;
    assert.equal((await fetch(base + "/v1/models")).status, 401);
    const headers = {Authorization:"Bearer fixture"};
    const catalog = await (await fetch(base + "/v1/models", {headers})).json() as {models: Awaited<ReturnType<typeof modelCatalog>>};
    const option = catalog.models[0];
    const assistant = {model:option.id,reasoningEffort:option.reasoningEfforts[0]};
    const response = await fetch(base + "/v1/assist", {method:"POST",headers,body:JSON.stringify({requestId:"timing",assistant,transcript:"Hello"})});
    assert.equal(response.status,200);
    const result = await response.json() as any;
    assert.deepEqual(received,assistant);
    assert.equal(result.execution.model, assistant.model);
    assert.ok(result.execution.codexMs >= 0);
    assert.ok(result.execution.relayTotalMs >= result.execution.codexMs);
    assert.ok(Math.abs(result.execution.relayTotalMs - result.execution.codexMs - result.execution.relayOverheadMs) < 0.01);
    const invalid = await fetch(base + "/v1/assist", {method:"POST",headers,body:JSON.stringify({requestId:"invalid",assistant:{model:"not-a-model",reasoningEffort:"low"}})});
    assert.equal(invalid.status,400);
  } finally { server.close(); }
});
