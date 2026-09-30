import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadOrCreatePairing, pairingCode, pairingHashes, hashToken, verifyToken } from "../src/security.ts";
import { createLiveCueServer } from "../src/server.ts";

test("Windows pairing survives reload and repeated QR display; explicit reset revokes it", { timeout: 30000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), "livecue-pairing-persistence-"));
  const file = join(directory, "relay.json");
  try {
    const first = await loadOrCreatePairing(file, false);
    assert.ok(first.plaintextToken);
    const stored = await readFile(file, "utf8");
    assert.equal(stored.includes(first.plaintextToken!), false);
    const restarted = await loadOrCreatePairing(file, false);
    assert.equal(restarted.plaintextToken, first.plaintextToken);
    const shown = await pairingCode(file);
    assert.equal(shown.plaintextToken, first.plaintextToken);
    assert.equal(verifyToken(first.plaintextToken!, pairingHashes(shown.config)), true);
    const reset = await loadOrCreatePairing(file, true);
    assert.equal(verifyToken(first.plaintextToken!, pairingHashes(reset.config)), false);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("Upgrading hash-only pairing keeps the old phone authorized through relay restart", { timeout: 30000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), "livecue-pairing-legacy-"));
  const file = join(directory, "relay.json");
  const oldToken = "synthetic-existing-phone-token";
  let server: ReturnType<typeof createLiveCueServer> | undefined;
  try {
    await writeFile(file, JSON.stringify({ tokenHash: hashToken(oldToken), createdAt: new Date().toISOString() }));
    const upgraded = await pairingCode(file);
    assert.equal(verifyToken(oldToken, pairingHashes(upgraded.config)), true);
    const restored = await loadOrCreatePairing(file, false);
    assert.equal(restored.plaintextToken, upgraded.plaintextToken);
    server = createLiveCueServer(pairingHashes(restored.config));
    await new Promise<void>(resolve => server!.listen(0, "127.0.0.1", resolve));
    const base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
    for (const token of [oldToken, upgraded.plaintextToken]) {
      assert.equal((await fetch(base + "/v1/health", { headers: { Authorization: `Bearer ${token}` } })).status, 200);
    }
    assert.equal((await fetch(base + "/v1/health", { headers: { Authorization: "Bearer not-paired" } })).status, 401);
  } finally {
    if (server) { server.closeAllConnections(); await new Promise<void>(resolve => server!.close(() => resolve())); }
    await rm(directory, { recursive: true, force: true });
  }
});
