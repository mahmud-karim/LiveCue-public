import assert from "node:assert/strict";
import test from "node:test";
import { once } from "node:events";
import { modelCatalog, validateSelection } from "../src/models.ts";
import { createLiveCueServer } from "../src/server.ts";
import { hashToken } from "../src/security.ts";

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
